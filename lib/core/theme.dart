import 'package:flutter/material.dart';
import 'tokens.dart';

/// Traduce AppTokens (Fase de diseño) a un ThemeData de Flutter.
/// Los componentes del catálogo no leen AppTokens directamente para
/// color de superficie/texto: leen Theme.of(context), que a su vez
/// viene de aquí. Esto es lo que exige el taller: "consumir los tokens
/// desde el tema, sin valores fijos en el código".
class AppTheme {
  static ThemeData light() {
    const colorScheme = ColorScheme.light(
      primary: AppTokens.colorPrimary,
      onPrimary: AppTokens.colorOnPrimary,
      primaryContainer: AppTokens.colorPrimaryContainer,
      onPrimaryContainer: AppTokens.colorOnPrimaryContainer,
      error: AppTokens.colorError,
      onError: AppTokens.colorOnError,
      errorContainer: AppTokens.colorErrorContainer,
      onErrorContainer: AppTokens.colorOnErrorContainer,
      surface: AppTokens.colorSurface,
      onSurface: AppTokens.colorTextPrimary,
      secondaryContainer: AppTokens.colorSuccessContainer,
      onSecondaryContainer: AppTokens.colorOnSuccessContainer,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppTokens.colorBackground,
      textTheme: const TextTheme(
        bodySmall: AppTokens.textCaption,
        bodyMedium: AppTokens.textBody,
        bodyLarge: AppTokens.textBodyLarge,
        titleLarge: AppTokens.textTitle,
        headlineSmall: AppTokens.textHeadline,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: AppTokens.spaceMD,
          vertical: AppTokens.spaceMD,
        ),
      ),
      cardTheme: CardThemeData(
        color: AppTokens.colorSurface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppTokens.radiusCard),
        ),
      ),
    );
  }
}
