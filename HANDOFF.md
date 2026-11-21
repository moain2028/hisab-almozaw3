# HANDOFF — تسليم العمل لجلسة/وكيل جديد

> **اقرأ هذا الملف أولاً.** آخر تحديث: نهاية جلسة 2.3.0 (عمل غير مكتمل — مرفوع كما هو).

## 0) الحالة بسطر واحد
**2.3.1 منشور** (Release `v2.3.1` + `update.json` حي، SHA-256 متحقق، نفس مفتاح التوقيع). analyze = 0 · test = 57 ناجحة. تدقيق شامل في `docs/design/audit-2.3.1.md`.
صفحة التنزيلات **منشورة على GitHub Pages**: https://moain2028.github.io/hisab-almozaw3-dist/ · الدومين downloads.alabbasi.uk ما زال ينتظر Cloudflare Token.
التحديث من 2.2.0 → 2.3.1 مُتحقَّق بكود 2.2.0 نفسه مقابل update.json الحي (متاح + تنزيل 200 + SHA مطابق). لم يُجرَّب التثبيت على جوال.
لقطات المراجعة: `flutter test test/screenshots_test.dart --run-skipped --update-goldens` → `test/goldens/`.

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

## 4) المتبقي (بالترتيب)
- [x] analyze + test (أُصلح 5 حالات overflow + تباين الوضع الداكن؛ التباين مدموج في `ui_audit_test` لكل الشاشات فاتح/داكن؛ سجل اليوم وتواصل المطوّر في المسار).
- [x] تصغير APK: unbundled + `--split-debug-info` → arm64 19.5MB، armv7 17.1MB (ADR 0010، `docs/design/apk-size-2.3.0.md`). الرموز في المستودع الخاص `symbols/2.3.0/`.
- [x] 2.3.0+230 بُني ونُشر + وسم `v2.3.0`.
- [ ] **نشر صفحة التنزيلات** — مانع: يلزم من المستخدم **API Token** (Account › Cloudflare Pages: Edit + Zone alabbasi.uk › DNS: Edit) و**Account ID**. ثم: `CLOUDFLARE_API_TOKEN=… CLOUDFLARE_ACCOUNT_ID=… hisab-almozaw3-dist/downloads-site/deploy.sh` (مشروع مستقل `alabbasi-downloads`، يلمس سجل `downloads` فقط ويتوقف لو موجود ويشير لغيره).
- [x] لقطات حقيقية `docs/screenshots/2.3.1/` (+ كل الشاشات في `test/goldens/`).
- [ ] اختبار يدوي على جوال: التحديث 2.2.0 → 2.3.0 (يجب أن يظهر الآن)، الباركود (الآن يحتاج Google Play Services)، قفل الترخيص.

## 5) أوامر سريعة
```bash
flutter pub get && flutter analyze && flutter test
flutter build web --release   # معاينة فقط
flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --split-debug-info=build/symbols
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
