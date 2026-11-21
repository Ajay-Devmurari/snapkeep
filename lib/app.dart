import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/notifications/notification_service.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'core/theme/theme_controller.dart';
import 'features/home/presentation/screens/home_screen.dart';
import 'features/onboarding/presentation/screens/onboarding_screen.dart';

class SnapKeepApp extends StatelessWidget {
  const SnapKeepApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppColors.darkMode,
      builder: (context, dark, _) {
        return MaterialApp(
          navigatorKey: NotificationService.navigatorKey,
          title: 'SnapKeep',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: dark ? ThemeMode.dark : ThemeMode.light,
          // Wraps the whole app so the wave can take a screenshot of it.
          builder: (context, child) => RepaintBoundary(
            key: ThemeController.appBoundaryKey,
            child: child!,
          ),
          home: const AppStartScreen(),
        );
      },
    );
  }
}

class AppStartScreen extends StatelessWidget {
  const AppStartScreen({super.key});

  Future<bool> _isFirstTime() async {
    final prefs = await SharedPreferences.getInstance();

    return prefs.getBool('isFirstTime') ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: _isFirstTime(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }

        if (snapshot.hasError) {
          return const OnboardingScreen();
        }

        final isFirstTime = snapshot.data ?? true;

        if (isFirstTime) {
          return const OnboardingScreen();
        }

        return const HomeScreen();
      },
    );
  }
}