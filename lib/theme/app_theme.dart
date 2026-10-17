import 'package:flutter/material.dart';

/// ── 圆角 ──────────────────────────────────────────────
class AppRadius {
  AppRadius._();
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
}

/// ── 间距 ──────────────────────────────────────────────
class AppGap {
  AppGap._();
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 28;
}

/// ── 品牌色 ────────────────────────────────────────────
///
/// 靛蓝单主色 + 极低饱和的分类底色。
/// 页面里不要再出现 `Colors.blue.shade200` 这类硬编码：
/// 一是深色模式下会失效，二是换配色要改几十处。
class AppColors {
  AppColors._();

  static const brand = Color(0xFF4C6FFF);
  static const brandDeep = Color(0xFF3452E0);
  static const brandSoft = Color(0xFFEDF1FF);
  static const brandSoftDark = Color(0xFF1E2742);

  /// 支出红 / 收入绿（中国习惯，与欧美相反）
  static const expense = Color(0xFFE5484D);
  static const income = Color(0xFF12A150);

  static const lightBg = Color(0xFFF4F6FA);
  static const lightSurface = Color(0xFFFFFFFF);
  static const lightSurfaceAlt = Color(0xFFF7F8FB);
  static const lightText = Color(0xFF151922);
  static const lightTextSecondary = Color(0xFF6B7385);
  static const lightTextTertiary = Color(0xFF9CA3B2);
  static const lightHairline = Color(0xFFEDEFF4);

  static const darkBg = Color(0xFF0E1015);
  static const darkSurface = Color(0xFF181B22);
  static const darkSurfaceAlt = Color(0xFF20242D);
  static const darkText = Color(0xFFF1F3F8);
  static const darkTextSecondary = Color(0xFF98A1B2);
  static const darkTextTertiary = Color(0xFF6C7587);
  static const darkHairline = Color(0xFF272C36);
}

/// 主题之外的语义色（ColorScheme 装不下的部分）
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  final Color expense;
  final Color income;
  final Color expenseSoft;
  final Color incomeSoft;
  final Color brandSoft;
  final Color textSecondary;
  final Color textTertiary;
  final Color hairline;
  final Color surfaceAlt;

  const AppPalette({
    required this.expense,
    required this.income,
    required this.expenseSoft,
    required this.incomeSoft,
    required this.brandSoft,
    required this.textSecondary,
    required this.textTertiary,
    required this.hairline,
    required this.surfaceAlt,
  });

  static const light = AppPalette(
    expense: AppColors.expense,
    income: AppColors.income,
    expenseSoft: Color(0xFFFDECEC),
    incomeSoft: Color(0xFFE8F7EE),
    brandSoft: AppColors.brandSoft,
    textSecondary: AppColors.lightTextSecondary,
    textTertiary: AppColors.lightTextTertiary,
    hairline: AppColors.lightHairline,
    surfaceAlt: AppColors.lightSurfaceAlt,
  );

  static const dark = AppPalette(
    expense: Color(0xFFFF6B70),
    income: Color(0xFF35C77A),
    expenseSoft: Color(0xFF3A1F22),
    incomeSoft: Color(0xFF16311F),
    brandSoft: AppColors.brandSoftDark,
    textSecondary: AppColors.darkTextSecondary,
    textTertiary: AppColors.darkTextTertiary,
    hairline: AppColors.darkHairline,
    surfaceAlt: AppColors.darkSurfaceAlt,
  );

  @override
  AppPalette copyWith({
    Color? expense,
    Color? income,
    Color? expenseSoft,
    Color? incomeSoft,
    Color? brandSoft,
    Color? textSecondary,
    Color? textTertiary,
    Color? hairline,
    Color? surfaceAlt,
  }) {
    return AppPalette(
      expense: expense ?? this.expense,
      income: income ?? this.income,
      expenseSoft: expenseSoft ?? this.expenseSoft,
      incomeSoft: incomeSoft ?? this.incomeSoft,
      brandSoft: brandSoft ?? this.brandSoft,
      textSecondary: textSecondary ?? this.textSecondary,
      textTertiary: textTertiary ?? this.textTertiary,
      hairline: hairline ?? this.hairline,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      expense: Color.lerp(expense, other.expense, t)!,
      income: Color.lerp(income, other.income, t)!,
      expenseSoft: Color.lerp(expenseSoft, other.expenseSoft, t)!,
      incomeSoft: Color.lerp(incomeSoft, other.incomeSoft, t)!,
      brandSoft: Color.lerp(brandSoft, other.brandSoft, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textTertiary: Color.lerp(textTertiary, other.textTertiary, t)!,
      hairline: Color.lerp(hairline, other.hairline, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
    );
  }
}

/// 页面里统一用 `context.palette.xxx` 取语义色
extension AppThemeContext on BuildContext {
  AppPalette get palette =>
      Theme.of(this).extension<AppPalette>() ?? AppPalette.light;

  bool get isDark => Theme.of(this).brightness == Brightness.dark;
}

/// 金额文本样式 —— 等宽数字，保证多行金额小数点对齐
TextStyle moneyStyle({
  required double size,
  required Color color,
  FontWeight weight = FontWeight.w700,
  double? letterSpacing,
}) {
  return TextStyle(
    fontSize: size,
    color: color,
    fontWeight: weight,
    letterSpacing: letterSpacing ?? -0.2,
    fontFeatures: const [FontFeature.tabularFigures()],
    height: 1.15,
  );
}

class AppTheme {
  AppTheme._();

  static ThemeData light() => _build(Brightness.light, AppPalette.light);
  static ThemeData dark() => _build(Brightness.dark, AppPalette.dark);

  static ThemeData _build(Brightness brightness, AppPalette palette) {
    final isDark = brightness == Brightness.dark;
    final bg = isDark ? AppColors.darkBg : AppColors.lightBg;
    final surface = isDark ? AppColors.darkSurface : AppColors.lightSurface;
    final text = isDark ? AppColors.darkText : AppColors.lightText;
    final brand = isDark ? const Color(0xFF7D95FF) : AppColors.brand;

    final scheme = ColorScheme.fromSeed(
      seedColor: AppColors.brand,
      brightness: brightness,
    ).copyWith(
      primary: brand,
      onPrimary: Colors.white,
      primaryContainer: palette.brandSoft,
      onPrimaryContainer: brand,
      surface: surface,
      onSurface: text,
      onSurfaceVariant: palette.textSecondary,
      outlineVariant: palette.hairline,
      error: palette.expense,
    );

    final base = ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: bg,
      splashFactory: InkSparkle.splashFactory,
      extensions: [palette],
    );

    return base.copyWith(
      textTheme: base.textTheme.apply(
        bodyColor: text,
        displayColor: text,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: bg,
        surfaceTintColor: Colors.transparent,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: text,
          letterSpacing: -0.2,
        ),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
      ),
      dividerTheme: DividerThemeData(
        color: palette.hairline,
        thickness: 1,
        space: 1,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: brand.withValues(alpha: 0.35),
          disabledForegroundColor: Colors.white70,
          elevation: 0,
          minimumSize: const Size.fromHeight(52),
          textStyle: const TextStyle(
              fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: text,
          backgroundColor: surface,
          minimumSize: const Size.fromHeight(52),
          side: BorderSide(color: palette.hairline),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: brand,
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: palette.surfaceAlt,
        hintStyle: TextStyle(color: palette.textTertiary, fontSize: 15),
        labelStyle: TextStyle(color: palette.textSecondary, fontSize: 14),
        floatingLabelStyle: TextStyle(color: brand, fontSize: 13),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
          borderSide: BorderSide(color: brand, width: 1.6),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: palette.surfaceAlt,
        selectedColor: palette.brandSoft,
        side: BorderSide.none,
        labelStyle: TextStyle(fontSize: 13, color: palette.textSecondary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor:
            isDark ? const Color(0xFF2C313C) : const Color(0xFF23272F),
        contentTextStyle: const TextStyle(fontSize: 14, color: Colors.white),
        elevation: 0,
        insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
        titleTextStyle: TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: text,
        ),
        contentTextStyle: TextStyle(
          fontSize: 14.5,
          height: 1.55,
          color: palette.textSecondary,
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        height: 64,
        indicatorColor: palette.brandSoft,
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(999),
        ),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 11.5,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
            color: selected ? brand : palette.textTertiary,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 23,
            color: selected ? brand : palette.textTertiary,
          );
        }),
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: brand,
        linearMinHeight: 5,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: palette.textSecondary,
        textColor: text,
      ),
    );
  }
}
