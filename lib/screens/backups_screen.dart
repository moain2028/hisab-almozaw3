/// backups_screen.dart — النسخ الاحتياطي (منذ 2.7.0 على نمط واتساب «النسخ الاحتياطي للدردشات»).
///
/// المبدأ (معيار القوائم في docs/standards/lists.md): **الصفحة ثابتة لا تطول مهما كثرت النسخ**.
///   - بطاقة الحالة: آخر نسخة + المكان + النسخ التلقائي.
///   - زران في صف واحد: «نسخ الآن» · «استرجاع».
///   - «استرجاع» يفتح نافذة سفلية (Bottom Sheet) فيها النسخ مجمّعة بالأيام، 8 في الصفحة مع ترقيم،
///     وفي أعلاها «من ملف آخر…». الضغط على نسخة يعرض محتواها (بقالات/أصناف/حركات) قبل أي تغيير.
///   - لا يوجد «نسخ كنص» ولا «استرجاع من نص» (ممنوع: يتجاوز التحقق بالبصمة ويُفسد البيانات بسهولة).
library;

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/format.dart';
import '../data/backup_service.dart';
import '../data/store.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

class BackupsScreen extends StatefulWidget {
  const BackupsScreen({super.key, this.pickToRestore = false, this.debugFiles});

  /// للاختبارات/اللقطات فقط: قائمة جاهزة بدل قراءة المجلد
  @visibleForTesting
  final List<BackupFile>? debugFiles;

  /// من شاشة أول تشغيل: تُفتح نافذة الاسترجاع مباشرة، وبعد الاسترجاع نرجع true
  final bool pickToRestore;

  @override
  State<BackupsScreen> createState() => _BackupsScreenState();
}

String backupSize(int b) => b < 1024
    ? '$b بايت'
    : (b < 1 << 20 ? '${(b / 1024).toStringAsFixed(1)} ك.ب' : '${(b / (1 << 20)).toStringAsFixed(1)} م.ب');

String backupKind(BackupFile b) => b.isAuto ? 'تلقائية' : (b.name.contains('before-restore') ? 'قبل استرجاع' : 'يدوية');

class _BackupsScreenState extends State<BackupsScreen> {
  List<BackupFile>? files;
  String path = '';
  bool busy = false;

  BackupService get svc => context.read<BackupService>();

  @override
  void initState() {
    super.initState();
    _load().then((_) {
      if (widget.pickToRestore && mounted) _openRestore();
    });
  }

  Future<void> _load() async {
    if (widget.debugFiles != null) {
      setState(() {
        files = widget.debugFiles;
        path = 'Android/media/com.hisabalmozaw3.distributor/Backups';
      });
      return;
    }
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
    toast(context, f == null ? 'تعذّر إنشاء النسخة: ${svc.lastError ?? ''}' : 'تم حفظ نسخة (${backupSize(f.size)})');
    await _load();
  }

  Future<void> _openRestore() async {
    final picked = await showModalBottomSheet<File>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      useSafeArea: true,
      builder: (_) => _RestoreSheet(files: files ?? const [], svc: svc, onChanged: _load),
    );
    if (picked != null && mounted) await _restore(picked);
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
        icon: const Icon(Icons.restore_rounded),
        title: const Text('استرجاع هذه النسخة؟'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _Count(n('shops'), 'بقالة'),
                _Count(n('products'), 'صنف'),
                _Count(n('shopTxs') + n('traderTxs'), 'حركة'),
              ],
            ),
            const SizedBox(height: Space.md),
            const Text(
              'استبدال: يرجّع الحسابات كما كانت في النسخة (يُحفظ الوضع الحالي تلقائياً قبلها).\n'
              'دمج: يضيف ما في النسخة بدون حذف شيء.',
              style: TextStyle(fontSize: 13.5, height: 1.6),
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

  String _when(DateTime d) => '${relativeDay(dayKey(d))} · ${timeOf(d.millisecondsSinceEpoch)}';

  @override
  Widget build(BuildContext context) {
    final store = context.watch<Store>();
    final cs = Theme.of(context).colorScheme;
    if (!BackupService.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('النسخ الاحتياطي')),
        body: const Center(
          child: EmptyState(icon: Icons.phone_android, text: 'النسخ الاحتياطي في ملفات يعمل على تطبيق أندرويد.'),
        ),
      );
    }
    final n = files?.length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('النسخ الاحتياطي')),
      body: files == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(Space.lg),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 52,
                              height: 52,
                              decoration: BoxDecoration(
                                color: cs.primaryContainer,
                                borderRadius: BorderRadius.circular(Radii.md),
                              ),
                              child: Icon(Icons.cloud_done_rounded, color: cs.onPrimaryContainer, size: 28),
                            ),
                            const SizedBox(width: Space.md),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    store.lastBackup == 0
                                        ? 'لا توجد نسخة بعد'
                                        : 'آخر نسخة: ${_when(DateTime.fromMillisecondsSinceEpoch(store.lastBackup))}',
                                    style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5),
                                  ),
                                  Text(
                                    '$n نسخة على الجوال · تبقى حتى لو حُذف التطبيق',
                                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: Space.lg),
                        // زران في صف واحد (لا أزرار متراكمة عمودياً)
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: busy ? null : _create,
                                style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                                icon: busy
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(strokeWidth: 2),
                                      )
                                    : const Icon(Icons.backup_outlined),
                                label: const Text('نسخ الآن'),
                              ),
                            ),
                            const SizedBox(width: Space.sm),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: busy ? null : _openRestore,
                                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                                icon: const Icon(Icons.restore_rounded),
                                label: const Text('استرجاع'),
                              ),
                            ),
                          ],
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
                        subtitle: const Text('بعد كل تعديل بثوانٍ وعند الخروج. يحتفظ بآخر 14 يوماً.'),
                      ),
                      const Divider(height: 1),
                      ListTile(
                        leading: const Icon(Icons.folder_outlined),
                        title: const Text('مكان الحفظ', style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text(
                          path,
                          textDirection: TextDirection.ltr,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.sm),
                  child: Text(
                    'للحماية من ضياع الجوال: من «استرجاع» اضغط خيارات النسخة ثم «مشاركة» وأرسلها لنفسك على واتساب أو Drive.',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.6),
                  ),
                ),
              ],
            ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.n, this.label);
  final int n;
  final String label;
  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(
      children: [
        Text('$n', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12.5)),
      ],
    ),
  );
}

/// نافذة اختيار نسخة للاسترجاع: مجمّعة بالأيام، 8 لكل صفحة، ترقيم ثابت أسفلها.
class _RestoreSheet extends StatefulWidget {
  const _RestoreSheet({required this.files, required this.svc, required this.onChanged});
  final List<BackupFile> files;
  final BackupService svc;
  final Future<void> Function() onChanged;
  @override
  State<_RestoreSheet> createState() => _RestoreSheetState();
}

class _RestoreSheetState extends State<_RestoreSheet> {
  static const per = 8;
  late List<BackupFile> files = [...widget.files];
  int page = 0;

  int get pages => files.isEmpty ? 1 : (files.length + per - 1) ~/ per;

  Future<void> _pickFile() async {
    final r = await FilePicker.platform.pickFiles(type: FileType.any);
    final p = r?.files.single.path;
    if (p != null && mounted) Navigator.pop(context, File(p));
  }

  Future<void> _share(BackupFile b) => Share.shareXFiles([
    XFile(b.file.path, mimeType: 'application/octet-stream'),
  ], text: 'نسخة احتياطية - حساب الموزع');

  Future<void> _delete(BackupFile b) async {
    if (!await confirm(context, 'حذف هذه النسخة؟')) return;
    await widget.svc.delete(b);
    await widget.onChanged();
    setState(() {
      files.remove(b);
      page = page.clamp(0, pages - 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final slice = files.skip(page * per).take(per).toList();
    final rows = <Widget>[];
    String? lastDay;
    for (final b in slice) {
      final d = relativeDay(dayKey(b.modified));
      if (d != lastDay) {
        rows.add(
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(Space.lg, Space.md, Space.lg, Space.xs),
            child: Text(
              d,
              style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700, fontSize: 13),
            ),
          ),
        );
        lastDay = d;
      }
      rows.add(
        ListTile(
          leading: Icon(
            b.isAuto
                ? Icons.autorenew
                : (b.name.contains('before-restore') ? Icons.shield_outlined : Icons.save_outlined),
            color: cs.primary,
          ),
          title: Text(timeOf(b.modified.millisecondsSinceEpoch), style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${backupKind(b)} · ${backupSize(b.size)}'),
          onTap: () => Navigator.pop(context, b.file),
          trailing: PopupMenuButton<String>(
            tooltip: 'خيارات',
            onSelected: (v) {
              if (v == 'share') _share(b);
              if (v == 'delete') _delete(b);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'share',
                child: ListTile(leading: Icon(Icons.share_outlined), title: Text('مشاركة')),
              ),
              PopupMenuItem(
                value: 'delete',
                child: ListTile(leading: Icon(Icons.delete_outline), title: Text('حذف')),
              ),
            ],
          ),
        ),
      );
    }
    return SizedBox(
      height: MediaQuery.of(context).size.height * .72,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.sm),
            child: Row(
              children: [
                const Expanded(
                  child: Text('اختر نسخة للاسترجاع', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ),
                TextButton.icon(
                  onPressed: _pickFile,
                  icon: const Icon(Icons.folder_open_outlined),
                  label: const Text('من ملف…'),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: files.isEmpty
                ? const EmptyState(icon: Icons.inventory_2_outlined, text: 'لا توجد نسخ على الجوال.\nاختر «من ملف…»')
                : ListView(children: rows),
          ),
          if (pages > 1) ...[
            const Divider(height: 1),
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
                child: Row(
                  children: [
                    IconButton(
                      tooltip: 'السابق',
                      onPressed: page > 0 ? () => setState(() => page--) : null,
                      icon: const Icon(Icons.chevron_right),
                    ),
                    Expanded(
                      child: Text(
                        'صفحة ${page + 1} من $pages · ${files.length} نسخة',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: cs.onSurfaceVariant),
                      ),
                    ),
                    IconButton(
                      tooltip: 'التالي',
                      onPressed: page < pages - 1 ? () => setState(() => page++) : null,
                      icon: const Icon(Icons.chevron_left),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
