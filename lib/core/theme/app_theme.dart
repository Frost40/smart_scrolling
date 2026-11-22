import 'package:flutter/material.dart';

import 'app_sizes.dart';
import 'theme_extensions.dart';

/// The one theme builder behind `lightMode()` and `darkMode()`.
/// Text, buttons, fields, chips, cards, dialogs and the navigation bar are styled here, once.
ThemeData buildTheme(Brightness brightness, {required bool highContrast}) {
  final colors = AppColors.generate(brightness, highContrast: highContrast);
  final scheme = AppColors.schemeFor(brightness, highContrast: highContrast);
  final light = brightness == Brightness.light;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: AppFonts.sans,
  );
  final t = base.textTheme.apply(
    bodyColor: colors.text,
    displayColor: colors.text,
  );
  final text = t.copyWith(
    headlineMedium: t.headlineMedium!.copyWith(
      fontSize: AppSizes.headingText,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
    ),
    headlineSmall: t.headlineSmall!.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.2,
    ),
    titleLarge: t.titleLarge!.copyWith(
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      height: 1.25,
    ),
    titleMedium: t.titleMedium!.copyWith(fontWeight: FontWeight.w600),
    titleSmall: t.titleSmall!.copyWith(fontWeight: FontWeight.w600),
    labelLarge: t.labelLarge!.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
    ),
    labelMedium: t.labelMedium!.copyWith(fontWeight: FontWeight.w600),
    bodyMedium: t.bodyMedium!.copyWith(color: colors.textMuted),
  );
  final rounded = RoundedRectangleBorder(
    borderRadius: BorderRadius.circular(AppRadius.button),
  );
  final buttonSize = const Size(AppSizes.minTap, AppSizes.buttonHeight);
  final buttonText = text.labelLarge!.copyWith(fontSize: 16);
  OutlineInputBorder field([Color? color, double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.field),
        borderSide: color == null
            ? BorderSide.none
            : BorderSide(color: color, width: width),
      );
  return base.copyWith(
    extensions: [colors],
    textTheme: text,
    scaffoldBackgroundColor: colors.background,
    dividerColor: colors.divider,
    dividerTheme: DividerThemeData(color: colors.divider, space: 1),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: _GentleTransitions(),
        TargetPlatform.iOS: _GentleTransitions(),
      },
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: colors.background,
      foregroundColor: colors.text,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge!.copyWith(fontSize: 24),
    ),
    // Light: a soft lift off the grey. Dark: shadows don't show, so a hairline.
    cardTheme: CardThemeData(
      color: colors.card,
      elevation: light ? 2 : 0,
      shadowColor: scheme.shadow.withValues(alpha: 0.35),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
        side: highContrast
            ? BorderSide(color: colors.divider)
            : light
            ? BorderSide.none
            : BorderSide(color: colors.cardMuted),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      indicatorColor: colors.tint(colors.primary),
      elevation: 0,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium!.copyWith(
          color: s.contains(WidgetState.selected)
              ? colors.text
              : colors.textMuted,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          color: s.contains(WidgetState.selected)
              ? colors.primary
              : colors.textMuted,
        ),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: colors.cardMuted,
      selectedColor: colors.tint(colors.primary),
      side: BorderSide.none,
      showCheckmark: false,
      labelStyle: text.labelLarge,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: colors.cardMuted,
      border: field(),
      enabledBorder: highContrast ? field(colors.textMuted) : field(),
      focusedBorder: field(colors.primary, 2),
      errorBorder: field(colors.wrong),
      focusedErrorBorder: field(colors.wrong, 2),
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.l,
        vertical: AppSpacing.m,
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(colors.card),
        shape: WidgetStatePropertyAll(rounded),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: buttonSize,
        shape: rounded,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: buttonSize,
        shape: rounded,
        textStyle: buttonText,
        foregroundColor: colors.text,
        backgroundColor: colors.card,
        side: BorderSide(
          color: highContrast ? colors.textMuted : colors.divider,
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        minimumSize: const Size(AppSizes.minTap, AppSizes.minTap),
        shape: rounded,
        textStyle: text.labelLarge,
      ),
    ),
    listTileTheme: ListTileThemeData(
      shape: rounded,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      selectedColor: colors.primary,
      selectedTileColor: colors.tint(colors.primary),
      titleTextStyle: text.bodyLarge,
      subtitleTextStyle: text.bodyMedium,
    ),
    expansionTileTheme: ExpansionTileThemeData(
      shape: rounded,
      collapsedShape: rounded,
      iconColor: colors.primary,
      collapsedIconColor: colors.textMuted,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.card,
      surfaceTintColor: Colors.transparent,
      titleTextStyle: text.headlineSmall,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: colors.card,
      surfaceTintColor: Colors.transparent,
      shape: rounded,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: rounded,
    ),
    bannerTheme: MaterialBannerThemeData(
      backgroundColor: colors.tint(colors.later),
      surfaceTintColor: Colors.transparent,
      dividerColor: Colors.transparent,
    ),
    // ignore: deprecated_member_use
    progressIndicatorTheme: const ProgressIndicatorThemeData(year2023: false),
    // ignore: deprecated_member_use
    sliderTheme: const SliderThemeData(year2023: false),
  );
}

/// Card text: the serif at reading size, for the content people came to read.
extension ReadingText on TextTheme {
  TextStyle get reading => bodyLarge!.copyWith(
    fontFamily: AppFonts.serif,
    fontSize: AppSizes.readingText,
    height: AppSizes.readingLineHeight,
  );
}

/// Screens fade and drift forward; with reduce motion they simply appear.
class _GentleTransitions extends PageTransitionsBuilder {
  const _GentleTransitions();

  static const _inner = FadeForwardsPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => MediaQuery.disableAnimationsOf(context)
      ? child
      : _inner.buildTransitions(
          route,
          context,
          animation,
          secondaryAnimation,
          child,
        );
}
