import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';

/// اهتزاز خفيف عند الأفعال المهمة (حفظ، تحصيل، تبديل تبويب) — يمكن إيقافه من الإعدادات
void haptic(BuildContext c, {bool strong = false}) {
  if (!c.read<Store>().haptics) return;
  strong ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
}

/// رقم الإصدار المعروض (يطابق pubspec.yaml)
const kAppVersion = '2.2.0';

/// شبكة مسافات 4dp — كل الهوامش في التطبيق من هذه القيم فقط
abstract final class Space {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

/// أنصاف أقطار موحّدة
abstract final class Radii {
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 20;
  static const double xl = 28;
  static const double pill = 999;
}

/// أرقام بعرض ثابت حتى لا تهتز الأعمدة عند تغيّر القيم
const tabular = [FontFeature.tabularFigures()];

class AppColors {
  static const primary = Color(0xFF0F766E);
  static const debt = Color(0xFFC62828); // عليه
  static const debtDark = Color(0xFFFF8A80);
  static const credit = Color(0xFF1565C0); // له
  static const creditDark = Color(0xFF90CAF9);
  static const paid = Color(0xFF2E7D32);
  static const paidDark = Color(0xFFA5D6A7);
  static const warn = Color(0xFFC25400); // تباين 4.6:1 على الأبيض (WCAG AA)
  static const warnDark = Color(0xFFFFB74D); // للوضع الداكن (warn الفاتح 2.8:1 على الداكن)
  static const deep = Color(0xFF0B3D3A); // تدرّج الترويسات الفاخرة
  static const gold = Color(0xFFC9A227); // لمسة ذهبية للتمييز (زخرفي فقط، لا نص عليه)
  static const bgLight = Color(0xFFF3F6F5);
}

/// تدرّج البطاقات البطلة والترويسات — **ثابت في الوضعين** (أخضر داكن) والنص عليه [kOnHero] دائماً.
/// سابقاً كان من cs.primary: في الداكن primary فاتح و onPrimary داكن → نص 1.7:1 (كشفه ui_audit_test 2.3.0).
LinearGradient heroGradient(ColorScheme cs) => LinearGradient(
  colors: [AppColors.primary, Color.lerp(AppColors.primary, AppColors.deep, .75)!],
  begin: AlignmentDirectional.topStart,
  end: AlignmentDirectional.bottomEnd,
);

/// لون النص والأيقونات فوق [heroGradient] (تباين ≥ 5.4:1 مع أفتح نقطة في التدرّج)
const kOnHero = Colors.white;

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color debtColor(BuildContext c) => isDark(c) ? AppColors.debtDark : AppColors.debt;
Color creditColor(BuildContext c) => isDark(c) ? AppColors.creditDark : AppColors.credit;
Color warnColor(BuildContext c) => isDark(c) ? AppColors.warnDark : AppColors.warn;
Color paidColor(BuildContext c) => isDark(c) ? AppColors.paidDark : AppColors.paid;

/// لون الرصيد: أحمر لو عليه، أزرق لو له، أخضر لو مسدد
Color balanceColor(BuildContext c, int v) => v > 0 ? debtColor(c) : (v < 0 ? creditColor(c) : paidColor(c));

String balanceLabel(int v) => v > 0 ? 'عليه' : (v < 0 ? 'له' : 'مسدّد');

ThemeData buildTheme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: b);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    brightness: b,
    fontFamily: 'Plex',
    // أهداف لمس ≥ 48dp على كل المنصات (حتى في معاينة الويب)
    materialTapTargetSize: MaterialTapTargetSize.padded,
    visualDensity: VisualDensity.standard,
  );
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light ? AppColors.bgLight : cs.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: b == Brightness.light ? AppColors.bgLight : cs.surface,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: b == Brightness.light ? Colors.white : cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: b == Brightness.light ? Colors.white : cs.surfaceContainerHigh,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide(color: cs.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    drawerTheme: DrawerThemeData(
      width: 304,
      backgroundColor: b == Brightness.light ? Colors.white : cs.surfaceContainerLow,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadiusDirectional.horizontal(end: Radius.circular(Radii.xl)),
      ),
    ),
    // تحذير: لا تضع labelStyle بلا لون هنا — يلغي لون Material الافتراضي فيظهر النص أسود على الداكن.
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill)),
      labelStyle: TextStyle(fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      secondaryLabelStyle: TextStyle(fontWeight: FontWeight.w700, color: cs.onSecondaryContainer),
      selectedColor: cs.secondaryContainer,
      checkmarkColor: cs.onSecondaryContainer,
      side: BorderSide(color: cs.outlineVariant),
    ),
    listTileTheme: const ListTileThemeData(minVerticalPadding: 10, horizontalTitleGap: 14),
    bottomSheetTheme: const BottomSheetThemeData(
      showDragHandle: true,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.xl))),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.lg)),
    ),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      elevation: 0,
      backgroundColor: b == Brightness.light ? Colors.white : cs.surfaceContainer,
      indicatorColor: cs.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: st.contains(WidgetState.selected) ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
