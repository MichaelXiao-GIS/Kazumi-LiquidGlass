import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

/// iOS keeps content quiet and reserves the glass layer for navigation.
ThemeData iosAppTheme(ThemeData base) {
  final dark = base.brightness == Brightness.dark;
  final colors = base.colorScheme.copyWith(
    surface: dark ? const Color(0xff000000) : const Color(0xfff2f2f7),
    surfaceContainerLowest: dark ? const Color(0xff000000) : Colors.white,
    surfaceContainerLow: dark ? const Color(0xff1c1c1e) : Colors.white,
    surfaceContainer: dark ? const Color(0xff1c1c1e) : const Color(0xffeaeaef),
    surfaceContainerHigh: dark
        ? const Color(0xff2c2c2e)
        : const Color(0xffe5e5ea),
    onSurface: dark ? const Color(0xfff5f5f7) : const Color(0xff1c1c1e),
    onSurfaceVariant: dark ? const Color(0xffaeaeb2) : const Color(0xff636366),
    outlineVariant: dark ? const Color(0xff38383a) : const Color(0xffd1d1d6),
  );
  return base.copyWith(
    platform: TargetPlatform.iOS,
    colorScheme: colors,
    scaffoldBackgroundColor: colors.surface,
    splashFactory: NoSplash.splashFactory,
    textTheme: base.textTheme.apply(fontFamily: 'CupertinoSystemText'),
    primaryTextTheme: base.primaryTextTheme.apply(
      fontFamily: 'CupertinoSystemText',
    ),
    cupertinoOverrideTheme: CupertinoThemeData(
      brightness: base.brightness,
      primaryColor: colors.primary,
      scaffoldBackgroundColor: colors.surface,
    ),
    pageTransitionsTheme: PageTransitionsTheme(
      builders: {
        ...base.pageTransitionsTheme.builders,
        TargetPlatform.iOS: const CupertinoPageTransitionsBuilder(),
      },
    ),
    appBarTheme: AppBarThemeData(
      systemOverlayStyle: SystemUiOverlayStyle(
        statusBarBrightness: base.brightness,
        statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      ),
      backgroundColor: colors.surface,
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: true,
      foregroundColor: colors.onSurface,
      titleTextStyle: TextStyle(
        fontFamily: 'CupertinoSystemText',
        fontSize: 17,
        fontWeight: FontWeight.w600,
        color: colors.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colors.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dividerTheme: DividerThemeData(color: colors.outlineVariant, thickness: .5),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(44, 48),
        shape: const StadiumBorder(),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(44, 44),
        shape: const StadiumBorder(),
      ),
    ),
    inputDecorationTheme: InputDecorationThemeData(
      filled: true,
      fillColor: colors.surfaceContainerHigh,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: BorderSide.none,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: const CircleBorder(),
      elevation: 0,
      backgroundColor: colors.surfaceContainerLow,
      foregroundColor: colors.primary,
    ),
  );
}

ThemeData oledDarkTheme(ThemeData defaultDarkTheme) {
  return defaultDarkTheme.copyWith(
    scaffoldBackgroundColor: Colors.black,
    colorScheme: defaultDarkTheme.colorScheme.copyWith(
      onPrimary: Colors.black,
      onSecondary: Colors.black,
      surface: Colors.black,
      onSurface: Colors.white,
    ),
  );
}
