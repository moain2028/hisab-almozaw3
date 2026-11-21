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
const kAppVersion = '2.7.0';

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

/// لوحة «بنفسجي وذهبي» — مأخوذة حرفياً من متغيرات CSS في «كتاب البيت» (docs/plans/2.4.0-plan.md).
class AppColors {
  // بنفسجي (plum) — الهوية
  static const primary = Color(0xFF5A1030); // --plum
  static const plum2 = Color(0xFF3A0A1F); // --plum2
  static const deep = Color(0xFF2B0716); // --plum3
  static const rose = Color(0xFFA3154F); // --rose
  static const blush = Color(0xFFFBEAF0); // --blush

  // ذهبي شامباني — الفخامة (أزرار الإجراء الرئيسية، الخطوط والزخارف)
  static const gold = Color(0xFFB8924E); // --gold
  static const goldDeep = Color(0xFFC9A86A); // --gold-deep
  static const goldHi = Color(0xFF8A6527); // --gold-hi (ذهبي للنص على الفاتح، تباين 5.0:1)
  static const champ = Color(0xFFE9D3A6); // --champ
  static const goldLight = Color(0xFFF5E6C4);
  static const goldMid = Color(0xFFE2C68E);

  // خلفيات ونص
  static const bgLight = Color(0xFFFBF5F1); // --bg
  static const bg2 = Color(0xFFF5EAE5); // --bg2
  static const ink = Color(0xFF2B1720); // --ink
  static const ink2 = Color(0xFF4A3039); // --ink2
  static const muted = Color(0xFF6E5862); // --muted
  static const bgDark = Color(0xFF170610); // مشتق من plum3 للوضع الداكن

  // دلالي
  static const debt = Color(0xFFB3261E); // --danger (عليه)
  static const debtDark = Color(0xFFFF8F86);
  static const credit = Color(0xFF1F4E8C); // له
  static const creditDark = Color(0xFF9EC1F2);
  static const paid = Color(0xFF1E7A46); // --ok
  static const paidDark = Color(0xFF8FD6AA);
  static const warn = Color(0xFF7A4A00); // --warn
  static const warnDark = Color(0xFFF2C46B);
}

/// تدرّج البطاقات البطلة والترويسات — بنفسجي ملكي **ثابت في الوضعين** (مثل بطل كتاب البيت) والنص عليه [kOnHero].
LinearGradient heroGradient(ColorScheme cs) => const LinearGradient(
  colors: [Color(0xFF7A1844), AppColors.primary, AppColors.plum2],
  stops: [0, .55, 1],
  begin: AlignmentDirectional.topStart,
  end: AlignmentDirectional.bottomEnd,
);

/// التدرّج الذهبي (--gold-grad) لأزرار الإجراء الرئيسية؛ النص عليه [kOnGold].
const goldGradient = LinearGradient(
  colors: [AppColors.goldLight, AppColors.goldMid, AppColors.goldDeep],
  begin: AlignmentDirectional.topStart,
  end: AlignmentDirectional.bottomEnd,
);

/// نص فوق الذهبي: بنفسجي داكن (تباين ≥ 7:1 مع أغمق نقطة)
const kOnGold = AppColors.deep;

/// لون النص فوق [heroGradient] (تباين ≥ 9:1 مع أفتح نقطة #7A1844)
const kOnHero = Colors.white;

/// لمسة ذهبية للعناوين الصغيرة داخل البطل (تباين ≥ 4.5:1)
const kOnHeroGold = AppColors.champ;

bool isDark(BuildContext c) => Theme.of(c).brightness == Brightness.dark;
Color debtColor(BuildContext c) => isDark(c) ? AppColors.debtDark : AppColors.debt;
Color creditColor(BuildContext c) => isDark(c) ? AppColors.creditDark : AppColors.credit;
Color warnColor(BuildContext c) => isDark(c) ? AppColors.warnDark : AppColors.warn;
Color paidColor(BuildContext c) => isDark(c) ? AppColors.paidDark : AppColors.paid;

/// لون الرصيد: أحمر لو عليه، أزرق لو له، أخضر لو مسدد
Color balanceColor(BuildContext c, int v) => v > 0 ? debtColor(c) : (v < 0 ? creditColor(c) : paidColor(c));

String balanceLabel(int v) => v > 0 ? 'عليه' : (v < 0 ? 'له' : 'مسدّد');

/// خط التطبيق. **كل TextStyle داخل الثيم يجب أن يحمله صراحةً**: أنماط مثل appBarTheme.titleTextStyle
/// لا ترث fontFamily من ThemeData، فتسقط لخط النظام (عناوين وأزرار بخط مختلف — كُشف في 2.3.0).
const kFont = 'Plex';

ThemeData buildTheme(Brightness b) {
  final light = b == Brightness.light;
  // لوحة مبنية يدوياً (لا fromSeed): fromSeed يولّد درجات بعيدة عن المرجع.
  final cs = light
      ? const ColorScheme(
          brightness: Brightness.light,
          primary: AppColors.primary,
          onPrimary: Colors.white,
          primaryContainer: Color(0xFFF6E3EA),
          onPrimaryContainer: AppColors.deep,
          secondary: AppColors.goldHi,
          onSecondary: Colors.white,
          secondaryContainer: AppColors.goldLight,
          onSecondaryContainer: Color(0xFF3D2A08),
          tertiary: AppColors.rose,
          onTertiary: Colors.white,
          tertiaryContainer: AppColors.blush,
          onTertiaryContainer: Color(0xFF4A0624),
          error: AppColors.debt,
          onError: Colors.white,
          errorContainer: Color(0xFFFDEDEB),
          onErrorContainer: Color(0xFF5C0E0A),
          surface: AppColors.bgLight,
          onSurface: AppColors.ink,
          onSurfaceVariant: AppColors.muted,
          surfaceContainerLowest: Colors.white,
          surfaceContainerLow: Color(0xFFFDF9F7),
          surfaceContainer: Color(0xFFF8EFEB),
          surfaceContainerHigh: AppColors.bg2,
          surfaceContainerHighest: Color(0xFFEEDFDA),
          outline: Color(0xFF9A8590),
          outlineVariant: Color(0xFFE6D6DC),
          inverseSurface: AppColors.ink,
          onInverseSurface: AppColors.bgLight,
          inversePrimary: AppColors.champ,
          shadow: AppColors.deep,
          scrim: Colors.black,
        )
      : const ColorScheme(
          brightness: Brightness.dark,
          primary: Color(0xFFF2B8CF),
          onPrimary: AppColors.deep,
          primaryContainer: Color(0xFF5A1030),
          onPrimaryContainer: Color(0xFFFFE3ED),
          secondary: AppColors.goldMid,
          onSecondary: Color(0xFF2E1F04),
          secondaryContainer: Color(0xFF4A3A1C),
          onSecondaryContainer: AppColors.goldLight,
          tertiary: Color(0xFFFF9EC4),
          onTertiary: Color(0xFF4A0624),
          tertiaryContainer: Color(0xFF6E1238),
          onTertiaryContainer: AppColors.blush,
          error: AppColors.debtDark,
          onError: Color(0xFF5C0E0A),
          errorContainer: Color(0xFF7A1A14),
          onErrorContainer: Color(0xFFFFDAD5),
          surface: AppColors.bgDark,
          onSurface: Color(0xFFF4E6EB),
          onSurfaceVariant: Color(0xFFD2BCC5),
          surfaceContainerLowest: Color(0xFF12040B),
          surfaceContainerLow: Color(0xFF1E0A15),
          surfaceContainer: Color(0xFF251019),
          surfaceContainerHigh: Color(0xFF30161F),
          surfaceContainerHighest: Color(0xFF3B1D29),
          outline: Color(0xFF9A8590),
          outlineVariant: Color(0xFF4A2B37),
          inverseSurface: Color(0xFFF4E6EB),
          onInverseSurface: AppColors.deep,
          inversePrimary: AppColors.primary,
          shadow: Colors.black,
          scrim: Colors.black,
        );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: cs,
    brightness: b,
    fontFamily: kFont,
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
      titleTextStyle: TextStyle(fontFamily: kFont, fontSize: 21, fontWeight: FontWeight.w700, color: cs.onSurface),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: const EdgeInsets.symmetric(vertical: 5),
      color: light ? Colors.white : cs.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: cs.outlineVariant),
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
        // الزر الممتلئ = بنفسجي بالفاتح، ذهبي بالداكن (مثل أزرار المرجع)
        backgroundColor: light ? AppColors.primary : AppColors.goldMid,
        foregroundColor: light ? Colors.white : AppColors.deep,
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(64, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontFamily: kFont, fontSize: 15, fontWeight: FontWeight.w700),
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
      labelStyle: TextStyle(fontFamily: kFont, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant),
      secondaryLabelStyle: TextStyle(fontFamily: kFont, fontWeight: FontWeight.w700, color: cs.onSecondaryContainer),
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
      indicatorColor: light ? const Color(0xFFF6E3EA) : const Color(0xFF5A1030),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (st) => TextStyle(
          fontFamily: kFont,
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: st.contains(WidgetState.selected) ? cs.onSurface : cs.onSurfaceVariant,
        ),
      ),
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
