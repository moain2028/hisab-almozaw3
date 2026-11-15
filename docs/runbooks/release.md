# دليل الإصدار
## 1. مرة واحدة: إنشاء مفتاح التوقيع
```bash
keytool -genkey -v -keystore ~/hisab-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias hisab
```
أنشئ `android/key.properties` (**لا يُرفع للمستودع**):
```properties
storeFile=/home/<you>/hisab-release.jks
storePassword=…
keyAlias=hisab
keyPassword=…
```
> ⚠️ احتفظ بالمفتاح وكلمة المرور في مكان آمن. بدونهما لا يمكن تحديث التطبيق على الأجهزة المثبّت عليها.

## 2. قبل كل إصدار
1. ارفع `version:` في `pubspec.yaml` (مثلاً `2.1.0+3`؛ الرقم بعد `+` يجب أن يزيد دائماً).
2. `dart format -l 120 lib test && flutter analyze && flutter test`
3. حدّث `CHANGELOG.md` و `STATUS.md`.

## 3. البناء
```bash
flutter build apk --release --split-per-abi   # ملفات أصغر لكل معالج (للتوزيع المباشر)
flutter build appbundle --release             # لـ Google Play
```
الناتج في `build/app/outputs/`. للأجهزة الحديثة يكفي `app-arm64-v8a-release.apk`.

## 4. الوسم
```bash
git tag -a v2.1.0 -m "v2.1.0" && git push origin v2.1.0
```
