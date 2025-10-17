import 'package:flutter/material.dart';
import 'screens/login_page.dart';
import 'utils/theme.dart';

void main() {
  runApp(const AttendanceApp());
}

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Student Attendance App',
      theme: AppTheme.lightTheme,
      home: const LoginPage(),
      debugShowCheckedModeBanner: false,
    );
  }
}