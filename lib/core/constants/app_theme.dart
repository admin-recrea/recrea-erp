import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class RecreaTheme {
  static const Color turquesa = Color(0xFF38C5FD);
  static const Color rosa = Color(0xFFE25192);
  static const Color verde = Color(0xFFB2D169);
  static const Color amarillo = Color(0xFFEEB041);
  static const Color blanco = Color(0xFFFFFFFF);
  static const Color oscuro = Color(0xFF1E293B);

  static const Color fondoBase = Color(0xFFF4F8FB); 
  static const Color textoMudo = Color(0xFF64748B);
  static const Color bordeClaro = Color(0xFFE2E8F0);
  
  static const Color turquesaSuave = Color(0x1F38C5FD);
  static const Color rosaSuave = Color(0x1FE25192);
  static const Color verdeSuave = Color(0x1FB2D169);
  static const Color amarilloSuave = Color(0x1FEEB041);

  static String? get fontFamily => GoogleFonts.nunito().fontFamily;

  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: fondoBase,
      primaryColor: turquesa,
      fontFamily: fontFamily,
      
      colorScheme: const ColorScheme.light(
        primary: turquesa,
        secondary: rosa,
        tertiary: verde,
        surface: blanco,
        error: amarillo,
        onPrimary: blanco,
        onSecondary: blanco,
        onSurface: oscuro,
      ),

      // Pesos equilibrados: Textos normales limpios y negritas con cuerpo adecuado
      textTheme: TextTheme(
        displayLarge: GoogleFonts.nunito(color: oscuro, fontWeight: FontWeight.w700),
        headlineMedium: GoogleFonts.nunito(color: oscuro, fontWeight: FontWeight.w500, letterSpacing: -0.5),
        titleLarge: GoogleFonts.nunito(color: oscuro, fontWeight: FontWeight.w700),
        titleMedium: GoogleFonts.nunito(color: oscuro, fontWeight: FontWeight.w600),
        bodyLarge: GoogleFonts.nunito(color: oscuro, fontWeight: FontWeight.w500),
        bodyMedium: GoogleFonts.nunito(color: textoMudo, fontWeight: FontWeight.w500),
        labelLarge: GoogleFonts.nunito(color: oscuro, fontWeight: FontWeight.w700),
      ),
      
      appBarTheme: AppBarTheme(
        backgroundColor: blanco,
        foregroundColor: oscuro,
        elevation: 0,
        centerTitle: false,
        iconTheme: const IconThemeData(color: oscuro),
        titleTextStyle: GoogleFonts.nunito(
          color: oscuro,
          fontSize: 20,
          fontWeight: FontWeight.w700,
        ),
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        hintStyle: GoogleFonts.nunito(color: const Color(0xFF94A3B8), fontWeight: FontWeight.w500),
        labelStyle: GoogleFonts.nunito(color: textoMudo, fontWeight: FontWeight.w600),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: bordeClaro, width: 1.5),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: bordeClaro, width: 1.5),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: turquesa, width: 2.2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: rosa, width: 1.8),
        ),
      ),
      
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: turquesa,
          foregroundColor: blanco,
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.nunito(fontSize: 16, fontWeight: FontWeight.w700, letterSpacing: 0.3),
        ),
      ),
      
      cardTheme: CardThemeData(
        color: blanco,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24.0),
          side: const BorderSide(color: bordeClaro, width: 1.2),
        ),
      ),
    );
  }
}