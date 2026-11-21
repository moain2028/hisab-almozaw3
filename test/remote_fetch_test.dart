// ترتيب المصادر في RemoteFetcher: المنصة ← GitHub API ← raw. وقواعد النبض.
import 'dart:convert';

import 'package:distributor/core/remote_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  http.Response j(Object o, [int code = 200]) =>
      http.Response.bytes(utf8.encode(jsonEncode(o)), code, headers: {'content-type': 'application/json'});

  test('المنصة 200 ⇒ لا يُسأل GitHub', () async {
    final hosts = <String>[];
    final f = RemoteFetcher(
      MockClient((r) async {
        hosts.add(r.url.host);
        return j({'active': true});
      }),
    );
    final r = await f.fetch('license.json');
    expect(r!.data!['active'], isTrue);
    expect(hosts, ['api.alabbasi.uk']);
  });

  test('المنصة معطّلة (500) ⇒ GitHub API', () async {
    final hosts = <String>[];
    final f = RemoteFetcher(
      MockClient((r) async {
        hosts.add(r.url.host);
        if (r.url.host == 'api.alabbasi.uk') return http.Response('x', 500);
        return j({'content': base64Encode(utf8.encode('{"active":false}'))});
      }),
    );
    final r = await f.fetch('license.json');
    expect(r!.data!['active'], isFalse);
    expect(hosts, ['api.alabbasi.uk', 'api.github.com']);
  });

  test('404 من المنصة لا يعني حذفاً ⇒ نرجع لـ GitHub', () async {
    final f = RemoteFetcher(
      MockClient((r) async {
        if (r.url.host == 'api.alabbasi.uk') return http.Response('{"error":"unknown_app"}', 404);
        return j({'content': base64Encode(utf8.encode('{"active":true}'))});
      }),
    );
    final r = await f.fetch('license.json');
    expect(r!.notFound, isFalse);
    expect(r.data!['active'], isTrue);
  });

  test('كل المصادر بلا شبكة ⇒ null', () async {
    final f = RemoteFetcher(MockClient((r) async => throw http.ClientException('offline')));
    expect(await f.fetch('license.json'), isNull);
  });

  test('ping: يرسل JSON إلى المنصة ويقرأ deviceActive', () async {
    late http.Request sent;
    final f = RemoteFetcher(
      MockClient((r) async {
        sent = r;
        return j({'active': false, 'deviceActive': false, 'message': 'm'});
      }),
    );
    final p = await f.ping({'deviceId': 'abc', 'build': 250});
    expect(p!.deviceActive, isFalse);
    expect(sent.method, 'POST');
    expect(sent.url.toString(), 'https://api.alabbasi.uk/v1/apps/hisab-almozaw3/ping');
    expect(jsonDecode(sent.body)['deviceId'], 'abc');
  });

  test('ping: خطأ خادم أو رد ناقص أو شبكة ⇒ null (لا قفل)', () async {
    expect(await RemoteFetcher(MockClient((_) async => http.Response('', 500))).ping({}), isNull);
    expect(await RemoteFetcher(MockClient((_) async => j({'active': true}))).ping({}), isNull);
    expect(await RemoteFetcher(MockClient((_) async => throw http.ClientException('x'))).ping({}), isNull);
  });
}
