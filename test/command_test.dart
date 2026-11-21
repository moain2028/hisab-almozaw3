// أوامر لوحة المنصة (2.6.0): إشعار، سحب نسخة، تنفيذ مرة واحدة، كود الجهاز.
import 'dart:convert';
import 'dart:io';

import 'package:distributor/core/command_service.dart';
import 'package:distributor/core/license_service.dart';
import 'package:distributor/core/remote_config.dart';
import 'package:distributor/data/backup_service.dart';
import 'package:distributor/data/store.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

class FakePlatform extends RemoteFetcher {
  RemoteFile? license = RemoteFile.ok({'active': true});
  PingResult? pingNext;
  final posts = <String, List<Map<String, Object?>>>{};
  Map<String, dynamic>? Function(String path, Map<String, Object?> body)? reply;
  @override
  Future<RemoteFile?> fetch(String file, {String? deviceId}) async => license;
  @override
  Future<PingResult?> ping(Map<String, Object?> body) async => pingNext;
  @override
  Future<Map<String, dynamic>?> post(String path, Map<String, Object?> body, {Duration? wait}) async {
    (posts[path] ??= []).add(body);
    return reply != null ? reply!(path, body) : {'ok': true};
  }
}

Future<Map<String, Object?>?> dev() async => {
  'version': '2.6.0',
  'build': 260,
  'abi': 'arm64',
  'model': 'X',
  'deviceName': 'جوال أحمد',
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  late Store store;
  late FakePlatform f;
  late LicenseService lic;
  late CommandService cmd;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('cmd_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => tmp.path,
    );
    store = Store();
    await store.init();
    f = FakePlatform();
    lic = LicenseService(store, fetcher: f, deviceInfo: dev);
    cmd = CommandService(store, lic);
  });
  tearDown(() async {
    cmd.dispose();
    await Hive.close();
    await tmp.delete(recursive: true);
  });

  test('اسم الجهاز يُرسل مع النبض', () async {
    f.pingNext = const PingResult(deviceActive: true);
    final sent = <Map<String, Object?>>[];
    final spy = _Spy(f, sent);
    await LicenseService(store, fetcher: spy, deviceInfo: dev).check();
    expect(sent.single['deviceName'], 'جوال أحمد');
  });

  test('الإشعار يظهر في الصندوق، ويُؤكَّد مرة واحدة بعد القراءة', () async {
    f.pingNext = const PingResult(
      deviceActive: true,
      commands: [
        RemoteCommand(7, 'message', {'title': 'مرحبا', 'body': 'نص'}),
      ],
    );
    await lic.check();
    await Future<void>.delayed(Duration.zero);
    expect(cmd.inbox.value.single.title, 'مرحبا');
    await cmd.dismiss(cmd.inbox.value.single);
    expect(cmd.inbox.value, isEmpty);
    expect(f.posts['commands/7/ack']!.single['ok'], isTrue);
    // نفس الأمر مرة ثانية (قبل أن يحذفه الخادم) لا يظهر مجدداً
    await cmd.handle(const [
      RemoteCommand(7, 'message', {'title': 'مرحبا'}),
    ]);
    expect(cmd.inbox.value, isEmpty);
  });

  test('سحب نسخة: يرفع ملف .hisab صالحاً بنفس بصمته، مرة واحدة', () async {
    await store.loadDemo(days: 2);
    await cmd.handle(const [RemoteCommand(9, 'backup', {})]);
    final b = f.posts['backup']!.single;
    expect(b['commandId'], 9);
    expect(b['deviceId'], lic.deviceId());
    final bytes = base64Decode(b['data'] as String);
    expect(BackupService.decode(bytes), isA<Map>());
    await cmd.handle(const [RemoteCommand(9, 'backup', {})]);
    expect(f.posts['backup'], hasLength(1));
  });

  test('فشل رفع النسخة (شبكة) ⇒ يُعاد في النبض التالي', () async {
    f.reply = (_, __) => null;
    await cmd.handle(const [RemoteCommand(11, 'backup', {})]);
    f.reply = null;
    await cmd.handle(const [RemoteCommand(11, 'backup', {})]);
    expect(f.posts['backup'], hasLength(2));
  });

  test('أمر غير معروف ⇒ ack بفشل (لا يعلق)', () async {
    await cmd.handle(const [RemoteCommand(12, 'wipe', {})]);
    expect(f.posts['commands/12/ack']!.single['ok'], isFalse);
  });

  test('جهاز مقفول + كود للجهاز ⇒ حقل الكود يظهر، والخادم يتحقق', () async {
    f.pingNext = const PingResult(deviceActive: false, deviceCode: true);
    final s = await lic.check();
    expect(s.deviceLocked, isTrue);
    expect(s.codeAccepted, isTrue);
    f.reply = (p, b) => p == 'activate' ? {'ok': b['code'] == 'HISAB-AAAA-BBBB'} : {'ok': true};
    expect(await lic.unlock('WRONG'), isFalse);
    f.pingNext = const PingResult(deviceActive: true);
    expect(await lic.unlock('HISAB-AAAA-BBBB'), isTrue);
    expect(lic.allowed, isTrue);
  });

  test('جهاز مقفول بلا كود ⇒ لا حقل كود', () async {
    f.pingNext = const PingResult(deviceActive: false);
    expect((await lic.check()).codeAccepted, isFalse);
  });

  test('RemoteCommand.tryParse يرفض المدخلات الناقصة', () {
    expect(RemoteCommand.tryParse({'id': 1, 'type': 'message'}), isNotNull);
    expect(RemoteCommand.tryParse({'type': 'message'}), isNull);
    expect(RemoteCommand.tryParse('x'), isNull);
  });
}

class _Spy extends FakePlatform {
  _Spy(this.base, this.sent);
  final FakePlatform base;
  final List<Map<String, Object?>> sent;
  @override
  Future<PingResult?> ping(Map<String, Object?> body) async {
    sent.add(body);
    return base.pingNext;
  }
}
