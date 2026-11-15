import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/license_service.dart';
import '../ui/theme.dart';
import '../core/developer.dart';
import 'backups_screen.dart';
import 'developer_screen.dart';

/// شاشة القفل: تظهر بدل التطبيق عند إيقاف الترخيص. البيانات لا تُمس.
class LicenseLockScreen extends StatefulWidget {
  const LicenseLockScreen({super.key});
  @override
  State<LicenseLockScreen> createState() => _LicenseLockScreenState();
}

class _LicenseLockScreenState extends State<LicenseLockScreen> {
  final ctl = TextEditingController();
  bool busy = false;
  String? error;

  @override
  void dispose() {
    ctl.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    if (ctl.text.trim().isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    final ok = await context.read<LicenseService>().unlock(ctl.text);
    if (!mounted) return;
    setState(() {
      busy = false;
      error = ok ? null : 'الكود غير صحيح';
    });
  }

  @override
  Widget build(BuildContext context) {
    final lic = context.watch<LicenseService>();
    final st = lic.state;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(Space.lg),
              children: [
                Icon(Icons.lock_rounded, size: 72, color: cs.primary),
                const SizedBox(height: Space.md),
                const Text(
                  'التطبيق موقوف',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: Space.sm),
                Text(
                  st.message.isEmpty ? 'يرجى التواصل مع المطوّر للحصول على كود التفعيل.' : st.message,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 15, height: 1.6),
                ),
                const SizedBox(height: Space.sm),
                Card(
                  color: paidColor(context).withValues(alpha: .08),
                  child: const Padding(
                    padding: EdgeInsets.all(Space.sm),
                    child: Row(
                      children: [
                        Icon(Icons.shield_outlined, size: 20),
                        SizedBox(width: Space.sm),
                        Expanded(child: Text('بياناتك محفوظة كما هي ولم يُحذف أي شيء.')),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: Space.lg),
                if (st.codeAccepted) ...[
                  TextField(
                    controller: ctl,
                    textAlign: TextAlign.center,
                    textCapitalization: TextCapitalization.characters,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: 2),
                    decoration: InputDecoration(hintText: 'كود التفعيل', errorText: error),
                    onSubmitted: (_) => _unlock(),
                  ),
                  const SizedBox(height: Space.md),
                  FilledButton(
                    onPressed: busy ? null : _unlock,
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                    child: busy
                        ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                        : const Text('تفعيل'),
                  ),
                ],
                const SizedBox(height: Space.sm),
                OutlinedButton.icon(
                  onPressed: busy ? null : lic.refresh,
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.refresh),
                  label: const Text('إعادة الفحص'),
                ),
                // طلب كود التفعيل مباشرة من المطوّر (واتساب)
                FilledButton.tonalIcon(
                  onPressed: () => openUri(context, Developer.whatsapp('أريد كود تفعيل تطبيق حساب الموزع')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  icon: const Icon(Icons.chat_rounded),
                  label: const Text('اطلب الكود من المطوّر (واتساب)'),
                ),
                // حتى أثناء القفل يستطيع المستخدم أخذ نسخة من بياناته
                TextButton.icon(
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const BackupsScreen())),
                  icon: const Icon(Icons.cloud_download_outlined),
                  label: const Text('نسخة احتياطية من بياناتي'),
                ),
                if (st.offline)
                  const Padding(
                    padding: EdgeInsets.only(top: Space.sm),
                    child: Text('لا يوجد اتصال الآن — تُعرض آخر حالة معروفة.', textAlign: TextAlign.center),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// يلف التطبيق: إن كان الترخيص موقوفاً تظهر شاشة القفل بدل المحتوى
class LicenseGate extends StatelessWidget {
  const LicenseGate({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final allowed = context.select<LicenseService, bool>((l) => l.allowed);
    return allowed ? child : const LicenseLockScreen();
  }
}
