#!/usr/bin/env python3
"""zopfli_apk.py — يعيد ضغط APK بأقوى ضغط Deflate متوافق مع أندرويد (Zopfli)، ثم المحاذاة والتوقيع.

لماذا: Gradle يضغط بـ zlib المستوى الافتراضي. Zopfli يُنتج Deflate قياسياً **يفكّه أي جوال** لكنه أصغر
بـ 3–8%. الفك عند التثبيت لا يتغيّر (نفس Deflate)، والوقت الإضافي فقط عند البناء.

قواعد أندرويد المحترمة:
  - resources.arsc يبقى غير مضغوط (STORED) ومحاذى 4 — إلزامي منذ Android 11 (targetSdk ≥ 30).
  - الملفات المخزّنة أصلاً (STORED) تبقى كما هي.
  - zipalign -P 16 (صفحات 16KB) ثم apksigner (v2/v3) بنفس مفتاح الإصدار.

الاستخدام:
  pip install zopfli
  python3 tool/zopfli_apk.py IN.apk OUT.apk --ks android/release-key.jks --props android/key.properties
"""
import argparse
import os
import subprocess
import sys
import tempfile
import zipfile
import zlib

import zopfli.zlib  # type: ignore

BT = os.environ.get("BUILD_TOOLS", "/home/user/android-sdk/build-tools/35.0.0")


def zopfli_raw(data: bytes, iterations: int) -> bytes:
    # zopfli.zlib يعطي zlib stream (رأس 2 بايت + adler32 4 بايت) → نأخذ Deflate الخام
    z = zopfli.zlib.compress(data, numiterations=iterations)
    return z[2:-4]


def main() -> int:
    a = argparse.ArgumentParser()
    a.add_argument("inp")
    a.add_argument("out")
    a.add_argument("--ks", required=True)
    a.add_argument("--props", required=True)
    a.add_argument("--iterations", type=int, default=15)
    o = a.parse_args()

    props = dict(
        line.strip().split("=", 1) for line in open(o.props, encoding="utf-8") if "=" in line and not line.startswith("#")
    )
    tmp = tempfile.mkdtemp()
    raw = os.path.join(tmp, "raw.apk")
    aligned = os.path.join(tmp, "aligned.apk")

    before = after = 0
    with zipfile.ZipFile(o.inp) as zin, zipfile.ZipFile(raw, "w") as zout:
        for info in zin.infolist():
            name = info.filename
            # التوقيع القديم يُحذف (يُعاد التوقيع في الأخير)
            if name.startswith("META-INF/") and name.rsplit(".", 1)[-1] in ("SF", "RSA", "EC", "DSA", "MF"):
                continue
            data = zin.read(name)
            ni = zipfile.ZipInfo(name, date_time=(1981, 1, 1, 1, 1, 2))
            ni.external_attr = info.external_attr
            if name == "resources.arsc" or info.compress_type == zipfile.ZIP_STORED:
                ni.compress_type = zipfile.ZIP_STORED
                zout.writestr(ni, data)
                continue
            before += info.compress_size
            comp = zopfli_raw(data, o.iterations)
            # لا نستخدم الأكبر أبداً
            std = zlib.compressobj(9, zlib.DEFLATED, -15)
            std_c = std.compress(data) + std.flush()
            if len(std_c) < len(comp):
                comp = std_c
            after += len(comp)
            # كتابة إدخال Deflate مضغوط مسبقاً: نستخدم واجهة zipfile الداخلية بأمان عبر _open_to_write
            ni.compress_type = zipfile.ZIP_DEFLATED
            ni.file_size = len(data)
            ni.compress_size = len(comp)
            ni.CRC = zlib.crc32(data) & 0xFFFFFFFF
            _write_precompressed(zout, ni, comp)

    subprocess.run([f"{BT}/zipalign", "-f", "-P", "16", "4", raw, aligned], check=True)
    subprocess.run(
        [
            f"{BT}/apksigner", "sign",
            "--ks", o.ks,
            "--ks-pass", f"pass:{props['storePassword']}",
            "--ks-key-alias", props["keyAlias"],
            "--key-pass", f"pass:{props['keyPassword']}",
            "--out", o.out, aligned,
        ],
        check=True,
    )
    subprocess.run([f"{BT}/apksigner", "verify", o.out], check=True)
    print(f"deflate entries: {before:,} → {after:,} B ({(before - after) / max(before, 1):.1%} أصغر)")
    print(f"APK: {os.path.getsize(o.inp):,} → {os.path.getsize(o.out):,} B")
    return 0


def _write_precompressed(zf: zipfile.ZipFile, zinfo: zipfile.ZipInfo, payload: bytes) -> None:
    """يكتب إدخالاً بـ Deflate جاهز (zipfile لا يدعم ذلك مباشرة)."""
    zf._writecheck(zinfo)  # noqa: SLF001
    zinfo.header_offset = zf.fp.tell()
    zinfo.flag_bits = 0x800 if any(ord(c) > 127 for c in zinfo.filename) else 0
    zinfo.extract_version = zinfo.create_version = 20
    zf.fp.write(zinfo.FileHeader(zip64=False))
    zf.fp.write(payload)
    zf.start_dir = zf.fp.tell()
    zf.filelist.append(zinfo)
    zf.NameToInfo[zinfo.filename] = zinfo


if __name__ == "__main__":
    sys.exit(main())
