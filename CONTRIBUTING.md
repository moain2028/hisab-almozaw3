# المساهمة
- الفروع: `feat/…` `fix/…` `perf/…` `docs/…` · Commits: [Conventional Commits](https://www.conventionalcommits.org/) (`feat: …` `fix: …` `perf: …`).
- قبل أي PR:
  ```bash
  dart format -l 120 lib test
  flutter analyze        # بلا أي ملاحظة
  flutter test           # كل الاختبارات
  ```
- **قواعد الكود**
  - لا حسابات أرصدة داخل الشاشات؛ كل رقم من `Store`.
  - أي تغيير في `ledger.dart` أو `ledger_index.dart` ← اختبار مطابقة مع المرجع.
  - أي تغيير في صيغة البيانات ← رفع `kSchemaVersion` + ترحيل + اختبار استيراد النسخة القديمة.
  - لا `print`؛ `debugPrint` داخل `kDebugMode` فقط. لا `withOpacity` (استخدم `withValues`).
  - النصوص للمستخدم بالعربية البسيطة (انظر docs/design/ux-review.md).
- تعريف "مكتمل": كود + اختبار + توثيق + CHANGELOG + STATUS محدّث. قرار معماري ← `docs/adr/`. مشكلة > 30 دقيقة ← `LESSONS.md`.
