/// remote_config.dart — مكان واحد لعناوين التحكم عن بُعد (ترخيص + تحديث).
///
/// نفس نمط منظومة الضيافة (MoTechSys/diafa-apps):
///   مستودع عام للتوزيع ← مجلد لهذا التطبيق ← license.json + update.json
///
///   `github.com/{owner}/{repo}/{folder}/license.json`
///   `github.com/{owner}/{repo}/{folder}/update.json`
///
/// ⚠️ هذه القيم تُقرأ حرفياً من كل نسخة مثبّتة. تغييرها بعد النشر = إصدار جديد إلزامي.
/// ⚠️ مستودع التوزيع يجب أن يبقى **عاماً** (التطبيق يقرأ بلا تسجيل دخول).
library;

import 'dart:convert';

import 'package:http/http.dart' as http;

class RemoteConfig {
  static const owner = 'moain2028';
  static const repo = 'hisab-almozaw3-dist';
  static const branch = 'main';
  static const folder = 'hisab-almozaw3';

  /// المصدر الأساسي GitHub Contents API (بلا كاش CDN)، والاحتياطي raw (كاش حتى 5 دقائق)
  static Uri apiUri(String file) =>
      Uri.https('api.github.com', '/repos/$owner/$repo/contents/$folder/$file', {'ref': branch});
  static Uri rawUri(String file) => Uri.https('raw.githubusercontent.com', '/$owner/$repo/$branch/$folder/$file');

  /// صفحة الإصدارات (لزر "فتح في المتصفح")
  static Uri get releasesPage => Uri.https('github.com', '/$owner/$repo/releases/latest');
}

/// نتيجة جلب ملف عن بُعد
class RemoteFile {
  RemoteFile.ok(this.data) : notFound = false;
  RemoteFile.notFound() : data = null, notFound = true;
  final Map<String, dynamic>? data;
  final bool notFound;
}

/// جلب JSON بلا كاش: API أولاً (حد 60 طلب/ساعة)، ثم الملف الخام.
/// يُرجع null عند انقطاع الشبكة أو ملف تالف (= "لا نعرف"، لا قفل خاطئ أبداً).
class RemoteFetcher {
  RemoteFetcher([http.Client? client]) : client = client ?? http.Client();
  http.Client client;

  static const _noCache = {'Cache-Control': 'no-cache, no-store, max-age=0', 'Pragma': 'no-cache'};
  static const timeout = Duration(seconds: 8);

  Future<RemoteFile?> fetch(String file) async {
    // 1) Contents API
    try {
      final res = await client
          .get(RemoteConfig.apiUri(file), headers: {..._noCache, 'Accept': 'application/vnd.github+json'})
          .timeout(timeout);
      if (res.statusCode == 200) {
        final meta = jsonDecode(utf8.decode(res.bodyBytes));
        final b64 = '${meta is Map ? meta['content'] ?? '' : ''}'.replaceAll(RegExp(r'\s'), '');
        if (b64.isNotEmpty) return RemoteFile.ok(_obj(utf8.decode(base64Decode(b64))));
      }
      if (res.statusCode == 404) return RemoteFile.notFound();
    } catch (_) {
      // 403 حد الطلبات / شبكة / JSON تالف → نجرّب الخام
    }
    // 2) الملف الخام
    try {
      final u = RemoteConfig.rawUri(file).replace(queryParameters: {'t': '${DateTime.now().millisecondsSinceEpoch}'});
      final res = await client.get(u, headers: _noCache).timeout(timeout);
      if (res.statusCode == 200) return RemoteFile.ok(_obj(utf8.decode(res.bodyBytes)));
      if (res.statusCode == 404) return RemoteFile.notFound();
    } catch (_) {}
    return null;
  }

  static Map<String, dynamic> _obj(String body) {
    final v = jsonDecode(body);
    if (v is Map<String, dynamic>) return v;
    throw const FormatException('not an object');
  }
}
