import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';

import 'core/command_service.dart';
import 'core/license_service.dart';
import 'core/update_service.dart';
import 'data/backup_service.dart';
import 'data/store.dart';
import 'screens/license_screen.dart';
import 'screens/onboarding_screen.dart';
import 'screens/reports_screen.dart';
import 'screens/shops_screen.dart';
import 'screens/today_screen.dart';
import 'screens/trader_screen.dart';
import 'screens/update_screen.dart';
import 'ui/app_drawer.dart';
import 'ui/shell.dart';
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

  // الترخيص عن بعد: يقرأ الحالة المحفوظة فوراً (بدون انتظار الشبكة) ثم يفحص في الخلفية
  final license = LicenseService(store);
  await license.init();
  final updates = UpdateService(store);
  // أوامر لوحة المنصة (إشعارات + سحب نسخة احتياطية) — منذ 2.6.0
  final commands = CommandService(store, license);

  WidgetsBinding.instance.addObserver(_Lifecycle(backup, license));
  // بعد أول إطار حتى لا تبطئ الإقلاع: نسخة احتياطية إن لزم + تنظيف ملفات تحديث قديمة
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(backup.runAuto());
    if (UpdateService.supported) unawaited(UpdateService.cleanup());
  });

  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(statusBarColor: Colors.transparent));

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: store),
        Provider.value(value: backup),
        ChangeNotifierProvider.value(value: license),
        ChangeNotifierProvider.value(value: updates),
        Provider.value(value: commands),
      ],
      child: const DistributorApp(),
    ),
  );
}

/// الخروج: نفّذ النسخة المعلّقة فوراً · العودة: أعد فحص الترخيص (بحد أدنى 10 دقائق بين الفحوص)
class _Lifecycle with WidgetsBindingObserver {
  _Lifecycle(this.backup, this.license);
  final BackupService backup;
  final LicenseService license;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) unawaited(backup.flushPending());
    if (state == AppLifecycleState.resumed) unawaited(license.onResumed());
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
      home: LicenseGate(child: onboarded ? const HomeShell() : const OnboardingScreen()),
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

  /// الشريط السفلي = عمل اليوم المتكرر فقط. كل ما سواه في القائمة الجانبية وزر ⚙
  static const _pages = <Widget>[TodayScreen(), ShopsScreen(), TraderTab(), ReportsScreen()];

  @override
  void initState() {
    super.initState();
    // فحص التحديث التلقائي (مرة كل 24 ساعة، أندرويد فقط) بعد استقرار الواجهة
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!UpdateService.supported) return;
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;
      final r = await context.read<UpdateService>().autoCheck();
      if (r != null && mounted) await showUpdateDialog(context, r);
    });
    // رسائل لوحة المنصة: تظهر كحوار واحد في كل مرة
    _inbox = context.read<CommandService>().inbox..addListener(_showInbox);
    WidgetsBinding.instance.addPostFrameCallback((_) => _showInbox());
  }

  late final ValueNotifier<List<InboxMessage>> _inbox;
  bool _showingMsg = false;

  Future<void> _showInbox() async {
    if (_showingMsg || !mounted || _inbox.value.isEmpty) return;
    _showingMsg = true;
    final m = _inbox.value.first;
    final cmds = context.read<CommandService>();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.campaign_rounded),
        title: Text(m.title.isEmpty ? 'رسالة من المطوّر' : m.title),
        content: m.body.isEmpty ? null : SingleChildScrollView(child: Text(m.body)),
        actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
      ),
    );
    await cmds.dismiss(m);
    _showingMsg = false;
    if (mounted) unawaited(_showInbox());
  }

  @override
  void dispose() {
    _inbox.removeListener(_showInbox);
    super.dispose();
  }

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
      // زر الرجوع في أندرويد: يغلق القائمة أولاً، ثم يرجع لـ"اليوم"، ثم يخرج
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _go(0);
      },
      child: Scaffold(
        key: shellScaffoldKey,
        drawer: AppDrawer(current: index, onNavigate: _go),
        drawerEdgeDragWidth: 24,
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
            NavigationDestination(
              icon: Icon(Icons.today_outlined),
              selectedIcon: Icon(Icons.today_rounded),
              label: 'اليوم',
            ),
            NavigationDestination(
              icon: Icon(Icons.storefront_outlined),
              selectedIcon: Icon(Icons.storefront_rounded),
              label: 'البقالات',
            ),
            NavigationDestination(
              icon: Icon(Icons.local_shipping_outlined),
              selectedIcon: Icon(Icons.local_shipping_rounded),
              label: 'التاجر',
            ),
            NavigationDestination(
              icon: Icon(Icons.insights_outlined),
              selectedIcon: Icon(Icons.insights_rounded),
              label: 'التقارير',
            ),
          ],
        ),
      ),
    );
  }
}
