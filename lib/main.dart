import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'data/backup_service.dart';
import 'data/store.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/shops_screen.dart';
import 'screens/today_screen.dart';
import 'screens/trader_screen.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // أي خطأ غير متوقع يُسجَّل بدلاً من إغلاق التطبيق
  FlutterError.onError = (d) {
    FlutterError.presentError(d);
    if (kDebugMode) debugPrint('FlutterError: ${d.exceptionAsString()}');
  };
  PlatformDispatcher.instance.onError = (e, s) {
    if (kDebugMode) debugPrint('Uncaught: $e\n$s');
    return true;
  };

  // تقليل استهلاك الذاكرة لكاش الصور (التطبيق لا يعرض صوراً كثيرة)
  PaintingBinding.instance.imageCache
    ..maximumSize = 50
    ..maximumSizeBytes = 20 << 20;

  final store = Store();
  await store.init();
  // معاينة الويب فقط: بيانات تجريبية حتى تظهر الشاشات ممتلئة. نسخة أندرويد تبدأ فارغة.
  if (kIsWeb && store.isEmpty) {
    await store.loadDemo();
    await store.setMeta('onboarded', true);
  }

  final backup = BackupService(store);
  store
    ..onDataChanged = backup.scheduleAuto
    ..attachLifecycle();
  WidgetsBinding.instance.addObserver(_BackupLifecycle(backup));
  // نسخة عند الفتح إن وُجدت تغييرات لم تُنسخ (بعد أول إطار حتى لا تبطئ الإقلاع)
  WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(backup.runAuto()));

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        Provider.value(value: backup),
      ],
      child: const DistributorApp(),
    ),
  );
}

/// عند خروج المستخدم من التطبيق: نفّذ النسخة المعلّقة فوراً
class _BackupLifecycle with WidgetsBindingObserver {
  _BackupLifecycle(this.backup);
  final BackupService backup;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(backup.flushPending());
  }
}

class DistributorApp extends StatelessWidget {
  const DistributorApp({super.key});

  @override
  Widget build(BuildContext context) {
    // نعيد بناء MaterialApp فقط عند تغيّر المظهر/الخط، وليس مع كل تعديل بيانات
    final mode = context.select<Store, int>((s) => s.themeMode);
    final scale = context.select<Store, double>((s) => s.textScale);
    final onboarded = context.select<Store, bool>((s) => s.onboarded);
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
      home: onboarded ? const HomeShell() : const OnboardingScreen(),
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

  /// الصفحات تُبنى عند أول زيارة فقط (Lazy) ثم تبقى في الذاكرة للتنقل الفوري
  final _built = <int>{0};

  static const _pages = <Widget>[TodayScreen(), ShopsScreen(), TraderTab(), ReportsScreen(), SettingsScreen()];

  void _go(int i) {
    if (i == index) return;
    haptic(context);
    setState(() {
      index = i;
      _built.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // زر الرجوع في أندرويد: من أي تبويب يرجع لـ"اليوم" أولاً قبل الخروج
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: IndexedStack(
            index: index,
            children: [
              for (var i = 0; i < _pages.length; i++)
                _built.contains(i)
                    // TickerMode يوقف أي حركة في الصفحات المخفية (يوفّر المعالج والبطارية)
                    ? TickerMode(enabled: i == index, child: _pages[i])
                    : const SizedBox.shrink(),
            ],
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: _go,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'اليوم'),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront),
              label: 'البقالات',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping),
              label: 'التاجر',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights),
              label: 'التقارير',
            ),
            NavigationDestination(icon: Icon(Icons.tune_outlined), selectedIcon: Icon(Icons.tune), label: 'المزيد'),
          ],
        ),
      ),
    );
  }
}
