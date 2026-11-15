import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../data/store.dart';

/// اهتزاز خفيف عند الأفعال المهمة (حفظ، تحصيل، تبديل تبويب) — يمكن إيقافه من الإعدادات
void haptic(BuildContext c, {bool strong = false}) {
  if (!c.read<Store>().haptics) return;
  strong ? HapticFeedback.mediumImpact() : HapticFeedback.selectionClick();
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
}

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color debtColor(BuildContext c) => isDark(c) ? AppColors.debtDark : AppColors.debt;
Color creditColor(BuildContext c) => isDark(c) ? AppColors.creditDark : AppColors.credit;
Color paidColor(BuildContext c) => isDark(c) ? AppColors.paidDark : AppColors.paid;

/// لون الرصيد: أحمر لو عليه، أزرق لو له، أخضر لو مسدد
Color balanceColor(BuildContext c, int v) => v > 0 ? debtColor(c) : (v < 0 ? creditColor(c) : paidColor(c));

String balanceLabel(int v) => v > 0 ? 'عليه' : (v < 0 ? 'له' : 'مسدّد');

ThemeData buildTheme(Brightness b) {
  final cs = ColorScheme.fromSeed(seedColor: AppColors.primary, brightness: b);
  final base = ThemeData(useMaterial3: true, colorScheme: cs, brightness: b, fontFamily: 'Plex');
  return base.copyWith(
    scaffoldBackgroundColor: b == Brightness.light ? const Color(0xFFF4F7F6) : cs.surface,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: b == Brightness.light ? const Color(0xFFF4F7F6) : cs.surface,
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
      ),
    ),
    dialogTheme: DialogThemeData(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22))),
    navigationBarTheme: NavigationBarThemeData(
      height: 68,
      labelTextStyle: WidgetStateProperty.all(const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
