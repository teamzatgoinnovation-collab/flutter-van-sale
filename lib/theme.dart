import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// ZatGo brand palette — single source of truth. Reference these instead of
/// re-typing the hex values so the brand stays consistent everywhere and can
/// be re-tuned in one place.
const kBrandBlue = Color(0xFF2952E3);
const kBrandBlueLight = Color(0xFF5B7FFF);
const kScaffoldDark = Color(0xFF10131C);
const kScaffoldLight = Color(0xFFF5F6FA);

/// Semantic status colors — kept separate from the brand palette. These
/// carry meaning (paid/overdue/etc.) regardless of what the brand color is.
const kStatusSuccess = Color(0xFF16A34A);
const kStatusWarning = Color(0xFFD97706);
const kStatusError = Color(0xFFDC2626);

/// Spacing scale — 4px base, per the design system.
class AppSpacing {
  const AppSpacing._();
  static const xs = 4.0;
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 24.0;
  static const xxl = 32.0;
}

/// Corner-radius scale — per the design system.
class AppRadius {
  const AppRadius._();
  static const sm = 8.0;
  static const md = 12.0;
  static const lg = 16.0;
  static const xl = 20.0;
}

/// Premium SaaS palette: deep royal blue on white/light-gray.
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
  const seed = kBrandBlue;
  final isDark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    primary: isDark ? kBrandBlueLight : seed,
    secondary: isDark ? kBrandBlue : kBrandBlueLight,
  );

  final scaffold = isDark ? kScaffoldDark : kScaffoldLight;
  final card = isDark ? const Color(0xFF1A1F2E) : Colors.white;
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
      elevation: isDark ? 0 : 2,
      shadowColor: scheme.shadow.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      color: card,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.xl),
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
