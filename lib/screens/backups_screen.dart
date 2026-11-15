import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/backup_service.dart';
import '../data/store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// إدارة النسخ الاحتياطية (مثل "النسخ الاحتياطي للدردشات" في واتساب)
class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key, this.pickToRestore = false});

  /// من شاشة أول تشغيل: بعد الاسترجاع نرجع true
  final bool pickToRestore;

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

class _BackupsScreenState extends State<BackupsScreen> {
  List<BackupFile>? files;
  String path = '';
  bool busy = false;

  BackupService get svc => context.read<BackupService>();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!BackupService.supported) {
      setState(() => files = const []);
      return;
    }
    final l = await svc.list();
    final p = await svc.displayPath();
    if (mounted) {
      setState(() {
        files = l;
        path = p;
      });
    }
  }

  Future<void> _create() async {
    setState(() => busy = true);
    final f = await svc.create();
    if (!mounted) return;
    setState(() => busy = false);
    haptic(context, strong: true);
    toast(
      context,
      f == null ? 'تعذّر إنشاء النسخة: ${svc.lastError ?? ''}' : 'تم حفظ نسخة احتياطية (${_size(f.size)})',
    );
    await _load();
  }

  Future<void> _restore(File f) async {
    // نتحقق من الملف أولاً ونعرض محتواه قبل أي تغيير
    Map doc;
    try {
      doc = await svc.read(f);
    } catch (e) {
      if (mounted) toast(context, e is FormatException ? e.message : 'الملف غير صالح');
      return;
    }
    if (!mounted) return;
    int n(String k) => ((doc[k] as List?) ?? const []).length;
    final mode = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('استرجاع هذه النسخة؟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${n('shops')} بقالة · ${n('products')} صنف · ${n('shopTxs') + n('traderTxs')} حركة'),
            const SizedBox(height: 12),
            const Text(
              'استبدال: يرجّع الحسابات كما كانت في النسخة (يُحفظ الوضع الحالي تلقائياً قبلها).\n\n'
              'دمج: يضيف ما في النسخة بدون حذف شيء.',
              style: TextStyle(fontSize: 13.5),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          TextButton(onPressed: () => Navigator.pop(ctx, 'merge'), child: const Text('دمج')),
          FilledButton(onPressed: () => Navigator.pop(ctx, 'replace'), child: const Text('استبدال')),
        ],
      ),
    );
    if (mode == null || !mounted) return;
    setState(() => busy = true);
    try {
      final count = await svc.restore(f, replace: mode == 'replace');
      if (!mounted) return;
      haptic(context, strong: true);
      toast(context, 'تم الاسترجاع ($count سجل)');
      if (widget.pickToRestore) {
        Navigator.pop(context, true);
        return;
      }
    } catch (e) {
      if (mounted) toast(context, e is FormatException ? e.message : 'فشل الاسترجاع');
    }
    if (mounted) setState(() => busy = false);
    await _load();
  }

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final p = r?.files.single.path;
    if (p != null) await _restore(File(p));
  }

  Future<void> _share(BackupFile b) async {
    await Share.shareXFiles([
      XFile(b.file.path, mimeType: 'application/octet-stream'),
    ], text: 'نسخة احتياطية - حساب الموزع');
  }

  String _size(int b) => b < 1024
      ? '$b بايت'
      : (b < 1 << 20 ? '${(b / 1024).toStringAsFixed(1)} ك.ب' : '${(b / (1 << 20)).toStringAsFixed(1)} م.ب');

  String _when(DateTime d) => '${relativeDay(dayKey(d))} · ${timeOf(d.millisecondsSinceEpoch)}';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    if (!BackupService.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('النسخ الاحتياطي')),
        body: const Center(
          child: EmptyState(
            icon: Icons.phone_android,
            text:
                'النسخ الاحتياطي في ملفات يعمل على تطبيق أندرويد.\nفي المعاينة استخدم "نسخ البيانات كنص" من الإعدادات.',
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.cloud_done_rounded, color: cs.primary, size: 30),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  store.lastBackup == 0
                                      ? 'لا توجد نسخة بعد'
                                      : 'آخر نسخة: ${_when(DateTime.fromMillisecondsSinceEpoch(store.lastBackup))}',
                                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'تُحفظ النسخ على الجوال في المجلد:',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                          ),
                          const SizedBox(height: 4),
                          InkWell(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: path));
                              toast(context, 'تم نسخ المسار');
                            },
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Text(
                                path,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(fontSize: 12.5, fontFamily: 'monospace'),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '• يبقى المجلد حتى لو حذفت التطبيق، فتقدر تسترجع بعد إعادة التثبيت.\n'
                            '• للحماية من ضياع الجوال: شارك نسخة لنفسك على واتساب أو تلجرام أو Drive.',
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.6),
                          ),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: busy ? null : _create,
                            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                            icon: busy
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.backup_outlined),
                            label: const Text('نسخ احتياطي الآن'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        SwitchListTile(
                          value: store.autoBackup,
                          onChanged: (v) => store.setMeta('autoBackup', v),
                          secondary: const Icon(Icons.autorenew),
                          title: const Text('نسخ تلقائي', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('بعد كل تعديل بثوانٍ، وعند الخروج من التطبيق. يحتفظ بآخر 14 يوماً.'),
                        ),
                        const Divider(height: 1),
                        ListTile(
                          leading: const Icon(Icons.folder_open_outlined),
                          title: const Text('استرجاع من ملف آخر', style: TextStyle(fontWeight: FontWeight.w700)),
                          subtitle: const Text('ملف .hisab نزّلته من واتساب أو تلجرام'),
                          onTap: busy ? null : _pickFile,
                        ),
                      ],
                    ),
                  ),
                  SectionTitle(
                    'النسخ على الجوال',
                    trailing: Text('${files!.length}', style: TextStyle(color: cs.onSurfaceVariant)),
                  ),
                  if (files!.isEmpty)
                    const EmptyState(icon: Icons.inventory_2_outlined, text: 'لا توجد نسخ محفوظة بعد'),
                  for (final b in files!)
                    Card(
                      child: ListTile(
                        leading: Icon(
                          b.isAuto
                              ? Icons.autorenew
                              : (b.name.contains('before-restore') ? Icons.shield_outlined : Icons.save_outlined),
                          color: cs.primary,
                        ),
                        title: Text(_when(b.modified), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          '${b.isAuto ? 'تلقائية' : (b.name.contains('before-restore') ? 'قبل استرجاع' : 'يدوية')} · ${_size(b.size)}',
                        ),
                        onTap: busy ? null : () => _restore(b.file),
                        trailing: PopupMenuButton<String>(
                          onSelected: (v) async {
                            if (v == 'share') await _share(b);
                            if (v == 'restore') await _restore(b.file);
                            if (v == 'delete' && context.mounted && await confirm(context, 'حذف هذه النسخة؟')) {
                              await svc.delete(b);
                              await _load();
                            }
                          },
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                              value: 'restore',
                              child: ListTile(leading: Icon(Icons.restore), title: Text('استرجاع')),
                            ),
                            PopupMenuItem(
                              value: 'share',
                              child: ListTile(leading: Icon(Icons.share_outlined), title: Text('مشاركة (واتساب...)')),
                            ),
                            PopupMenuItem(
                              value: 'delete',
                              child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف')),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}
