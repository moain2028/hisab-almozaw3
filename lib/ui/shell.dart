/// shell.dart — أزرار الرأس المشتركة لكل الشاشات الرئيسية.
///
/// الشاشات الرئيسية لها Scaffold خاص بها داخل Scaffold الهيكل (الذي يملك القائمة الجانبية)،
/// لذلك لا يظهر زر ☰ تلقائياً. نستخدم مفتاحاً عاماً واحداً لفتح القائمة من أي رأس.
library;

import 'package:flutter/material.dart';

import '../screens/settings_screen.dart';

/// مفتاح Scaffold الهيكل (HomeShell) — يملك القائمة الجانبية
final shellScaffoldKey = GlobalKey<ScaffoldState>();

/// زر ☰ يفتح القائمة الجانبية
class MenuButton extends StatelessWidget {
  const MenuButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'القائمة',
    icon: const Icon(Icons.menu_rounded),
    onPressed: () => shellScaffoldKey.currentState?.openDrawer(),
  );
}

/// زر ⚙ يفتح الإعدادات — موجود في رأس كل شاشة رئيسية
class SettingsButton extends StatelessWidget {
  const SettingsButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: 'الإعدادات',
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())),
  );
}
