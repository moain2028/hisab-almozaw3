# AGENTS.md — حساب الموزع
## ابدأ هنا
1. `STATUS.md` ثم `docs/design/architecture.md`.
## الأوامر
- تثبيت: `flutter pub get` · فحص: `flutter analyze` · اختبار: `flutter test` · قياس: `flutter test test/ledger_index_test.dart -r expanded`
- APK: `flutter build apk --release --split-per-abi` · ويب: `flutter build web --release`
## القواعد
- Flutter 3.35.x / Dart 3.9.x **ثابتة** — لا ترقية حزم بدون اختبار كامل.
- المحاسبة المرجعية في `lib/data/ledger.dart` لا تُحذف: هي معيار صحة الفهرس.
- أي رقم أداء يُعلن يأتي من اختبار قابل للإعادة.
- قرار ← `docs/adr/` · مشكلة > 30 دقيقة ← `LESSONS.md`.
