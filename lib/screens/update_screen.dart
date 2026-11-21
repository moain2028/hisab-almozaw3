import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/format.dart';
import '../core/remote_config.dart';
import '../core/update_service.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

/// شاشة "تحديث التطبيق": الحالة، ما الجديد، تنزيل بشريط تقدّم، تحقق البصمة، التثبيت.
class UpdateScreen extends StatefulWidget {
  const UpdateScreen({super.key, this.forced = false});

  /// تحديث إجباري (من اللوحة): بلا رجوع، والتطبيق لا يُفتح حتى يُحدَّث
  final bool forced;
  @override
  State<UpdateScreen> createState() => _UpdateScreenState();
}

class _UpdateScreenState extends State<UpdateScreen> with WidgetsBindingObserver {
  String? error;
  String? downloadedPath;

  UpdateService get svc => context.read<UpdateService>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => svc.check());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// بعد الرجوع من إعداد "تثبيت تطبيقات غير معروفة" نكمل التثبيت تلقائياً
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) {
    if (s == AppLifecycleState.resumed && downloadedPath != null) _install();
  }

  Future<void> _download(UpdateCheck r) async {
    setState(() => error = null);
    try {
      downloadedPath = await svc.download(r.apk!);
      await _install();
    } on UpdateException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  Future<void> _install() async {
    final p = downloadedPath;
    if (p == null) return;
    if (!await UpdateService.canInstall()) {
      if (!mounted) return;
      final ok = await confirm(
        context,
        'للتثبيت يجب السماح لهذا التطبيق بـ"تثبيت تطبيقات غير معروفة" مرة واحدة.\n\nسنفتح لك الإعداد، فعّله ثم ارجع.',
        ok: 'فتح الإعداد',
        danger: false,
      );
      if (ok) await UpdateService.openInstallSettings();
      return;
    }
    try {
      await UpdateService.install(p);
    } on UpdateException catch (e) {
      if (mounted) setState(() => error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<UpdateService>();
    final r = s.last;
    final cs = Theme.of(context).colorScheme;

    if (!UpdateService.supported) {
      return Scaffold(
        appBar: AppBar(title: const Text('تحديث التطبيق')),
        body: const Center(
          child: EmptyState(icon: Icons.phone_android, text: 'التحديث من داخل التطبيق يعمل على أندرويد فقط.'),
        ),
      );
    }

    final (IconData icon, Color color, String title) = switch (r?.status) {
      null => (Icons.sync, cs.primary, 'جارٍ الفحص…'),
      UpdateStatus.available => (Icons.new_releases_rounded, cs.primary, 'تحديث جديد متاح'),
      UpdateStatus.upToDate => (Icons.verified_rounded, paidColor(context), 'لديك آخر إصدار'),
      UpdateStatus.offline => (Icons.wifi_off_rounded, warnColor(context), 'لا يوجد اتصال'),
      _ => (Icons.error_outline, debtColor(context), 'تعذّر الفحص'),
    };

    return PopScope(
      canPop: !widget.forced,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: !widget.forced,
          title: Text(widget.forced ? 'تحديث إجباري' : 'تحديث التطبيق'),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(
                  children: [
                    Icon(icon, size: 56, color: color),
                    const SizedBox(height: Space.sm),
                    Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                    const SizedBox(height: Space.xs),
                    Text(
                      r?.installed == null
                          ? 'الإصدار الحالي: $kAppVersion'
                          : 'الإصدار الحالي: ${r!.installed!.versionName} (${r.installed!.abi})',
                      style: TextStyle(color: cs.onSurfaceVariant),
                    ),
                    if (r?.available == true) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        'الجديد: ${r!.info!.version}'
                        '${r.apk!.size > 0 ? ' · ${(r.apk!.size / 1048576).toStringAsFixed(1)} م.ب' : ''}',
                        style: TextStyle(color: cs.primary, fontWeight: FontWeight.w700),
                      ),
                    ],
                    if (s.lastCheck != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        'آخر فحص: ${relativeDay(dayKey(s.lastCheck!))} ${timeOf(s.lastCheck!.millisecondsSinceEpoch)}',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            if (widget.forced)
              Card(
                color: warnColor(context).withValues(alpha: .1),
                child: const ListTile(
                  leading: Icon(Icons.priority_high_rounded),
                  title: Text(
                    'هذا التحديث ضروري لمواصلة استخدام التطبيق',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text('بياناتك محفوظة وتبقى كما هي بعد التحديث.'),
                ),
              ),
            if (r?.available == true && r!.info!.notes.isNotEmpty) ...[
              const SectionTitle('ما الجديد'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(Space.md),
                  child: Text(r.info!.notes, style: const TextStyle(height: 1.7)),
                ),
              ),
            ],
            if (error != null)
              Card(
                color: debtColor(context).withValues(alpha: .08),
                child: ListTile(
                  leading: Icon(Icons.error_outline, color: debtColor(context)),
                  title: Text(error!, style: TextStyle(color: debtColor(context))),
                ),
              ),
            const SizedBox(height: Space.md),
            ValueListenableBuilder<double?>(
              valueListenable: s.progress,
              builder: (_, p, _) {
                if (p != null) {
                  return Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.sm),
                        child: LinearProgressIndicator(value: p, minHeight: 10),
                      ),
                      const SizedBox(height: Space.sm),
                      Text('جارٍ التنزيل ${(p * 100).toStringAsFixed(0)}%'),
                    ],
                  );
                }
                if (r?.available == true) {
                  return FilledButton.icon(
                    onPressed: () => _download(r!),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    icon: const Icon(Icons.download_rounded),
                    label: Text(downloadedPath == null ? 'تنزيل وتثبيت' : 'تثبيت'),
                  );
                }
                return OutlinedButton.icon(
                  onPressed: s.checking ? null : s.check,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                  icon: s.checking
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.refresh),
                  label: const Text('فحص الآن'),
                );
              },
            ),
            const SizedBox(height: Space.md),
            Text(
              '• التحديث يُثبَّت فوق التطبيق الحالي، والبيانات تبقى كما هي.\n'
              '• يُتحقق من سلامة الملف تلقائياً قبل التثبيت.\n'
              '• يُفحص تلقائياً مرة كل يوم.',
              style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.7),
            ),
            TextButton.icon(
              onPressed: () => launchUrl(RemoteConfig.downloadsPage, mode: LaunchMode.externalApplication),
              icon: const Icon(Icons.open_in_new, size: 18),
              label: const Text('صفحة التنزيل'),
            ),
          ],
        ),
      ),
    );
  }
}

/// نافذة تظهر تلقائياً عند وجود تحديث (من الفحص اليومي)
Future<void> showUpdateDialog(BuildContext context, UpdateCheck r) {
  final mandatory = r.mandatory;
  return showDialog(
    context: context,
    barrierDismissible: !mandatory,
    builder: (ctx) => PopScope(
      canPop: !mandatory,
      child: AlertDialog(
        icon: const Icon(Icons.system_update_rounded, size: 36),
        title: Text('الإصدار ${r.info!.version} متاح'),
        content: SingleChildScrollView(
          child: Text(
            [
              if (mandatory) 'هذا التحديث ضروري لمواصلة استخدام التطبيق.\n',
              r.info!.notes.isEmpty ? 'تحسينات وإصلاحات.' : r.info!.notes,
            ].join('\n'),
            style: const TextStyle(height: 1.6),
          ),
        ),
        actions: [
          if (!mandatory) ...[
            TextButton(
              onPressed: () {
                ctx.read<UpdateService>().skip(r);
                Navigator.pop(ctx);
              },
              child: const Text('تخطّي'),
            ),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('لاحقاً')),
          ],
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              Navigator.push(ctx, MaterialPageRoute(builder: (_) => const UpdateScreen()));
            },
            child: const Text('تحديث'),
          ),
        ],
      ),
    ),
  );
}
