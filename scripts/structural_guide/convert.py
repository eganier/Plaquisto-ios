"""Reproducible offline TEED conversion. Downloads weights only, never images.
Run in a venv: torch==2.8.0 coremltools==8.3.0 numpy<2 onnx==1.19.1.
The source model is MIT licensed; see vendor/LICENSE and README.md.
"""
from pathlib import Path
import hashlib
import urllib.request
import numpy as np
import torch
from torch import nn
import coremltools as ct
from vendor.ted import TED

ROOT = Path(__file__).resolve().parents[2]
DEST = ROOT / 'Plaquisto/PlaquistoCore/Tools/GuideModels'
SHA = 'd0109e7f40e7d9f1f495d34947eb08167e8fbb0a13b4e6ab3121261fb8d5a416'
URL = 'https://raw.githubusercontent.com/xavysp/TEED/40fa4b1391dc6424f88989d0ca75d5b592c8681d/checkpoints/BIPED/7/7_model.pth'

class PortableGuide(nn.Module):
    def __init__(self, weights):
        super().__init__()
        self.detector = TED()
        self.detector.load_state_dict(torch.load(weights,map_location='cpu',weights_only=True))
        self.detector.block_cat.PSconv1 = nn.Identity()  # PixelShuffle(1) is exactly identity.
        self.register_buffer('mean',torch.tensor([104.007,116.669,122.679]).reshape(1,3,1,1))
    def forward(self, rgb):
        bgr = torch.cat([rgb[:,2:3],rgb[:,1:2],rgb[:,0:1]],dim=1)*255-self.mean
        return torch.sigmoid(self.detector(bgr)[-1])

if __name__ == '__main__':
    import tempfile
    torch.set_num_threads(4)
    DEST.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='plaquisto-teed-') as tmp:
        weights = Path(tmp)/'model.pth'
        urllib.request.urlretrieve(URL,weights)
        assert hashlib.sha256(weights.read_bytes()).hexdigest() == SHA
        model = PortableGuide(weights).eval()
        example = torch.zeros(1,3,512,512)
        traced = torch.jit.trace(model,example)
        converted = ct.convert(traced,convert_to='neuralnetwork',
            inputs=[ct.TensorType(name='rgb',shape=example.shape)],
            outputs=[ct.TensorType(name='edges')],minimum_deployment_target=ct.target.iOS14)
        converted.author = 'Xavier Soria Poma et al. (TEED); Plaquisto adapter'
        converted.license = 'MIT — see StructuralContours-LICENSE.txt'
        converted.short_description = 'Local structural edge probabilities. RGB NCHW 0...1, 512 square with preserved-aspect letterbox.'
        converted.save(str(DEST/'StructuralContours.mlmodel'))
        torch.onnx.export(model,example,str(DEST/'StructuralContours.onnx'),
                          input_names=['rgb'],output_names=['edges'],opset_version=17,dynamo=False)
        # Check that the portable model really matches the iOS export.
        import onnxruntime as ort
        values = np.random.default_rng(7).random((1,3,512,512),dtype=np.float32)
        a = converted.predict({'rgb':values})['edges']
        b = ort.InferenceSession(str(DEST/'StructuralContours.onnx'),providers=['CPUExecutionProvider']).run(None,{'rgb':values})[0]
        error = float(np.max(np.abs(a-b)))
        print('CoreML/ONNX max abs difference:',error)
        assert error < 0.025, error
