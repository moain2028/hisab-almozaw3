# HANDOFF — تسليم العمل لجلسة/وكيل جديد

> **اقرأ هذا الملف أولاً.** آخر تحديث: نهاية جلسة 2.3.0 (عمل غير مكتمل — مرفوع كما هو).

## 0) الحالة بسطر واحد
الكود **يبني ونظيف** (`flutter analyze` = 0 مشاكل). الإصدار المنشور للمستخدمين = **2.2.0**.
الكود الحالي في `main` = **2.3.0 قيد العمل** (إعادة هيكلة الواجهة) — **لم يُبنَ له APK ولم يُنشر بعد**، ولم تُشغَّل كل الاختبارات بعد التعديلات الأخيرة.

## 1) المشروع
- تطبيق Flutter **أندرويد فقط** (حُذفت ios/linux/macos/windows في 2.3.0؛ مجلد `web/` باقٍ للمعاينة فقط).
- الاسم: «حساب الموزع» · الحزمة `com.hisabalmozaw3.distributor` · Flutter **3.35.4** / Dart **3.9.2** (مقفلة).
- الفكرة: موزع ألبان (زبادي/حقين) يستلم من التاجر صباحاً، يوزّع على البقالات، يحصّل ليلاً، يدفع للتاجر صباح الغد.
- التخزين: Hive محلي + فهارس Prefix-sum (انظر `docs/design/architecture.md`, ADR 0001–0004).

## 2) المستودعات (منظومة 3 مستودعات)
| المستودع | الرؤية | المحتوى |
|---|---|---|
| `moain2028/hisab-almozaw3` | عام | الكود + التوثيق (هذا) |
| `moain2028/hisab-almozaw3-dist` | عام | `hisab-almozaw3/license.json` (هاش فقط) + `update.json` + Releases APK |
| `moain2028/hisab-almozaw3-secrets` | **خاص** | `android/release-key.jks` + `android/key.properties` + `license/license-code.md` (الكود الحقيقي وهاشه) |

**للبناء الموقّع:** انسخ `release-key.jks` و `key.properties` من المستودع الخاص إلى `android/` (مُستثناة في `.gitignore`). بدون نفس المفتاح **لن يقبل أندرويد التحديث** فوق 2.2.0.

## 3) ما أُنجز في 2.3.0 (مرفوع، غير منشور)
بناءً على شكاوى المستخدم (لقطات شاشة داكنة):
1. **إصلاح تباين الشرائح** (خط أسود على خلفية داكنة): السبب `chipTheme.labelStyle` بلا لون → `lib/ui/theme.dart`. أُضيف `test/contrast_test.dart` (فحص WCAG آلي — مُتحقَّق أنه يكشف الخطأ القديم 1.14:1 ويمر بعد الإصلاح).
2. **الرئيسية ثابتة بلا قائمة طويلة** `lib/screens/today_screen.dart`: يوم + بطاقة بطلة + شبكة إجراءات 3×2 (عطاء، تحصيل، استلام، مصروف، **صنف جديد**، بقالة جديدة) + تقدّم اليوم + زر «فتح سجل اليوم».
3. **سجل اليوم صفحة مستقلة** `lib/screens/day_log_screen.dart` برأس **مثبّت** (يوم + عطاء/تحصيل + بحث + فلتر «لم يُعطَ/لم يدفع»).
4. مكونات مشتركة نُقلت إلى `lib/screens/day_widgets.dart` (HeroCard, StockCard, DeliverTile, CollectTile, ExpenseDialog).
5. **رأس مثبّت عام** `lib/ui/pinned.dart` (`PinnedHeader`) — مطبّق على: البقالات (مجموع + بحث + ترتيب)، التاجر (رصيد + استلام/دفعة/إرجاع)، التقارير (الفترة).
6. **التقارير بهيكلية تطبيق** `lib/screens/reports_screen.dart`: فترة مثبتة + صافي الربح + شبكة 2×2 + أقسام تفتح صفحات (تفاصيل الربح، الأصناف، البقالات، يومياً، المصاريف).
7. **تواصل مع المطوّر**: `lib/core/developer.dart` (+967770941666، alabbasi.uk، downloads.alabbasi.uk) + `lib/screens/developer_screen.dart` + روابط في القائمة الجانبية والإعدادات + زر «اطلب الكود (واتساب)» في شاشة قفل الترخيص.
8. حذف منصات غير أندرويد.

## 4) المتبقي (بالترتيب المقترح)
- [ ] **تشغيل كل الاختبارات** `flutter test` وإصلاح ما يلزم. `test/ui_audit_test.dart` يعتمد على نصوص القائمة الجانبية ('الأصناف والأسعار','المصاريف','الإعدادات') وقد يحتاج تحديثاً للرئيسية الجديدة. أضف «سجل اليوم» و«تواصل مع المطوّر» لمسار التدقيق.
- [ ] **دمج فحص التباين داخل `ui_audit_test`** لكل الشاشات بالوضعين الفاتح والداكن (حالياً contrast_test يغطي الشرائح/الأزرار/نموذج الصنف فقط).
- [ ] **تصغير APK**: ماسح الباركود يضيف ~4.9MB (`libbarhopper_v3.so`). الخيار: `dev.steenbakker.mobile_scanner.useUnbundled=true` في `android/gradle.properties` (يستخدم Google Play Services، أصغر بكثير، لكن يحتاج GMS). القرار للمستخدم: يريد حجماً صغيراً وأندرويد فقط. البناء: `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`.
- [ ] رفع الإصدار إلى `2.3.0+230` في `pubspec.yaml` و `kAppVersion` في `lib/ui/theme.dart`.
- [ ] بناء APK موقّع → Release `v2.3.0` في `hisab-almozaw3-dist` → `python3 tool/make_update_json.py ...` → رفع `update.json` → التحقق من SHA-256 بعد التنزيل.
- [ ] **صفحة التنزيلات `downloads.alabbasi.uk`** (Cloudflare Pages، مشروع جديد مستقل — الدومين فيه صفحات كثيرة فلا تلمس غيرها): صفحة عربية RTL لكل تطبيقات المطوّر (اسم، نوع، إصدار، حجم، زر تنزيل arm64/armv7، تعليمات التثبيت). المحتوى يُقرأ من `update.json`. **مانع:** المفتاح الذي أرسله المستخدم (`db12…` 37 حرفاً) هو **Global API Key** ويحتاج بريد حساب Cloudflare (جُرّبت manusdate@gmail.com و moain2028@gmail.com وفشلت). المطلوب من المستخدم: **API Token** (صلاحيات: Pages Edit + DNS Edit على zone alabbasi.uk) أو البريد الصحيح.
- [ ] لقطات شاشة جديدة `docs/screenshots/` + تحديث README/CHANGELOG/STATUS + ADR 0008 (رئيسية ثابتة + رؤوس مثبتة) + ADR 0009 (أندرويد فقط).
- [ ] اختبار يدوي على جوال حقيقي: الباركود، التحديث عن بعد (يظهر عند نشر 2.3.0 فوق 2.2.0)، قفل الترخيص.

## 5) أوامر سريعة
```bash
flutter pub get && flutter analyze && flutter test
flutter build web --release   # معاينة فقط
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64
python3 tool/license_hash.py NEW-CODE          # هاش كود ترخيص جديد → codeHash في dist
python3 tool/make_update_json.py --help         # توليد update.json
```

## 6) قواعد العمل (من المستخدم)
- الرد بالعربية، مختصر، **لا تقل "تم" بدون تحقق فعلي**.
- **أي سر (كود ترخيص، كلمة مرور، مفتاح) → المستودع الخاص فقط**، والعام يحمل الهاش فقط. وثّق كل كود/هاش جديد في `hisab-almozaw3-secrets/license/license-code.md`.
- كل تغيير يُوثَّق ويُرفع إلى GitHub أولاً بأول (Conventional Commits).
- هيكلية **تطبيق** لا صفحة ويب: رؤوس مثبتة، الرئيسية مختصرة، القوائم الطويلة في صفحاتها.
- أهداف لمس ≥ 48dp، صفر overflow، تباين ≥ 4.5:1 للنص.

## 7) أمان — مطلوب من المستخدم
- **ألغِ** GitHub token `ghp_GmLM…` و Cloudflare key `db12…` — كلاهما ظهر في المحادثة.
