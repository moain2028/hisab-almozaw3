/// command_service.dart — تنفيذ أوامر لوحة المنصة (admin.alabbasi.uk) على الجهاز. منذ 2.6.0.
///
/// الأوامر تصل مع رد النبض (`LicenseService.commands`):
/// | النوع    | التنفيذ                                                                   |
/// |----------|---------------------------------------------------------------------------|
/// | message  | حوار داخل التطبيق (عنوان + نص). يُؤكَّد بـ ack بعد ضغط «حسناً».           |
/// | backup   | يرفع نسخة `.hisab` من البيانات (نفس صيغة النسخ المحلي) إلى المنصة.         |
///
/// - كل أمر يُنفّذ **مرة واحدة**: نحفظ آخر المعرّفات المنفّذة محلياً، والخادم لا يعيد ما أُكّد.
/// - فشل الشبكة = يُعاد المحاولة في النبض التالي (لا يُحفظ كمنفّذ).
/// - حد النسخة 1.4MB (حد المنصة). أكبر من ذلك = ack بفشل وسبب واضح في اللوحة.
library;

import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../data/backup_service.dart';
import '../data/store.dart';
import 'license_service.dart';
import 'remote_config.dart';

/// رسالة جاهزة للعرض (تستمع لها الواجهة)
@immutable
class InboxMessage {
  const InboxMessage(this.commandId, this.title, this.body);
  final int commandId;
  final String title;
  final String body;
}

class CommandService {
  CommandService(this.store, this.license, {RemoteFetcher? fetcher}) : fetcher = fetcher ?? license.fetcher {
    license.commands.addListener(_onCommands);
  }

  final Store store;
  final LicenseService license;
  final RemoteFetcher fetcher;
  static const maxBackup = 1400000;
  static const _kDone = 'cmd_done';

  /// الرسائل المنتظرة للعرض (الأقدم أولاً)
  final ValueNotifier<List<InboxMessage>> inbox = ValueNotifier(const []);
  final _running = <int>{};

  Set<int> get _done => {...(store.meta<List>(_kDone) ?? const []).whereType<int>()};
  Future<void> _markDone(int id) {
    final d = _done..add(id);
    final keep = d.toList()..sort();
    return store.putMetaSilently({_kDone: keep.length > 200 ? keep.sublist(keep.length - 200) : keep});
  }

  void _onCommands() => unawaited(handle(license.commands.value));

  /// يعالج قائمة أوامر (عامة للاختبار)
  Future<void> handle(List<RemoteCommand> cmds) async {
    final done = _done;
    for (final c in cmds) {
      if (done.contains(c.id) || !_running.add(c.id)) continue;
      try {
        switch (c.type) {
          case 'message':
            final title = '${c.payload['title'] ?? ''}'.trim();
            final body = '${c.payload['body'] ?? ''}'.trim();
            if (title.isEmpty && body.isEmpty) {
              await _ack(c.id, ok: false, result: 'empty');
            } else if (!inbox.value.any((m) => m.commandId == c.id)) {
              inbox.value = [...inbox.value, InboxMessage(c.id, title, body)];
            }
          case 'backup':
            await _uploadBackup(c.id);
          default:
            await _ack(c.id, ok: false, result: 'unsupported:${c.type}');
        }
      } catch (e) {
        if (kDebugMode) debugPrint('command ${c.id}: $e');
      } finally {
        _running.remove(c.id);
      }
    }
  }

  /// المستخدم قرأ الرسالة
  Future<void> dismiss(InboxMessage m) async {
    inbox.value = inbox.value.where((x) => x.commandId != m.commandId).toList();
    await _ack(m.commandId, ok: true, result: 'shown');
  }

  Future<void> _uploadBackup(int id) async {
    final bytes = BackupService.encode(store.toJsonMap());
    if (bytes.length > maxBackup) {
      await _ack(id, ok: false, result: 'too_large ${bytes.length}B');
      return;
    }
    final r = await fetcher.post('backup', {
      'deviceId': license.deviceId(),
      'commandId': id,
      'data': base64Encode(bytes),
      'sha256': sha256.convert(bytes).toString(),
    }, wait: const Duration(seconds: 60));
    if (r != null && r['ok'] == true) await _markDone(id);
  }

  Future<void> _ack(int id, {required bool ok, String? result}) async {
    final r = await fetcher.post('commands/$id/ack', {
      'deviceId': license.deviceId(),
      'ok': ok,
      if (result != null) 'result': result,
    });
    if (r != null) await _markDone(id);
  }

  void dispose() => license.commands.removeListener(_onCommands);
}
