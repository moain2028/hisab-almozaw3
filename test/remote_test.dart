// اختبارات الترخيص والتحديث عن بعد — خادم وهمي بلا شبكة.
// تغطي كل قواعد المرجع (MoTechSys/keif_blins · diafa-apps).
import 'dart:io';

import 'package:distributor/core/license_service.dart';
import 'package:distributor/core/remote_config.dart';
import 'package:distributor/core/update_service.dart';
import 'package:distributor/data/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// خادم قابل للبرمجة: null = بلا اتصال، notFound = 404، وإلا JSON
class FakeFetcher extends RemoteFetcher {
  RemoteFile? next;
  int calls = 0;

  /// رد النبض: null = لا شبكة
  PingResult? pingNext;
  final pings = <Map<String, Object?>>[];
  @override
  Future<RemoteFile?> fetch(String file, {String? deviceId}) async {
    calls++;
    return next;
  }

  @override
  Future<PingResult?> ping(Map<String, Object?> body) async {
    pings.add(body);
    return pingNext;
  }
}

Future<Map<String, Object?>?> fakeDevice() async => {
  'version': '2.5.0',
  'build': 250,
  'abi': 'arm64',
  'sdk': 34,
  'model': 'Test X',
};

RemoteFile lic(bool active, {String code = 'ABC123', String message = 'رسالة'}) =>
    RemoteFile.ok({'active': active, 'code': code, 'message': message});

const _sha = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';

Map<String, Object?> upd({int arm64 = 2221, int armv7 = 1221, int minBuild = 0}) => {
  'version': '2.2.1',
  'build': 221,
  'versionCodes': {'arm64': arm64, 'armv7': armv7},
  'apks': {
    'arm64': {'url': 'https://example.com/a64.apk', 'sha256': _sha, 'size': 100},
    'armv7': {'url': 'https://example.com/a7.apk', 'sha256': _sha, 'size': 90},
  },
  'notes': 'جديد',
  'minSupportedBuild': minBuild,
};

const inst64 = InstalledInfo(versionCode: 2220, versionName: '2.2.0', abi: 'arm64');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Store store;
  late FakeFetcher f;
  late LicenseService l;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('remote_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    store = Store();
    await store.init();
    f = FakeFetcher();
    l = LicenseService(store, fetcher: f);
  });

  tearDown(() async {
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  group('الترخيص عن بعد', () {
    test('تثبيت جديد بلا اتصال ⇒ مفتوح (لا نقفل المستخدم بسبب الشبكة)', () async {
      f.next = null;
      final s = await l.check();
      expect(s.allowed, isTrue);
      expect(s.offline, isTrue);
    });

    test('ملف غير موجود ولم يُرَ من قبل ⇒ مفتوح (ملف لم يُرفع بعد)', () async {
      f.next = RemoteFile.notFound();
      expect((await l.check()).allowed, isTrue);
    });

    test('active=true ⇒ مفتوح', () async {
      f.next = lic(true);
      expect((await l.check()).allowed, isTrue);
    });

    test('active=false ⇒ مقفل، والكود الصحيح يفتح (بدون حساسية للحروف)', () async {
      f.next = lic(false);
      final s = await l.check();
      expect(s.allowed, isFalse);
      expect(s.message, 'رسالة');
      expect(await l.unlock('xyz'), isFalse);
      expect(await l.unlock(' abc123 '), isTrue);
      expect(l.allowed, isTrue);
      // فحص لاحق بنفس الكود يبقى مفتوحاً
      expect((await l.check()).allowed, isTrue);
    });

    test('تغيير الكود في الخادم ⇒ يُعاد القفل', () async {
      f.next = lic(false);
      await l.check();
      await l.unlock('ABC123');
      f.next = lic(false, code: 'NEW999');
      expect((await l.check()).allowed, isFalse);
      expect(await l.unlock('NEW999'), isTrue);
    });

    test('codeHash فقط (بلا كود نصي في الملف العام) يفتح بالكود الصحيح', () async {
      f.next = RemoteFile.ok({'active': false, 'codeHash': LicenseService.hashCode_('SECRET-1'), 'message': ''});
      expect((await l.check()).allowed, isFalse);
      expect(await l.unlock('secret-2'), isFalse);
      expect(await l.unlock(' secret-1 '), isTrue);
      // لا يُخزَّن الكود نصاً في الجهاز
      expect(store.meta<String>('lic_activated'), isNot(contains('SECRET')));
    });

    test('حذف الملف بعد رؤيته ⇒ قفل نهائي ولا يقبل أي كود', () async {
      f.next = lic(true);
      await l.check();
      f.next = RemoteFile.notFound();
      final s = await l.check();
      expect(s.allowed, isFalse);
      expect(s.codeAccepted, isFalse);
      expect(await l.unlock('ABC123'), isFalse);
    });

    test('مقفل ثم انقطع الاتصال ⇒ يبقى مقفلاً (آخر حالة معروفة)', () async {
      f.next = lic(false);
      await l.check();
      f.next = null;
      final s = await l.check();
      expect(s.allowed, isFalse);
      expect(s.offline, isTrue);
    });

    test('الحالة تُحفظ: خدمة جديدة (إعادة تشغيل) تقرأ القفل فوراً بلا شبكة', () async {
      f.next = lic(false);
      await l.check();
      final l2 = LicenseService(store, fetcher: FakeFetcher());
      expect(l2.allowed, isFalse);
    });

    test('init لا ينتظر الشبكة', () async {
      final slow = _SlowFetcher();
      final l3 = LicenseService(store, fetcher: slow);
      final sw = Stopwatch()..start();
      await l3.init();
      expect(sw.elapsedMilliseconds, lessThan(500));
      expect(l3.allowed, isTrue);
    });
  });

  group('قفل الجهاز من المنصة (2.5.0)', () {
    late LicenseService d;
    setUp(() => d = LicenseService(store, fetcher: f, deviceInfo: fakeDevice));

    test('النبض يرسل معرّفاً ثابتاً (48 hex) وبيانات الجهاز', () async {
      f.next = lic(true);
      f.pingNext = const PingResult(deviceActive: true);
      await d.check();
      await d.check();
      expect(f.pings, hasLength(2));
      final id = f.pings.first['deviceId'] as String;
      expect(id, matches(RegExp(r'^[0-9a-f]{48}$')));
      expect(f.pings.last['deviceId'], id);
      expect(f.pings.first['model'], 'Test X');
      expect(f.pings.first['build'], 250);
      // يبقى بعد إعادة التشغيل
      expect(LicenseService(store, fetcher: f, deviceInfo: fakeDevice).deviceId(), id);
    });

    test('deviceActive=false ⇒ مقفل، والكود لا يفتحه', () async {
      f.next = lic(true);
      f.pingNext = const PingResult(deviceActive: false);
      final s = await d.check();
      expect(s.allowed, isFalse);
      expect(s.deviceLocked, isTrue);
      expect(s.codeAccepted, isFalse);
      expect(await d.unlock('ABC123'), isFalse);
    });

    test('قفل الجهاز ثم انقطاع الشبكة ⇒ يبقى مقفلاً، ويُحفظ عبر إعادة التشغيل', () async {
      f.next = lic(true);
      f.pingNext = const PingResult(deviceActive: false);
      await d.check();
      f.pingNext = null;
      f.next = null;
      expect((await d.check()).allowed, isFalse);
      expect(LicenseService(store, fetcher: FakeFetcher()).allowed, isFalse);
    });

    test('فتح الجهاز من اللوحة ⇒ يفتح فوراً في الفحص التالي', () async {
      f.next = lic(true);
      f.pingNext = const PingResult(deviceActive: false);
      await d.check();
      f.pingNext = const PingResult(deviceActive: true);
      final s = await d.check();
      expect(s.allowed, isTrue);
      expect(s.deviceLocked, isFalse);
    });

    test('النبض يفشل (شبكة) لأول مرة ⇒ لا قفل أبداً', () async {
      f.next = lic(true);
      f.pingNext = null;
      expect((await d.check()).allowed, isTrue);
    });

    test('الجهاز مفتوح لكن الترخيص العام موقوف ⇒ مقفل ويقبل الكود', () async {
      f.next = lic(false);
      f.pingNext = const PingResult(deviceActive: true);
      final s = await d.check();
      expect(s.allowed, isFalse);
      expect(s.deviceLocked, isFalse);
      expect(await d.unlock('ABC123'), isTrue);
    });

    test('2.7.0: hwId يُرسل، والمعرّف المعتمد من الخادم يُعتمد (لا تكرار عند إعادة التثبيت)', () async {
      final h = LicenseService(
        store,
        fetcher: f,
        deviceInfo: () async => {...(await fakeDevice())!, 'hwId': 'abcdef0123456789'},
      );
      f.next = lic(true);
      const canonical = '0123456789abcdef0123456789abcdef0123456789abcdef';
      f.pingNext = const PingResult(deviceActive: true, canonicalId: canonical);
      await h.check();
      expect(f.pings.first['hwId'], 'abcdef0123456789');
      expect(h.deviceId(), canonical);
      f.pingNext = const PingResult(deviceActive: true);
      await h.check();
      expect(f.pings.last['deviceId'], canonical);
    });

    test('2.7.0: التحديث مع النبض — عادي وإجباري وموقوف', () async {
      f.next = lic(true);
      f.pingNext = const PingResult(deviceActive: true, latest: LatestRelease(version: '2.7.0', build: 270));
      await d.check();
      expect(d.updateAvailable, isTrue);
      expect(d.mandatoryUpdate, isFalse);
      f.pingNext = const PingResult(
        deviceActive: true,
        latest: LatestRelease(version: '2.7.0', build: 270, minSupportedBuild: 260),
      );
      await d.check();
      expect(d.mandatoryUpdate, isTrue, reason: 'المثبّت 250 < أقل مدعوم 260');
      f.pingNext = const PingResult(
        deviceActive: true,
        updateBlocked: true,
        latest: LatestRelease(version: '2.7.0', build: 270, minSupportedBuild: 260),
      );
      await d.check();
      expect(d.updateAvailable, isFalse, reason: 'إيقاف التحديث من اللوحة يخفي كل شيء');
      expect(d.mandatoryUpdate, isFalse);
      f.pingNext = const PingResult(deviceActive: true, latest: LatestRelease(version: '2.5.0', build: 250));
      await d.check();
      expect(d.updateAvailable, isFalse, reason: 'نفس الإصدار المثبّت');
    });

    test('الويب/غير أندرويد ⇒ لا نبض', () async {
      final w = LicenseService(store, fetcher: f, deviceInfo: () async => null);
      f.next = lic(true);
      await w.check();
      expect(f.pings, isEmpty);
    });
  });

  group('مصادر الجلب', () {
    test('المنصة هي المصدر الأساسي والعناوين صحيحة', () {
      expect(
        RemoteConfig.platformUri('update.json').toString(),
        'https://api.alabbasi.uk/v1/apps/hisab-almozaw3/update.json',
      );
      expect(RemoteConfig.pingUri.toString(), 'https://api.alabbasi.uk/v1/apps/hisab-almozaw3/ping');
    });
  });

  group('التحديث عن بعد', () {
    test('abiKey من مجلد المكتبات أولاً ثم معمارية الجهاز', () {
      expect(UpdateService.abiKey('/data/app/x/lib/arm64', 'armeabi-v7a'), 'arm64');
      expect(UpdateService.abiKey('/data/app/x/lib/arm', 'arm64-v8a'), 'armv7');
      expect(UpdateService.abiKey('', 'arm64-v8a'), 'arm64');
      expect(UpdateService.abiKey('', 'mips'), '');
    });

    test('tryParse يرفض: http، sha قصير، بلا apks', () {
      expect(UpdateInfo.tryParse(upd()), isNotNull);
      final bad1 = upd()
        ..['apks'] = {
          'arm64': {'url': 'http://x/a.apk', 'sha256': _sha},
        };
      expect(UpdateInfo.tryParse(bad1), isNull);
      final bad2 = upd()
        ..['apks'] = {
          'arm64': {'url': 'https://x/a.apk', 'sha256': 'abc'},
        };
      expect(UpdateInfo.tryParse(bad2), isNull);
      expect(UpdateInfo.tryParse({'version': '1'}), isNull);
      expect(UpdateInfo.tryParse('junk'), isNull);
    });

    test('متاح فقط إن كان versionCode لنفس المعمارية أكبر', () {
      expect(UpdateService.compare(UpdateInfo.tryParse(upd()), inst64).status, UpdateStatus.available);
      expect(UpdateService.compare(UpdateInfo.tryParse(upd(arm64: 2220)), inst64).status, UpdateStatus.upToDate);
      // armv7 أحدث لكن المثبّت arm64 ⇒ لا تحديث
      expect(
        UpdateService.compare(UpdateInfo.tryParse(upd(arm64: 2220, armv7: 1300)), inst64).status,
        UpdateStatus.upToDate,
      );
    });

    test('APK الصحيح للمعمارية المثبّتة', () {
      final r = UpdateService.compare(UpdateInfo.tryParse(upd()), inst64);
      expect(r.apk!.url.path, '/a64.apk');
    });

    test('إلزامي عندما build المثبّت < minSupportedBuild', () {
      expect(UpdateService.compare(UpdateInfo.tryParse(upd()), inst64).mandatory, isFalse);
      expect(UpdateService.compare(UpdateInfo.tryParse(upd(minBuild: 221)), inst64).mandatory, isTrue);
    });

    test('معمارية غير معروفة ⇒ unsupported (لا تنزيل خاطئ)', () {
      const x = InstalledInfo(versionCode: 3220, versionName: '2.2.0', abi: 'x86_64');
      expect(UpdateService.compare(UpdateInfo.tryParse(upd()), x).status, UpdateStatus.unsupported);
      expect(UpdateService.compare(null, inst64).status, UpdateStatus.invalid);
    });

    test('isCheckDue كل 24 ساعة', () {
      final now = DateTime(2026, 1, 2, 12);
      expect(UpdateService.isCheckDue(null, now: now), isTrue);
      expect(UpdateService.isCheckDue(now.subtract(const Duration(hours: 23)), now: now), isFalse);
      expect(UpdateService.isCheckDue(now.subtract(const Duration(hours: 24)), now: now), isTrue);
    });

    test('build من versionCode (1000×ABI + N)', () {
      expect(inst64.build, 220);
      expect(const InstalledInfo(versionCode: 1220, versionName: '', abi: 'armv7').build, 220);
    });
  });
}

class _SlowFetcher extends RemoteFetcher {
  @override
  Future<RemoteFile?> fetch(String file, {String? deviceId}) async {
    await Future<void>.delayed(const Duration(seconds: 3));
    return null;
  }
}
