import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/store.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shops_screen.dart';
import 'screens/today_screen.dart';
import 'screens/trader_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = Store();
  await store.init();
  // معاينة الويب فقط: تحميل بيانات تجريبية حتى تظهر الشاشات ممتلئة. نسخة أندرويد تبدأ فارغة.
  if (kIsWeb && store.isEmpty) await store.loadDemo();
  runApp(ChangeNotifierProvider.value(value: store, child: const DistributorApp()));
}

class DistributorApp extends StatelessWidget {
  const DistributorApp({super.key});

  @override
  Widget build(BuildContext context) {
    final mode = context.select<Store, int>((s) => s.themeMode);
    final scale = context.select<Store, double>((s) => s.textScale);
    return MaterialApp(
      title: 'حساب الموزع',
      debugShowCheckedModeBanner: false,
      locale: const Locale('ar'),
      supportedLocales: const [Locale('ar')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      themeMode: const [ThemeMode.system, ThemeMode.light, ThemeMode.dark][mode.clamp(0, 2)],
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: const HomeShell(),
    );
  }
}

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});
  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int index = 0;

  static const _pages = [TodayScreen(), ShopsScreen(), TraderTab(), ReportsScreen(), SettingsScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(bottom: false, child: IndexedStack(index: index, children: _pages)),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) => setState(() => index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'اليوم'),
          NavigationDestination(icon: Icon(Icons.storefront_outlined), selectedIcon: Icon(Icons.storefront), label: 'البقالات'),
          NavigationDestination(icon: Icon(Icons.local_shipping_outlined), selectedIcon: Icon(Icons.local_shipping), label: 'التاجر'),
          NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'التقارير'),
          NavigationDestination(icon: Icon(Icons.more_horiz), selectedIcon: Icon(Icons.more_horiz), label: 'المزيد'),
        ],
      ),
    );
  }
}
