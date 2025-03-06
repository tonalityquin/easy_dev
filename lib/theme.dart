import 'package:flutter/material.dart';

// 앱 전체 테마 설정
final ThemeData appTheme = ThemeData(
  primarySwatch: Colors.blue,
  scaffoldBackgroundColor: Colors.white,
  appBarTheme: const AppBarTheme(
    backgroundColor: Colors.blue,
    foregroundColor: Colors.white,
    elevation: 0,
  ),
  textTheme: const TextTheme(
    bodyLarge: TextStyle(fontSize: 18.0, color: Colors.black),
    bodyMedium: TextStyle(fontSize: 16.0, color: Colors.black),
  ),
);
