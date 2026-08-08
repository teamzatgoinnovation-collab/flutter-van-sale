import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ZatGo brand palette — single source of truth. Reference these instead of
/// re-typing the hex values so the brand stays consistent everywhere and can
/// be re-tuned in one place.
const kBrandTeal = Color(0xFF0F4C5C);
const kBrandTealLight = Color(0xFF2A9D8F);
const kBrandOrange = Color(0xFFE36414);
const kScaffoldDark = Color(0xFF0C1618);
const kScaffoldLight = Color(0xFFF3F6F5);

/// Field-sales palette: deep teal road / warm sand accents.
/// Themes are cached — GoogleFonts must not rebuild on every [MaterialApp] build.
ThemeData? _lightTheme;
ThemeData? _darkTheme;

ThemeData vanSaleLightTheme() =>
    _lightTheme ??= buildVanSaleTheme(brightness: Brightness.light);

ThemeData vanSaleDarkTheme() =>
    _darkTheme ??= buildVanSaleTheme(brightness: Brightness.dark);

/// Warm the Poppins cache before first paint (avoids main-thread jank).
Future<void> preloadVanSaleFonts() async {
  try {
    await GoogleFonts.pendingFonts([
      GoogleFonts.poppins(),
      GoogleFonts.poppins(fontWeight: FontWeight.w500),
      GoogleFonts.poppins(fontWeight: FontWeight.w700),
    ]);
  } catch (_) {
    // Offline / fetch failure — ThemeData falls back to platform fonts.
  }
}

ThemeData buildVanSaleTheme({Brightness brightness = Brightness.light}) {
  const seed = kBrandTeal;
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: isDark ? kBrandTealLight : seed,
    secondary: kBrandOrange,
  );

  final scaffold = isDark ? kScaffoldDark : kScaffoldLight;
  final card = isDark ? const Color(0xFF152428) : Colors.white;
  final textTheme = GoogleFonts.poppinsTextTheme(
    isDark ? ThemeData.dark().textTheme : ThemeData.light().textTheme,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scaffold,
    textTheme: textTheme,
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        color: scheme.onSurface,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: isDark ? 0 : 3,
      shadowColor: scheme.primary.withValues(alpha: 0.16),
      surfaceTintColor: Colors.transparent,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isDark
            ? BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.3))
            : BorderSide.none,
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: card,
      indicatorColor: seed.withValues(alpha: isDark ? 0.28 : 0.12),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        );
      }),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: card,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: scheme.primary, width: 1.5),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    listTileTheme: ListTileThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: card,
      modalBackgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
    ),
  );
}
