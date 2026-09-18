import SwiftUI
import AVFoundation
import ImageIO
import Darwin
import CoreImage

enum BeforeAfterDeviceIdentity {
    private static var key: String {
        var info = utsname(); uname(&info)
        let capacity = MemoryLayout.size(ofValue:info.machine)
        let hardware = withUnsafePointer(to:&info.machine) { ptr in
            ptr.withMemoryRebound(to:CChar.self,capacity:capacity) { String(cString:$0) }
        }
        return "BeforeAfter.actualCameraModel.\(hardware)"
    }
    static var knownModel: String? { UserDefaults.standard.string(forKey:key) }
    static func learn(from data: Data) {
        guard let source = CGImageSourceCreateWithData(data as CFData,nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source,0,nil) as? [String:Any],
              let model = BeforeAfterMetadataExtractor.extract(properties:properties).model else { return }
        UserDefaults.standard.set(model,forKey:key)
    }
}

/// All AVCaptureSession/device mutations are serialized off the UI thread.
final class BeforeAfterCameraController: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate, AVCaptureVideoDataOutputSampleBufferDelegate {
    struct Lens: Identifiable { let id: String; let title: String }
    let session = AVCaptureSession()
    private let queue = DispatchQueue(label:"fr.plaquisto.beforeafter.camera",qos:.userInitiated)
    private let output = AVCapturePhotoOutput()
    private let video = AVCaptureVideoDataOutput()
    private let analysisQueue = DispatchQueue(label:"fr.plaquisto.beforeafter.framing",qos:.userInitiated)
    private let imageContext = CIContext(options:[.cacheIntermediates:false])
    private var reference: CGImage?
    private var lastAnalysis = 0.0
    private var previousCorners: [BeforeAfterPoint]?
    private var analysisGeneration = -1
    private var stability = BeforeAfterCaptureStability()
    private var generation = 0
    @Published private(set) var referenceReady = false
    @Published private(set) var framing = BeforeAfterFraming.searching
    @Published private(set) var stableProgress = 0.0
    private var lastGuidanceTime = 0.0
    var canAutoCapture: Bool { ready && referenceReady && stableProgress >= 1 && ProcessInfo.processInfo.systemUptime-lastGuidanceTime < 1.0 }

    func prepareReference(_ image: UIImage) {
        guard let cg = image.cgImage else { return }
        analysisQueue.async { [weak self] in
            guard let self else { return }
            let scale = min(1,480 / CGFloat(max(cg.width,cg.height)))
            let source = CIImage(cgImage:cg).transformed(by:.init(scaleX:scale,y:scale))
            self.reference = self.imageContext.createCGImage(source,from:source.extent)
            let available = self.reference != nil
            DispatchQueue.main.async { self.referenceReady = available }
        }
    }
    func resetGuidance() { generation += 1; stability.reset(); stableProgress = 0; framing = .searching; lastGuidanceTime = 0 }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = ProcessInfo.processInfo.systemUptime
        guard now-lastAnalysis >= 0.6, let reference, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastAnalysis = now
        // Serial analysis queue + discarded late frames: never queue a video backlog.
        let token = DispatchQueue.main.sync { generation }
        let frame = CIImage(cvPixelBuffer:buffer)
        let size = CGSize(width:reference.width,height:reference.height)
        let scale = max(size.width/frame.extent.width,size.height/frame.extent.height)
        let scaled = frame.transformed(by:.init(scaleX:scale,y:scale))
        let cropped = scaled.transformed(by:.init(translationX:(size.width-scaled.extent.width)/2,y:(size.height-scaled.extent.height)/2))
        guard let image = imageContext.createCGImage(cropped,from:CGRect(origin:.zero,size:size)) else { return }
        let alignment = BeforeAfterAlignmentEngine.align(reference:reference,after:image)
        var result = BeforeAfterFraming.evaluate(alignment)
        if analysisGeneration != token { previousCorners = nil; analysisGeneration = token }
        if result.aligned {
            let steady = alignment.corners.map { current in
                previousCorners.map { previous in
                    zip(current,previous).allSatisfy { hypot($0.x-$1.x,$0.y-$1.y) < 0.012 }
                } ?? false
            } ?? false
            if !steady { result = .init(message:"Cadrage proche. Stabilisez le téléphone…") }
        }
        previousCorners = alignment.corners
        let guidance = result
        DispatchQueue.main.async {
            guard self.visible, self.ready, !self.capturing, self.generation == token else { return }
            let fresh = ProcessInfo.processInfo.systemUptime-now < 1.2
            self.framing = fresh ? guidance : .searching
            self.lastGuidanceTime = now
            self.stableProgress = self.stability.update(aligned:fresh && guidance.aligned,time:now)
        }
    }
    private var input: AVCaptureDeviceInput?
    private var devices: [AVCaptureDevice] = []
    private var configured = false
    private var wantsRunning = false
    private var pending = false
    private var captureHandler: ((Result<(Data,String),Error>) -> Void)?
    private var observers: [NSObjectProtocol] = []
    private var visible = false
    @Published private(set) var error: String?
    @Published private(set) var denied = false
    @Published private(set) var ready = false
    @Published private(set) var capturing = false
    @Published private(set) var lenses: [Lens] = []
    @Published private(set) var selectedLens = ""
    @Published private(set) var settingsSummary = "Exposition automatique. Objectif à choisir manuellement ; focale d’origine non reproduite automatiquement."
    var sourceMetadata = BeforeAfterMetadata()

    override init() {
        super.init()
        observers = [
            NotificationCenter.default.addObserver(forName:.AVCaptureSessionWasInterrupted,object:session,queue:.main) { [weak self] _ in
                self?.ready = false; self?.error = "La caméra est momentanément utilisée ailleurs. Revenez à cet écran pour réessayer."
            },
            NotificationCenter.default.addObserver(forName:.AVCaptureSessionInterruptionEnded,object:session,queue:.main) { [weak self] _ in if self?.visible == true { self?.start() } },
            NotificationCenter.default.addObserver(forName:.AVCaptureSessionRuntimeError,object:session,queue:.main) { [weak self] _ in
                self?.ready = false; self?.capturing = false; self?.error = "La caméra s’est interrompue. Fermez puis rouvrez la prise de vue."
            }
        ]
    }
    deinit { observers.forEach(NotificationCenter.default.removeObserver) }
    func start() {
        resetGuidance()
        visible = true
        switch AVCaptureDevice.authorizationStatus(for:.video) {
        case .authorized: configureAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for:.video) { [weak self] granted in
                DispatchQueue.main.async { guard self?.visible == true else { return }; granted ? self?.configureAndStart() : self?.permissionDenied() }
            }
        default: permissionDenied()
        }
    }
    private func permissionDenied() { denied = true; error = "Autorisez la caméra dans Réglages pour prendre la photo Après." }
    private func configureAndStart() {
        denied = false; error = nil
        queue.async { [weak self] in
            guard let self else { return }
            self.wantsRunning = true
            do {
                if !self.configured {
                    self.devices = AVCaptureDevice.DiscoverySession(deviceTypes:[.builtInWideAngleCamera,.builtInUltraWideCamera,.builtInTelephotoCamera],mediaType:.video,position:.back).devices
                    guard let device = self.devices.first(where: { $0.deviceType == .builtInWideAngleCamera }) ?? self.devices.first else { throw BeforeAfterError.cameraUnavailable }
                    let input = try AVCaptureDeviceInput(device:device)
                    self.session.beginConfiguration()
                    self.session.sessionPreset = .photo
                    guard self.session.canAddInput(input), self.session.canAddOutput(self.output) else {
                        self.session.commitConfiguration(); throw BeforeAfterError.cameraUnavailable
                    }
                    self.session.addInput(input); self.session.addOutput(self.output)
                    self.video.alwaysDiscardsLateVideoFrames = true
                    self.video.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String:kCVPixelFormatType_32BGRA]
                    if self.session.canAddOutput(self.video) {
                        self.session.addOutput(self.video)
                        self.video.setSampleBufferDelegate(self,queue:self.analysisQueue)
                    }
                    self.input = input
                    self.output.maxPhotoQualityPrioritization = .balanced
                    self.session.commitConfiguration(); self.configured = true
                    self.portraitCapture()
                    let lenses = self.devices.map { device in
                        Lens(id:device.uniqueID,title:device.deviceType == .builtInUltraWideCamera ? "Ultra grand-angle" : device.deviceType == .builtInTelephotoCamera ? "Téléobjectif" : "Principal")
                    }
                    DispatchQueue.main.async { self.lenses = lenses; self.selectedLens = device.uniqueID }
                }
                if !self.session.isRunning { self.session.startRunning() }
                DispatchQueue.main.async { self.ready = self.session.isRunning }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.ready = false } }
        }
    }
    private func portraitCapture() {
        if let c = output.connection(with:.video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        if let c = video.connection(with:.video), c.isVideoRotationAngleSupported(90) { c.videoRotationAngle = 90 }
        if let c = video.connection(with:.video), c.isVideoStabilizationSupported { c.preferredVideoStabilizationMode = .off }
    }
    func stop() {
        resetGuidance()
        visible = false
        ready = false
        queue.async { [weak self] in self?.wantsRunning = false; self?.session.stopRunning() }
    }
    func chooseLens(_ id: String) {
        guard !capturing else { return }
        resetGuidance()
        ready = false
        queue.async { [weak self] in
            guard let self, let device = self.devices.first(where: { $0.uniqueID == id }), let old = self.input else { return }
            do {
                let new = try AVCaptureDeviceInput(device:device)
                self.session.beginConfiguration(); self.session.removeInput(old)
                if self.session.canAddInput(new) { self.session.addInput(new); self.input = new }
                else { self.session.addInput(old) }
                self.session.commitConfiguration(); self.portraitCapture()
                DispatchQueue.main.async {
                    self.selectedLens = self.input?.device.uniqueID ?? ""; self.ready = self.session.isRunning
                    self.settingsSummary = "Exposition automatique. Objectif choisi manuellement."
                }
            } catch { DispatchQueue.main.async { self.error = error.localizedDescription; self.ready = self.session.isRunning } }
        }
    }
    func approximateExposure(enabled: Bool) {
        resetGuidance()
        let metadata = sourceMetadata
        let compatible = BeforeAfterCompatibility.check(source:metadata.model,current:BeforeAfterDeviceIdentity.knownModel) == .sameModel
        queue.async { [weak self] in
            guard let self, let device = self.input?.device else { return }
            var message = "Exposition automatique. Objectif choisi manuellement."
            do {
                try device.lockForConfiguration(); defer { device.unlockForConfiguration() }
                if enabled, compatible, let iso = metadata.iso, iso.isFinite, iso > 0,
                   let seconds = metadata.exposureSeconds, seconds.isFinite, seconds > 0, device.isExposureModeSupported(.custom) {
                    let duration = min(max(seconds,CMTimeGetSeconds(device.activeFormat.minExposureDuration)),CMTimeGetSeconds(device.activeFormat.maxExposureDuration))
                    let safeISO = min(max(Float(iso),device.activeFormat.minISO),device.activeFormat.maxISO)
                    device.setExposureModeCustom(duration:CMTime(seconds:duration,preferredTimescale:1_000_000_000),iso:safeISO)
                    message = "ISO \(Int(safeISO)) et exposition \(duration.formatted(.number.precision(.fractionLength(1...4)))) s appliqués dans les limites de cet objectif. Focale et ouverture non reproduites."
                } else if device.isExposureModeSupported(.continuousAutoExposure) { device.exposureMode = .continuousAutoExposure }
            } catch { message = "Réglages non importés : exposition automatique conservée." }
            DispatchQueue.main.async { self.settingsSummary = message }
        }
    }
    func capture(completion: @escaping (Result<(Data,String),Error>) -> Void) {
        guard ready, !capturing else { return }
        capturing = true; captureHandler = completion
        queue.async { [weak self] in
            guard let self else { return }
            guard self.wantsRunning, self.session.isRunning, !self.pending else {
                DispatchQueue.main.async { self.capturing = false; self.captureHandler?(.failure(BeforeAfterError.cameraUnavailable)); self.captureHandler = nil }; return
            }
            self.pending = true
            let settings = AVCapturePhotoSettings(format:[AVVideoCodecKey:AVVideoCodecType.jpeg])
            settings.photoQualityPrioritization = .balanced
            self.output.capturePhoto(with:settings,delegate:self)
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        let data = error == nil ? photo.fileDataRepresentation() : nil
        if let data { BeforeAfterDeviceIdentity.learn(from:data) }
        DispatchQueue.main.async {
            self.capturing = false
            if let data { self.captureHandler?(.success((data,self.settingsSummary))) }
            else { self.captureHandler?(.failure(error ?? BeforeAfterError.invalidImage)) }
            self.captureHandler = nil
        }
    }
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        queue.async { self.pending = false }
        if let error { DispatchQueue.main.async { self.capturing = false; self.captureHandler?(.failure(error)); self.captureHandler = nil } }
    }
}

private final class BeforeAfterPreviewUIView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var preview: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    override func layoutSubviews() {
        super.layoutSubviews()
        if let connection = preview.connection, connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
    }
}
private struct BeforeAfterCameraPreview: UIViewRepresentable {
    let session: AVCaptureSession
    func makeUIView(context: Context) -> BeforeAfterPreviewUIView {
        let view = BeforeAfterPreviewUIView(); view.preview.session = session; view.preview.videoGravity = .resizeAspectFill; return view
    }
    func updateUIView(_ uiView: BeforeAfterPreviewUIView, context: Context) { uiView.setNeedsLayout() }
}

private struct BeforeAfterOpacitySlider: View {
    @Binding var value:Double
    var body: some View {
        GeometryReader { geometry in
            let travel = geometry.size.height-24
            let fraction = min(1,max(0,value/0.8))
            ZStack(alignment:.bottom) {
                Capsule().fill(.white.opacity(0.25)).frame(width:5).padding(.vertical,12)
                Capsule().fill(.white).frame(width:5,height:max(0,travel*fraction)).padding(.bottom,12)
                Circle().fill(.white).frame(width:24,height:24).offset(y:-travel*fraction)
            }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.bottom)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance:0).onChanged {
                    value = min(0.8,max(0,(1-($0.location.y-12)/travel)*0.8))
                })
        }.frame(width:44,height:180)
            .accessibilityElement().accessibilityLabel("Opacité de la photo Avant")
            .accessibilityValue(value.formatted(.percent))
            .accessibilityAdjustableAction { direction in
                switch direction {
                case .increment: value = min(0.8,value+0.05)
                case .decrement: value = max(0,value-0.05)
                @unknown default: break
                }
            }
    }
}

struct BeforeAfterCameraView: View {
    let before: UIImage
    let metadata: BeforeAfterMetadata
    let onCapture: (Data,String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var camera = BeforeAfterCameraController()
    @State private var showOriginalPhoto = true
    @State private var originalPhotoOpacity = 0.20
    @State private var showLiveCamera = true
    @State private var finishing = false
    @State private var preparing = false
    @State private var flash = false
    @State private var captureError: String?

    private var busy: Bool { camera.capturing || finishing || preparing }
    var body: some View {
        VStack(spacing:0) {
            header
            GeometryReader { geometry in
                ZStack {
                    Color.black
                    ZStack {
                        BeforeAfterCameraPreview(session:camera.session)
                            .opacity(showLiveCamera ? 1 : 0)
                        if showOriginalPhoto {
                            Image(uiImage:before).resizable().scaledToFit()
                                .opacity(originalPhotoOpacity)
                                .allowsHitTesting(false).accessibilityHidden(true)
                        }
                    }
                    .aspectRatio(before.size.width/before.size.height,contentMode:.fit)
                    .frame(width:geometry.size.width,height:geometry.size.height)
                    .clipped()
                    VStack {
                        Spacer()
                        if let error = camera.error {
                            VStack(spacing:10) {
                                Text(error).font(.caption).multilineTextAlignment(.center)
                                if camera.denied, let url = URL(string:UIApplication.openSettingsURLString) {
                                    Link("Ouvrir Réglages",destination:url).font(.subheadline.bold())
                                } else {
                                    Button("Réessayer") { camera.start() }.font(.subheadline.bold())
                                }
                            }.padding().background(.black.opacity(0.8),in:RoundedRectangle(cornerRadius:16))
                                .padding(.horizontal,64).padding(.bottom,12)
                        } else if !camera.ready && !finishing {
                            ProgressView().tint(.white).padding(.bottom,20)
                        }
                    }
                    HStack {
                        VStack(spacing:14) {
                            sideButton(showOriginalPhoto ? "eye" : "eye.slash",
                                       label:showOriginalPhoto ? "Masquer la photo Avant" : "Afficher la photo Avant",
                                       selected:showOriginalPhoto) { showOriginalPhoto.toggle() }
                            Text("Photo\nAvant").font(.caption2).multilineTextAlignment(.center)
                            sideButton(showLiveCamera ? "video" : "video.slash",
                                       label:showLiveCamera ? "Masquer la vue actuelle" : "Afficher la vue actuelle",
                                       selected:showLiveCamera) { showLiveCamera.toggle() }
                            Text("Vue\nactuelle").font(.caption2).multilineTextAlignment(.center)
                        }.padding(.vertical,12).frame(width:56)
                            .background(.black.opacity(0.55),in:Capsule())
                        Spacer()
                        VStack(spacing:12) {
                            BeforeAfterOpacitySlider(value:$originalPhotoOpacity)
                                .disabled(!showOriginalPhoto)
                                .opacity(showOriginalPhoto ? 1 : 0.4)
                            Text(originalPhotoOpacity,format:.percent.precision(.fractionLength(0)))
                                .font(.system(size:13,weight:.semibold,design:.rounded).monospacedDigit())
                            Text("OPACITÉ").font(.system(size:9,weight:.semibold)).tracking(1)
                        }.padding(.vertical,12).frame(width:56)
                            .background(.black.opacity(0.55),in:Capsule())
                    }.padding(.horizontal,10).disabled(busy)
                }
            }
            shutterBar
        }
        .foregroundStyle(.white).background { Color.black.ignoresSafeArea() }
        .preferredColorScheme(.dark)
        .alert("Prise de vue",isPresented:Binding(get:{ captureError != nil },set:{ if !$0 { captureError = nil } })) {
            Button("OK") { captureError = nil }
        } message: { Text(captureError ?? "") }
        .task { camera.sourceMetadata = metadata; camera.start() }
        .onChange(of:phase) { _, value in if value == .active && !finishing { camera.start() } else { camera.stop() } }
        .onDisappear { camera.stop() }
        .overlay { Color.white.opacity(flash ? 0.8 : 0).ignoresSafeArea().allowsHitTesting(false) }
        .interactiveDismissDisabled(busy)
    }

    private var header: some View {
        HStack {
            sideButton("xmark",label:"Fermer l’appareil photo") { camera.stop(); dismiss() }.disabled(busy)
            Spacer()
            Text("PHOTO APRÈS").font(.system(size:13,weight:.semibold)).tracking(2)
            Spacer()
            Color.clear.frame(width:44,height:44).accessibilityHidden(true)
        }.padding(.horizontal,12).padding(.vertical,8)
    }

    private var shutterBar: some View {
        VStack(spacing:14) {
            if camera.lenses.count > 1 {
                HStack(spacing:12) {
                    ForEach(camera.lenses) { lens in
                        Button {
                            camera.chooseLens(lens.id)
                        } label: {
                            Text(lens.title).font(.caption.bold()).padding(.horizontal,12).padding(.vertical,8)
                                .background(camera.selectedLens == lens.id ? Color.white.opacity(0.25) : Color.white.opacity(0.08),in:Capsule())
                        }.accessibilityAddTraits(camera.selectedLens == lens.id ? .isSelected : [])
                    }
                }.disabled(busy || !camera.ready)
            }
            ZStack {
                HStack {
                    Image(uiImage:before).resizable().scaledToFill().frame(width:44,height:54)
                        .clipped().clipShape(RoundedRectangle(cornerRadius:8))
                        .overlay(RoundedRectangle(cornerRadius:8).stroke(.white.opacity(0.3)))
                        .accessibilityLabel("Photo Avant de référence")
                    Spacer()
                }.padding(.horizontal,28)
                Button { takePhoto() } label: {
                    ZStack {
                        Circle().stroke(.white,lineWidth:3).frame(width:80,height:80)
                        Circle().fill(.white).frame(width:66,height:66)
                        if busy { ProgressView().tint(.black) }
                    }.frame(width:88,height:88)
                }.buttonStyle(.plain).disabled(!camera.ready || busy)
                    .opacity(camera.ready && !busy ? 1 : 0.45)
                    .accessibilityLabel("Prendre la photo Après")
            }
        }.padding(.top,12).padding(.bottom,18)
    }

    private func sideButton(_ symbol:String,label:String,selected:Bool = false,action:@escaping () -> Void) -> some View {
        Button(action:action) {
            Image(systemName:symbol).font(.system(size:18,weight:.medium)).frame(width:44,height:44)
                .background(selected ? Color.white.opacity(0.25) : Color.black.opacity(0.6),in:Circle())
                .overlay(Circle().stroke(.white.opacity(0.15),lineWidth:1))
        }.buttonStyle(.plain).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func takePhoto() {
        guard !busy, camera.ready, phase == .active else { return }
        preparing = true
        performCapture()
    }
    private func performCapture() {
        camera.capture { result in
            switch result {
            case .success(let (data,summary)):
                finishing = true; camera.stop()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                flash = true
                Task { @MainActor in
                    try? await Task.sleep(for:.milliseconds(50))
                    withAnimation(.easeOut(duration:0.3)) { flash = false }
                    try? await Task.sleep(for:.milliseconds(350))
                    onCapture(data,summary); dismiss()
                }
            case .failure(let error): preparing = false; camera.resetGuidance(); captureError = error.localizedDescription
            }
        }
    }
}
