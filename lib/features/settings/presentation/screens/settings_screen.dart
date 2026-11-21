import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/theme_controller.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        title: Text(
          'Settings',
          style: TextStyle(
            color: AppColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      body: ValueListenableBuilder<bool>(
        valueListenable: AppColors.darkMode,
        builder: (context, dark, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
            children: [
              Text(
                'APPEARANCE',
                style: TextStyle(
                  color: AppColors.secondaryText,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.text.withValues(alpha: 0.045),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SwitchListTile(
                  secondary: Icon(
                    dark
                        ? Icons.dark_mode_rounded
                        : Icons.light_mode_outlined,
                    color: AppColors.accent,
                  ),
                  title: Text(
                    'Dark mode',
                    style: TextStyle(
                      color: AppColors.text,
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    dark ? 'On' : 'Off',
                    style: TextStyle(
                      color: AppColors.secondaryText,
                      fontSize: 12.5,
                    ),
                  ),
                  value: dark,
                  activeThumbColor: AppColors.accent,
                  onChanged: (value) => ThemeController.setDark(value),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}