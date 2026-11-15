import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/backup_service.dart';
import '../data/store.dart';
import 'backups_screen.dart';

/// أول تشغيل: 3 خطوات بسيطة بدل شاشة فارغة محيّرة
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final name = TextEditingController();
  final currency = TextEditingController(text: 'ريال');
  bool starter = true;
  bool busy = false;
  List<BackupFile> found = const [];

  @override
  void initState() {
    super.initState();
    // لو وُجدت نسخ احتياطية من تثبيت سابق (مثل واتساب) نعرض الاسترجاع مباشرة
    if (BackupService.supported) {
      context.read<BackupService>().list().then((l) {
        if (mounted) setState(() => found = l);
      });
    }
  }

  @override
  void dispose() {
    name.dispose();
    currency.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() => busy = true);
    final store = context.read<Store>();
    await store.setMeta('distributorName', name.text.trim());
    if (currency.text.trim().isNotEmpty) await store.setMeta('currency', currency.text.trim());
    if (starter && store.products.isEmpty) await store.addStarterProducts();
    await store.setMeta('onboarded', true);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
          children: [
            Center(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: Container(
                  width: 96,
                  height: 96,
                  color: cs.primary,
                  child: Icon(Icons.local_shipping_rounded, size: 52, color: cs.onPrimary),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'حساب الموزع',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'سجّل عطاء الصباح، وتعرف بالليل كم باقي عند كل بقالة.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 28),
            if (found.isNotEmpty) ...[
              Card(
                color: cs.primaryContainer,
                child: ListTile(
                  leading: Icon(Icons.restore, color: cs.onPrimaryContainer),
                  title: Text(
                    'وجدنا ${found.length} نسخة احتياطية على الجوال',
                    style: TextStyle(fontWeight: FontWeight.w700, color: cs.onPrimaryContainer),
                  ),
                  subtitle: Text('استرجع حساباتك السابقة', style: TextStyle(color: cs.onPrimaryContainer)),
                  trailing: Icon(Icons.chevron_left, color: cs.onPrimaryContainer),
                  onTap: () async {
                    final ok = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(builder: (_) => const BackupsScreen(pickToRestore: true)),
                    );
                    if (ok == true && context.mounted) await context.read<Store>().setMeta('onboarded', true);
                  },
                ),
              ),
              const SizedBox(height: 16),
            ],
            _step(context, 1, 'أضف الأصناف', 'زبادي، حقين... بأسعار البيع والشراء'),
            _step(context, 2, 'أضف البقالات', 'بترتيب طريقك اليومي'),
            _step(context, 3, 'كل يوم: عطاء الصبح وتحصيل الليل', 'والبرنامج يحسب الباقي تلقائياً'),
            const SizedBox(height: 20),
            TextField(
              controller: name,
              decoration: const InputDecoration(
                labelText: 'اسمك (اختياري، يظهر في الكشوفات)',
                prefixIcon: Icon(Icons.badge_outlined),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: currency,
              decoration: const InputDecoration(labelText: 'العملة', prefixIcon: Icon(Icons.payments_outlined)),
            ),
            const SizedBox(height: 8),
            CheckboxListTile(
              value: starter,
              onChanged: (v) => setState(() => starter = v ?? true),
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('أضف أصناف جاهزة (زبادي، حقين، لبن، جبن)'),
              subtitle: const Text('تقدر تعدّل الأسعار بعدين'),
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: busy ? null : _start,
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
              child: busy
                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5))
                  : const Text('ابدأ'),
            ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      setState(() => busy = true);
                      final store = context.read<Store>();
                      await store.loadDemo();
                      await store.setMeta('onboarded', true);
                    },
              child: const Text('جرّب ببيانات تجريبية أولاً'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _step(BuildContext c, int n, String title, String sub) {
    final cs = Theme.of(c).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: cs.secondaryContainer,
            child: Text(
              '$n',
              style: TextStyle(fontWeight: FontWeight.w700, color: cs.onSecondaryContainer),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15.5)),
                Text(sub, style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
