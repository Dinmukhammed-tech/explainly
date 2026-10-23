import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// The colours of the prototype. Every screen takes its colours from here.
class C {
  static const bg = Color(0xFF12151C);
  static const card = Color(0xFF1E222D);
  static const line = Color(0xFF2B303D);
  static const text = Color(0xFFF2F0EA);
  static const muted = Color(0xFF9AA1B0);
  static const accent = Color(0xFFF26B3A);
  static const red = Color(0xFFEF7B72);
  static const amber = Color(0xFFE0A35B);
  static const green = Color(0xFF52C99B);
  static const paper = Color(0xFFEDEEF3);
}

/// The topic map colours: red = study again, green = you can explain it.
Color statusColor(String status) => switch (status) {
      'weak' => C.red,
      'ok' => C.amber,
      'strong' => C.green,
      _ => C.muted,
    };

TextStyle mono({double size = 13, Color color = C.muted, FontWeight weight = FontWeight.w500}) =>
    GoogleFonts.jetBrainsMono(fontSize: size, color: color, fontWeight: weight);

/// Small grey heading in capitals, like "YOUR SUBJECTS".
TextStyle label() => GoogleFonts.bricolageGrotesque(
    fontSize: 12, color: C.muted, fontWeight: FontWeight.w700, letterSpacing: 2);

ThemeData appTheme() {
  final base = ThemeData(
    brightness: Brightness.dark,
    useMaterial3: true,
    fontFamily: GoogleFonts.bricolageGrotesque().fontFamily,
  );
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: base.colorScheme.copyWith(primary: C.accent, surface: C.card, onSurface: C.text),
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    dialogTheme: const DialogThemeData(backgroundColor: C.card),
    bottomSheetTheme: const BottomSheetThemeData(backgroundColor: C.card),
    snackBarTheme: const SnackBarThemeData(
        backgroundColor: C.paper, contentTextStyle: TextStyle(color: C.bg)),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.bg,
      hintStyle: const TextStyle(color: C.muted),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: C.line)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: C.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size.fromHeight(52),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: C.text,
        minimumSize: const Size.fromHeight(52),
        side: const BorderSide(color: C.line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
      ),
    ),
  );
}
