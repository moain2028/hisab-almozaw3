/// update_gate.dart — التحديث بنوعيه (منذ 2.7.0)، حسب معيار Google Play In-App Updates:
///
/// | النوع          | متى                                            | السلوك                                           |
/// |----------------|------------------------------------------------|--------------------------------------------------|
/// | عادي (Flexible) | build المنشور > المثبّت                          | إشعار داخل التطبيق **مرة واحدة لكل إصدار** + شارة |
/// | إجباري (Immediate) | المثبّت < minSupportedBuild (من اللوحة)        | شاشة كاملة تمنع الاستخدام حتى يحدّث (لا رجوع)     |
///
/// المصدر: النبض (`LicenseService.release`) — يصل مع كل فتح/عودة وكل دقيقتين، فيظهر الإشعار
/// بعد النشر بدقائق بلا خادم إشعارات. «إيقاف التحديث» من اللوحة ⇒ release = null ⇒ لا شيء يظهر.
library;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/license_service.dart';
import '../core/remote_config.dart';
import '../ui/theme.dart';
import 'update_screen.dart';

/// يلف التطبيق: تحديث إجباري ⇒ شاشة التحديث بدل التطبيق
class UpdateGate extends StatelessWidget {
  const UpdateGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    return ValueListenableBuilder<LatestRelease?>(
      valueListenable: lic.release,
      builder: (_, r, _) => lic.mandatoryUpdate ? const UpdateScreen(forced: true) : child,
    );
  }
}

/// إشعار التحديث العادي: مرة واحدة لكل build (يُحفظ في meta `upd_notified`)
class UpdateNotifier {
  UpdateNotifier(this.context);
  final BuildContext context;
  static const _k = 'upd_notified';
  bool _showing = false;

  Future<void> maybeShow() async {
    final lic = context.read<LicenseService>();
    final r = lic.release.value;
    if (_showing || r == null || !lic.updateAvailable || lic.mandatoryUpdate) return;
    if (lic.store.meta<int>(_k) == r.build) return;
    _showing = true;
    await lic.store.putMetaSilently({_k: r.build});
    if (!context.mounted) return;
    final go = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        final cs = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.lg, 0, Space.lg, Space.lg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer,
                        borderRadius: BorderRadius.circular(Radii.md),
                      ),
                      child: Icon(Icons.system_update_rounded, color: cs.onPrimaryContainer),
                    ),
                    const SizedBox(width: Space.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'تحديث جديد · ${r.version}',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                          ),
                          Text('بياناتك تبقى كما هي', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                        ],
                      ),
                    ),
                  ],
                ),
                if (r.notes.isNotEmpty) ...[
                  const SizedBox(height: Space.md),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 160),
                    child: SingleChildScrollView(child: Text(r.notes, style: const TextStyle(height: 1.6))),
                  ),
                ],
                const SizedBox(height: Space.lg),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        child: const Text('لاحقاً'),
                      ),
                    ),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () => Navigator.pop(ctx, true),
                        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(52)),
                        icon: const Icon(Icons.download_rounded),
                        label: const Text('تحديث'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    _showing = false;
    if (go == true && context.mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => const UpdateScreen()));
    }
  }
}
