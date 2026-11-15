/// developer_screen.dart — تواصل مع المطوّر (اتصال · واتساب · الموقع · صفحة التنزيلات).
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/developer.dart';
import '../ui/theme.dart';
import '../ui/widgets.dart';

Future<void> openUri(BuildContext context, Uri u) async {
  final ok = await launchUrl(u, mode: LaunchMode.externalApplication).catchError((_) => false);
  if (!ok && context.mounted) toast(context, 'تعذّر الفتح على هذا الجهاز');
}

class DeveloperScreen extends StatelessWidget {
  const DeveloperScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('تواصل مع المطوّر')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.md, Space.xl),
        children: [
          Container(
            padding: const EdgeInsets.all(Space.xl),
            decoration: BoxDecoration(gradient: heroGradient(cs), borderRadius: BorderRadius.circular(Radii.lg)),
            child: Column(
              children: [
                CircleAvatar(
                  radius: 34,
                  backgroundColor: cs.onPrimary.withValues(alpha: .15),
                  child: Icon(Icons.code_rounded, size: 34, color: cs.onPrimary),
                ),
                const SizedBox(height: Space.md),
                Text(
                  Developer.name,
                  style: TextStyle(color: cs.onPrimary, fontWeight: FontWeight.w700, fontSize: 20),
                ),
                const SizedBox(height: Space.xs),
                Text(
                  'تطوير وتصميم «حساب الموزع»',
                  style: TextStyle(color: cs.onPrimary.withValues(alpha: .85)),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.md),
          Card(
            margin: EdgeInsets.zero,
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                _Row(
                  icon: Icons.chat_rounded,
                  color: const Color(0xFF1FA855),
                  title: 'واتساب',
                  sub: Developer.phoneDisplay,
                  onTap: () => openUri(context, Developer.whatsapp('السلام عليكم، بخصوص تطبيق حساب الموزع')),
                ),
                const Divider(height: 1, indent: 64),
                _Row(
                  icon: Icons.call_rounded,
                  color: cs.primary,
                  title: 'اتصال',
                  sub: Developer.phoneDisplay,
                  onTap: () => openUri(context, Developer.tel),
                ),
                const Divider(height: 1, indent: 64),
                _Row(
                  icon: Icons.language_rounded,
                  color: cs.tertiary,
                  title: 'الموقع',
                  sub: Developer.website,
                  onTap: () => openUri(context, Developer.site),
                ),
                const Divider(height: 1, indent: 64),
                _Row(
                  icon: Icons.download_rounded,
                  color: cs.secondary,
                  title: 'صفحة التنزيلات',
                  sub: Developer.downloads,
                  onTap: () => openUri(context, Developer.downloadsSite),
                ),
              ],
            ),
          ),
          const SizedBox(height: Space.lg),
          Text(
            'جميع الحقوق محفوظة © ${DateTime.now().year} ${Developer.name}\nالإصدار $kAppVersion',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5, height: 1.6),
          ),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.icon, required this.color, required this.title, required this.sub, required this.onTap});
  final IconData icon;
  final Color color;
  final String title;
  final String sub;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => ListTile(
    onTap: onTap,
    minVerticalPadding: 14,
    leading: Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: .14), borderRadius: BorderRadius.circular(Radii.md)),
      child: Icon(icon, color: color),
    ),
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
    subtitle: Text(sub, textDirection: TextDirection.ltr, textAlign: TextAlign.end),
    trailing: const Icon(Icons.chevron_left_rounded),
  );
}
