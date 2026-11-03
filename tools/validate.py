#!/usr/bin/env python3
"""Validate manifest/config/index theo schema + các luật mà JSON Schema không diễn tả được.
Dùng:  python3 tools/validate.py manifest <file> | config <file> | index <file> | all
"""
import json, re, sys
from pathlib import Path
from jsonschema import Draft7Validator

ROOT = Path(__file__).resolve().parent.parent
SCHEMAS = {k: json.loads((ROOT / "docs" / f"{k}.schema.json").read_text()) for k in ("manifest", "config", "index")}

def schema_errors(kind, data):
    v = Draft7Validator(SCHEMAS[kind])
    return [f"{'/'.join(map(str, e.absolute_path)) or '<root>'}: {e.message}" for e in sorted(v.iter_errors(data), key=lambda e: list(e.absolute_path))]

def no_dotdot(data, path="<root>"):
    out = []
    if isinstance(data, str):
        if ".." in data or data.startswith("/") or "\\" in data:
            out.append(f"{path}: chứa '..', '/' đầu chuỗi hoặc '\\'")
    elif isinstance(data, dict):
        for k, v in data.items(): out += no_dotdot(v, f"{path}/{k}")
    elif isinstance(data, list):
        for i, v in enumerate(data): out += no_dotdot(v, f"{path}/{i}")
    return out

def manifest_rules(m):
    e = []
    ids = [f["id"] for f in m["functions"]]
    if len(ids) != len(set(ids)): e.append("functions: id trùng")
    for f in m["functions"]:
        if f["defaultObject"] not in f["objects"]:
            e.append(f"functions/{f['id']}: defaultObject không nằm trong objects")
    keys = [o["key"] for o in m["options"]]
    if len(keys) != len(set(keys)): e.append("options: key trùng")
    for o in m["options"]:
        t, d = o["type"], o["default"]
        if t in ("int", "float") and not (o["min"] <= d <= o["max"]): e.append(f"options/{o['key']}: default ngoài [min,max]")
        if t == "intlist" and not all(o["min"] <= x <= o["max"] for x in d): e.append(f"options/{o['key']}: phần tử default ngoài [min,max]")
        if t in ("int", "float", "intlist") and o["min"] > o["max"]: e.append(f"options/{o['key']}: min > max")
        if t == "enum" and d not in o["values"]: e.append(f"options/{o['key']}: default không nằm trong values")
    acts = [k["action"] for k in m["keybinds"]]
    if len(acts) != len(set(acts)): e.append("keybinds: action trùng")
    keycaps = [k["default"].upper() for k in m["keybinds"] if k["action"] not in ("confirm", "cancel")]
    if len(keycaps) != len(set(keycaps)): e.append("keybinds: phím mặc định trùng nhau")
    cancel = [k for k in m["keybinds"] if k["action"] == "cancel"]
    if not cancel or cancel[0]["default"] != "Escape" or not cancel[0].get("locked"):
        e.append("keybinds: bắt buộc có action 'cancel' = Escape và locked")
    if "{dir}" not in m["run"]: e.append("run: thiếu {dir}")
    if m["ipc_target"] != f"sumi-{m['id']}": e.append("ipc_target phải là sumi-<id>")
    e += no_dotdot({k: v for k, v in m.items() if k != "description"})
    return e

def check(kind, path):
    data = json.loads(Path(path).read_text())
    errs = schema_errors(kind, data)
    if not errs:
        if kind == "manifest": errs += manifest_rules(data)
        if kind == "index":
            ids = [a["id"] for a in data["apps"]]
            if len(ids) != len(set(ids)): errs.append("apps: id trùng")
            for a in data["apps"]:
                if not a["repo"].rsplit("/", 1)[1] == f"sumi-{a['id']}": errs.append(f"apps/{a['id']}: tên repo phải là sumi-<id>")
        if kind == "config": errs += no_dotdot(data.get("hub", {}))
    return errs

def main():
    a = sys.argv[1:]
    jobs = []
    if a and a[0] != "all": jobs = [(a[0], a[1])]
    else:
        ex = ROOT / "examples"
        jobs = [("manifest", ex / "kakunin.manifest.json"), ("manifest", ex / "jigen.manifest.json"),
                ("index", ex / "index.json"), ("config", ex / "config.json")]
    bad = 0
    for kind, p in jobs:
        errs = check(kind, p)
        print(("FAIL " if errs else "OK   ") + f"{kind:9} {Path(p).name}")
        for x in errs: print("     -", x)
        bad += bool(errs)
    sys.exit(1 if bad else 0)

if __name__ == "__main__":
    main()
