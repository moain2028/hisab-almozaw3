#!/usr/bin/env python3
"""يولّد update.json من ملفات APK المقسّمة (SHA-256 + الحجم + versionCode لكل معمارية).

الاستخدام:
  python3 tool/make_update_json.py --version 2.2.0 --build 220 \
     --base https://github.com/moain2028/hisab-almozaw3-dist/releases/download/v2.2.0 \
     --arm64 dist/hisab-almozaw3-2.2.0-arm64.apk --armv7 dist/hisab-almozaw3-2.2.0-armv7.apk \
     --notes "ما الجديد" [--min-build 0] > update.json

versionCode = 1000×ABI + build  (armv7=1, arm64=2) — نفس صيغة Flutter split-per-abi.
"""
import argparse, datetime, hashlib, json, os

ABI = {"armv7": 1, "arm64": 2}

def sha(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for b in iter(lambda: f.read(1 << 20), b""):
            h.update(b)
    return h.hexdigest()

a = argparse.ArgumentParser()
a.add_argument("--version", required=True)
a.add_argument("--build", type=int, required=True)
a.add_argument("--base", required=True)
a.add_argument("--arm64")
a.add_argument("--armv7")
a.add_argument("--notes", default="")
a.add_argument("--min-build", type=int, default=0)
o = a.parse_args()

apks, codes = {}, {}
for k in ABI:
    p = getattr(o, k)
    if not p:
        continue
    apks[k] = {"url": f"{o.base.rstrip('/')}/{os.path.basename(p)}", "sha256": sha(p), "size": os.path.getsize(p)}
    codes[k] = ABI[k] * 1000 + o.build
print(json.dumps({
    "version": o.version, "build": o.build, "versionCodes": codes, "apks": apks,
    "notes": o.notes, "publishedAt": datetime.date.today().isoformat(), "minSupportedBuild": o.min_build,
}, ensure_ascii=False, indent=2))
