# ADR 0013 — نسخ احتياطي إلى Google Drive (مقترح)

- التجربة: زر «نسخ إلى Google Drive» → نافذة Google لاختيار الحساب → رفع ملف `.hisab` (نفس صيغة النسخ المحلي، SHA-256) إلى مجلد «حساب الموزع» في درايف المستخدم. استرجاع: قائمة النسخ من درايف.
- الصلاحية: `drive.file` فقط (يرى التطبيق ملفاته هو فقط، ليست صلاحية حساسة ⇒ لا مراجعة أمنية من Google).
- يحتاج: Google Play Services على الجوال (مثل الماسح).
- إعداد المالك في Google Cloud Console (مجاني):
  1. مشروع جديد → تفعيل **Google Drive API**.
  2. شاشة الموافقة OAuth: External → **Publish to production** (وضع Testing يُخرج المستخدمين كل 7 أيام).
  3. Credentials → OAuth client → **Android**: الحزمة `com.hisabalmozaw3.distributor`، SHA-1 `8A:F2:BC:CA:C3:D9:E8:47:57:79:2E:AF:92:7A:25:79:08:E2:39:C5` (من مفتاح التوقيع الحالي).
- لا يُرسَل للمطوّر أي سر من Google: عميل Android يُعرَّف بالحزمة + البصمة فقط.
