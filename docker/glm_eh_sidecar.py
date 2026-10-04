"""Fetch GLM-5.3's unquantized MTP eh_proj weight for EXL3_MTP_EH_FP16.

usage: glm_eh_sidecar.py <hf repo> <out.safetensors>
Same output as tools/glm/mtp_eh_sidecar.py, but reads the one 64 MiB tensor
with HTTP range requests instead of downloading its 4 GB+ shard.
"""
import json, os, struct, sys
from urllib.request import Request, urlopen

repo, out = sys.argv[1], sys.argv[2]
base = f"https://huggingface.co/{repo}/resolve/main/"
wm = json.load(urlopen(base + "model.safetensors.index.json"))["weight_map"]
keys = [k for k in wm if k.endswith("eh_proj.weight")]
assert len(keys) == 1, keys
key, url = keys[0], base + wm[keys[0]]

def get(a, b):
    return urlopen(Request(url, headers={"Range": f"bytes={a}-{b}"})).read()

n = struct.unpack("<Q", get(0, 7))[0]
t = json.loads(get(8, 7 + n))[key]
assert t["dtype"] in ("BF16", "F16"), f"{key}: {t['dtype']}"
start, end = t["data_offsets"]
data = get(8 + n + start, 7 + n + end)
assert len(data) == end - start
hdr = json.dumps({key: {"dtype": t["dtype"], "shape": t["shape"], "data_offsets": [0, len(data)]}}).encode()
hdr += b" " * (-len(hdr) % 8)
tmp = out + ".tmp"
with open(tmp, "wb") as f:
    f.write(struct.pack("<Q", len(hdr)) + hdr + data)
os.replace(tmp, out)
print(key, t["shape"], t["dtype"], "->", out)
