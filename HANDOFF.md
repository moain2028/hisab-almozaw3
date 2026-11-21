# HANDOFF — تسليم العمل لجلسة/وكيل جديد

> **اقرأ هذا الملف أولاً.** آخر تحديث: نهاية جلسة 2.3.0 (عمل غير مكتمل — مرفوع كما هو).

## 0) الحالة بسطر واحد
**2.4.0 منشور**: هوية بنفسجي/ذهبي (مثل «كتاب البيت»)، APK مضغوط arm64 **9.1MB** / armv7 **8.8MB** (يُفك عند التثبيت، ADR 0012). analyze = 0 · test = 57.
مسار التحديث مُتحقَّق بكود 2.2.0 نفسه مقابل update.json الحي (متاح + HTTP 200 + SHA مطابق).
صفحة التنزيلات (بالهوية الجديدة): https://moain2028.github.io/hisab-almozaw3-dist/ (فرع gh-pages).
**البناء الآن خطوتان:** `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64 --split-debug-info=build/symbols` ثم `python3 tool/zopfli_apk.py IN OUT --ks android/release-key.jks --props android/key.properties` لكل ملف.
التالي: لوحة الأجهزة (ADR 0011) — تنتظر Cloudflare API Token + Account ID.

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

## منصة النشر (2026-11-21)
النشر والتحديث والترخيص والتحكم بالأجهزة لكل التطبيقات صار عبر المستودع الخاص **[moain2028/alabbasi-publish](https://github.com/moain2028/alabbasi-publish)** («صفحة المنشورات»):
- `https://api.alabbasi.uk/v1/apps/hisab-almozaw3/{update.json,license.json,ping}`
- لوحة الأجهزة: `https://admin.alabbasi.uk` (Access OTP) · التنزيلات: `https://downloads.alabbasi.uk`
- كل الأسرار (Cloudflare، ADMIN_TOKEN، مفتاح توقيع هذا التطبيق وكود الترخيص) في `alabbasi-publish/secrets/`.
- **2.5.0 منشور** ويقرأ من المنصة أولاً. النسخ ≤2.4.0 ما زالت تقرأ من `hisab-almozaw3-dist`، لذا حدّث المكانين في كل إصدار. `release-flutter.sh` في المنصة يفعل ذلك تلقائياً.
- **الإصدار التالي بأمر واحد** (من مستودع المنصة): ارفع `version` في pubspec.yaml ثم
  `bash scripts/release-flutter.sh hisab-almozaw3 ~/flutter_app moain2028/hisab-almozaw3-dist "ما الجديد"`
- التالي: نسخ احتياطي إلى Google Drive (ADR 0013). يحتاج من المالك إنشاء OAuth Android client في Google Cloud (الحزمة + SHA-1 `8A:F2:BC:CA:C3:D9:E8:47:57:79:2E:AF:92:7A:25:79:08:E2:39:C5`).
