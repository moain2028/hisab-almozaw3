# ADR 0010 — ماسح الباركود عبر Google Play Services (unbundled)

- الحالة: مقبول (2.3.0) — يعكس قرار 2.2.0 (المدمج).
- القرار: `dev.steenbakker.mobile_scanner.useUnbundled=true` في `android/gradle.properties` + `com.google.mlkit.vision.DEPENDENCIES=barcode` في المانيفست (تنزيل النموذج مبكراً عند التثبيت).
- السبب: طلب المستخدم حجماً أصغر. المقاس: arm64 26.6MB ← 19.5MB، armv7 22.7MB ← 17.1MB (انظر `docs/design/apk-size-2.3.0.md`).
- الثمن: الماسح يحتاج Google Play Services وإنترنت مرة واحدة لتنزيل النموذج (~2–3MB تُدار من GMS، مشتركة بين التطبيقات). على جوال بلا GMS تظهر رسالة خطأ واضحة + **إدخال يدوي** (باقي التطبيق يعمل).
- التراجع: احذف السطر من `gradle.properties` وأعد البناء.
