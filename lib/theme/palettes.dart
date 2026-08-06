import 'package:flutter/material.dart';

class ThemePalette {
  final String id;
  final String zhName;
  final String enName;
  final ColorScheme light;
  final ColorScheme dark;

  const ThemePalette({
    required this.id,
    required this.zhName,
    required this.enName,
    required this.light,
    required this.dark,
  });

  String get displayNameZh => zhName;
  String get displayNameEn => enName;
}

class ThemePalettes {
  static const String defaultId = 'default';

  static const ThemePalette defaultPalette = ThemePalette(
    id: defaultId,
    zhName: '默认',
    enName: 'Default',
    light: ColorScheme(
      brightness: Brightness.light,
      primary: Color(0xFF4D5C92),
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFDCE1FF),
      onPrimaryContainer: Color(0xFF03174B),
      secondary: Color(0xFF595D72),
      onSecondary: Color(0xFFFFFFFF),
      secondaryContainer: Color(0xFFDEE1F9),
      onSecondaryContainer: Color(0xFF161B2C),
      tertiary: Color(0xFF75546F),
      onTertiary: Color(0xFFFFFFFF),
      tertiaryContainer: Color(0xFFFFD7F6),
      onTertiaryContainer: Color(0xFF2C122A),
      error: Color(0xFFBB0947),
      onError: Color(0xFFFFFFFF),
      errorContainer: Color(0xFFFDDADE),
      onErrorContainer: Color(0xFF400013),
      surface: Color(0xFFF7F7F7),
      onSurface: Color(0xFF202020),
      onSurfaceVariant: Color(0xFF646464),
      outline: Color(0x1A000000),
      outlineVariant: Color(0xFF000000),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFF121213),
      onInverseSurface: Color(0xFFF9F9F9),
      inversePrimary: Color(0xFF4D5C92),
      surfaceTint: Color(0xFF4D5C92),
    ),
    dark: ColorScheme(
      brightness: Brightness.dark,
      primary: Color(0xFFB6C4FF),
      onPrimary: Color(0xFF1D2D61),
      primaryContainer: Color(0xFF354479),
      onPrimaryContainer: Color(0xFFDCE1FF),
      secondary: Color(0xFFC2C5DD),
      onSecondary: Color(0xFF2B3042),
      secondaryContainer: Color(0xFF424659),
      onSecondaryContainer: Color(0xFFDEE1F9),
      tertiary: Color(0xFFE3BADA),
      onTertiary: Color(0xFF432740),
      tertiaryContainer: Color(0xFF5B3D57),
      onTertiaryContainer: Color(0xFFFFD7F6),
      error: Color(0xFFFCB4BD),
      onError: Color(0xFF670023),
      errorContainer: Color(0xFF910034),
      onErrorContainer: Color(0xFFFCB4BD),
      surface: Color(0xFF121213),
      onSurface: Color(0xFFF9F9F9),
      onSurfaceVariant: Color(0xFFCECECE),
      outline: Color(0x1A000000),
      outlineVariant: Color(0xFFFFFFFF),
      shadow: Color(0xFF000000),
      scrim: Color(0xFF000000),
      inverseSurface: Color(0xFFF7F7F7),
      onInverseSurface: Color(0xFF202020),
      inversePrimary: Color(0xFFB6C4FF),
      surfaceTint: Color(0xFFB6C4FF),
    ),
  );

  static ThemePalette byId(String id) => defaultPalette;
}
