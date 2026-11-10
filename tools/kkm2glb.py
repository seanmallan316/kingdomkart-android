#!/usr/bin/env python3
"""Turns a Wii U Kingdom Kart model (.kkm + its .png picture) into a .glb that Godot opens directly.

Each .kkm part becomes its own node, placed at its pivot, so the game can spin wheels and turn heads.
Part kinds: 0 body, 1-4 wheels (front-left, front-right, back-left, back-right), 5+ rider pieces.
Usage: kkm2glb.py model.kkm picture.png out.glb
"""
import json, struct, sys
import numpy as np

NAMES = {0: "body", 1: "wheel_fl", 2: "wheel_fr", 3: "wheel_bl", 4: "wheel_br"}


def read_kkm(path):
    b = open(path, "rb").read()
    assert b[:4] == b"KKM1", "not a .kkm file"
    n = struct.unpack(">I", b[4:8])[0]
    o, parts = 8, []
    for _ in range(n):
        kind, px, py, pz, r, cnt = struct.unpack(">I4fI", b[o:o + 24]); o += 24
        v = np.frombuffer(b, ">f4", cnt * 12, o).reshape(cnt, 12).astype(np.float32); o += cnt * 48
        parts.append((kind, (px, py, pz), r, v))
    return parts


def write_glb(parts, png, out):
    blob = bytearray(); views = []; accs = []; meshes = []; nodes = []

    def add_view(data, target=None):
        while len(blob) % 4: blob.append(0)
        v = {"buffer": 0, "byteOffset": len(blob), "byteLength": len(data)}
        if target: v["target"] = target
        blob.extend(data); views.append(v); return len(views) - 1

    def add_acc(arr, typ, minmax=False):
        a = {"bufferView": add_view(arr.tobytes(), 34962), "componentType": 5126, "count": len(arr), "type": typ}
        if minmax: a["min"] = arr.min(0).tolist(); a["max"] = arr.max(0).tolist()
        accs.append(a); return len(accs) - 1

    img_view = add_view(open(png, "rb").read())
    for kind, piv, r, v in parts:
        name = NAMES.get(kind, "rider_%d" % kind)
        node = {"name": name, "translation": [float(x) for x in piv]}
        if len(v):
            pos = np.ascontiguousarray(v[:, 0:3]); nrm = v[:, 3:6]
            nrm = np.ascontiguousarray(nrm / np.maximum(np.linalg.norm(nrm, axis=1, keepdims=True), 1e-6)).astype(np.float32)
            uv = np.ascontiguousarray(v[:, 6:8])
            prim = {"attributes": {"POSITION": add_acc(pos, "VEC3", True), "NORMAL": add_acc(nrm, "VEC3"),
                                   "TEXCOORD_0": add_acc(uv, "VEC2")}, "material": 0}
            meshes.append({"name": name, "primitives": [prim]}); node["mesh"] = len(meshes) - 1
        if kind in (1, 2, 3, 4): node["extras"] = {"wheel_radius": r}
        nodes.append(node)
    nodes.append({"name": "kart", "children": list(range(len(nodes)))})
    gl = {"asset": {"version": "2.0", "generator": "kingdomkart kkm2glb"},
          "scene": 0, "scenes": [{"nodes": [len(nodes) - 1]}], "nodes": nodes, "meshes": meshes,
          "materials": [{"name": "paint", "pbrMetallicRoughness": {"baseColorTexture": {"index": 0},
                                                                   "metallicFactor": 0.0, "roughnessFactor": 0.6}}],
          "textures": [{"source": 0, "sampler": 0}], "samplers": [{"magFilter": 9729, "minFilter": 9987}],
          "images": [{"bufferView": img_view, "mimeType": "image/png"}],
          "accessors": accs, "bufferViews": views, "buffers": [{"byteLength": 0}]}
    while len(blob) % 4: blob.append(0)
    gl["buffers"][0]["byteLength"] = len(blob)
    js = json.dumps(gl, separators=(",", ":")).encode()
    while len(js) % 4: js += b" "
    with open(out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A)); f.write(js)
        f.write(struct.pack("<II", len(blob), 0x004E4942)); f.write(blob)


if __name__ == "__main__":
    write_glb(read_kkm(sys.argv[1]), sys.argv[2], sys.argv[3])
    print("wrote", sys.argv[3])
