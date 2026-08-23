import 'package:flutter/material.dart';

/// ============================================================
/// NIVEL PRIMITIVO — valores crudos, sin significado de uso.
/// Nadie fuera de este archivo debería referenciar estos directamente;
/// las pantallas y componentes consumen los tokens SEMÁNTICOS de abajo.
/// ============================================================
class _Primitive {
  // Colores
  static const purple900 = Color(0xFF4527A0);
  static const purple700 = Color(0xFF5E35B1);
  static const purple100 = Color(0xFFEDE7F6);
  static const white = Color(0xFFFFFFFF);
  static const black = Color(0xFF1A1A1A);
  static const gray50 = Color(0xFFFAFAFA);
  static const gray200 = Color(0xFFE0E0E0);
  static const gray600 = Color(0xFF757575);
  static const red600 = Color(0xFFD32F2F);
  static const red800 = Color(0xFFB71C1C); // texto sobre errorContainer (AA)
  static const red50 = Color(0xFFFFEBEE);
  static const green800 = Color(0xFF2E7D32);
  static const green50 = Color(0xFFE8F5E9);

  // Espaciado (escala 4pt)
  static const space1 = 4.0;
  static const space2 = 8.0;
  // ignore: unused_field
  static const space3 = 12.0; // reservado en la escala; sin token semántico aún
  static const space4 = 16.0;
  static const space5 = 24.0;
  static const space6 = 32.0;
  static const space8 = 48.0;

  // Radios
  // ignore: unused_field
  static const radius1 = 4.0; // reservado en la escala; sin token semántico aún
  static const radius2 = 8.0;
  // ignore: unused_field
  static const radius3 = 16.0; // reservado en la escala; sin token semántico aún
  static const radiusPill = 999.0;

  // Tipografía
  static const fontCaption = 12.0;
  static const fontBody = 14.0;
  static const fontBodyLarge = 16.0;
  static const fontTitle = 20.0;
  static const fontHeadline = 24.0;
}

/// ============================================================
/// NIVEL SEMÁNTICO — lo que consumen los componentes y pantallas.
/// Cambiar el look and feel de toda la app implica editar solo esta
/// clase; ningún componente ni pantalla debe usar Color(0x...) o un
/// número de spacing fijo directamente.
/// ============================================================
class AppTokens {
  // --- Color: superficie y fondo ---
  static const colorBackground = _Primitive.gray50;
  static const colorSurface = _Primitive.white;
  static const colorBorder = _Primitive.gray200;

  // --- Color: texto ---
  static const colorTextPrimary = _Primitive.black; // 16.7:1 sobre surface
  static const colorTextSecondary = _Primitive.gray600; // 4.6:1 sobre surface

  // --- Color: marca / acción primaria ---
  static const colorPrimary = _Primitive.purple700; // 8.0:1 con onPrimary
  static const colorOnPrimary = _Primitive.white;
  static const colorPrimaryContainer = _Primitive.purple100;
  static const colorOnPrimaryContainer = _Primitive.purple900; // 8.5:1

  // --- Color: error ---
  static const colorError = _Primitive.red600;
  static const colorOnError = _Primitive.white; // 5.0:1
  static const colorErrorContainer = _Primitive.red50;
  static const colorOnErrorContainer = _Primitive.red800; // 5.75:1 (corregido)

  // --- Color: éxito ---
  static const colorSuccessContainer = _Primitive.green50;
  static const colorOnSuccessContainer = _Primitive.green800; // 4.56:1

  // --- Espaciado semántico ---
  static const spaceXS = _Primitive.space1;
  static const spaceSM = _Primitive.space2;
  static const spaceMD = _Primitive.space4;
  static const spaceLG = _Primitive.space5;
  static const spaceXL = _Primitive.space6;
  static const spaceXXL = _Primitive.space8;

  // --- Radio semántico ---
  static const radiusCard = _Primitive.radius2;
  static const radiusButton = _Primitive.radius2;
  static const radiusChip = _Primitive.radiusPill;

  // --- Tipografía semántica ---
  static const textCaption = TextStyle(
    fontSize: _Primitive.fontCaption,
    color: colorTextSecondary,
  );
  static const textBody = TextStyle(
    fontSize: _Primitive.fontBody,
    color: colorTextPrimary,
  );
  static const textBodyLarge = TextStyle(
    fontSize: _Primitive.fontBodyLarge,
    color: colorTextPrimary,
  );
  static const textTitle = TextStyle(
    fontSize: _Primitive.fontTitle,
    fontWeight: FontWeight.w600,
    color: colorTextPrimary,
  );
  static const textHeadline = TextStyle(
    fontSize: _Primitive.fontHeadline,
    fontWeight: FontWeight.w700,
    color: colorTextPrimary,
  );

  // --- Accesibilidad ---
  /// Área táctil mínima recomendada por Material/WCAG (48x48dp).
  static const minTouchTarget = 48.0;
}
