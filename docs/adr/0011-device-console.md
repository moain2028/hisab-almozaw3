# ADR 0011 — بوابة الدومين: مستودعات خاصة + لوحة الأجهزة (مقترح، ينتظر Cloudflare Token)

## القرار المقترح
1. **كل المستودعات خاصة** (المصدر، التوزيع، الأسرار).
2. **Worker** على `api.alabbasi.uk` = البوابة الوحيدة التي يكلّمها التطبيق:
   - `GET /hisab/update.json` و `/hisab/license.json`: يقرأها من المستودع الخاص بـ GitHub token **للقراءة فقط** محفوظ كـ Secret في Cloudflare (ليس داخل التطبيق).
   - `GET /hisab/apk/<file>`: ملفات APK من **R2** (تخزين Cloudflare) — Releases المستودع الخاص لا تُنزَّل بدون مفتاح.
   - `POST /hisab/ping`: نبضة الجهاز `{id عشوائي, model, version, abi}` → D1. يرد بحالة الجهاز `active`.
3. **Pages** على `admin.alabbasi.uk`: قائمة الأجهزة + قفل/فتح لكل جهاز وللكل. و`downloads.alabbasi.uk` لصفحة التنزيلات (GitHub Pages لا يعمل على مستودع خاص في الخطة المجانية).
4. **الدخول للوحة:** Cloudflare Access (مجاني حتى 50 مستخدماً): «الدخول بـ Google» أو رمز لمرة واحدة يرسله **Cloudflare** لبريد المالك. لا كلمة مرور في الصفحة، لا رمز تطبيقات Gmail، ولا يرى المطوّر أي رمز.
5. لا مساس بصفحات الدومين الأخرى: نطاقات فرعية جديدة فقط.

## الانتقال (مهم)
النسخ المثبّتة 2.2–2.4 تقرأ من GitHub العام مباشرة. لو صار المستودع خاصاً فوراً: لن ترى التحديثات وستبقى على آخر حالة ترخيص معروفة.
⇒ 2.5.0 يقرأ من `api.alabbasi.uk` (والـ GitHub كبديل مؤقت) → ننتظر انتقال الأجهزة → نجعل `hisab-almozaw3-dist` خاصاً.
مستودع المصدر `hisab-almozaw3` يمكن جعله خاصاً **الآن** بلا أي أثر على التطبيق.

## المطلوب من المالك
Cloudflare API Token (Workers Scripts: Edit، Pages: Edit، D1: Edit، R2: Edit، Access: Edit، DNS: Edit على alabbasi.uk) + Account ID.
