import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'core/constants/app_strings.dart';
import 'features/home/presentation/screens/home_screen.dart';

/// The root widget of the entire application.
///
/// WHY A SEPARATE app.dart (instead of putting MaterialApp in main.dart):
/// `main.dart` should do exactly ONE thing: bootstrap the app. Keeping the
/// actual widget tree in its own file means:
///   - main.dart stays tiny and easy to scan at a glance.
///   - Later, if we add setup code that must run BEFORE `runApp` (e.g.
///     initializing a local database, reading saved settings), it won't
///     get buried inside a large widget class.
class EBookReaderApp extends StatelessWidget {
  const EBookReaderApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: AppStrings.appName,
      // Hides the little red "DEBUG" banner in the top-right corner —
      // purely cosmetic, but makes screenshots/demos look professional.
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      home: const HomeScreen(),
    );
  }
}
