# حجم APK — 2.3.0 (أرقام مقاسة على ملفات موقّعة)

| البناء | arm64 (B) | armv7 (B) |
|---|---|---|
| 2.2.0 المنشور (ML Kit مدمج) | 26,584,275 | 22,634,351 |
| 2.3.0 مدمج (للمقارنة) | 26,585,479 | 22,684,707 |
| 2.3.0 + unbundled | 20,657,438 | 18,444,216 |
| **2.3.0 + unbundled + `--split-debug-info`** (المنشور) | **19,543,374** | **17,084,392** |

- unbundled أزال `libbarhopper_v3.so` (−4.9MB arm64) وموارد ML Kit.
- `--split-debug-info=build/symbols` نقل رموز Dart خارج `libapp.so` (−1.1MB arm64). الرموز لا تُرفع (تُحفظ محلياً لفك تتبّع الأعطال).
- المتبقي: `libflutter.so` 11.0MB (المحرك، ثابت) + `libapp.so` ≈ 6.4MB.

البناء:
```bash
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --split-debug-info=build/symbols
```
