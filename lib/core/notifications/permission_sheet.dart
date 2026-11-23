import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/app_colors.dart';
import 'notification_service.dart';

import 'package:permission_handler/permission_handler.dart';

const _explainedKey = 'permission_explained';

enum ReminderPermission { granted, denied, skipped }

/// Checks notification permission before a reminder is scheduled.
///
/// - Already allowed: returns [ReminderPermission.granted].
/// - First time: shows the explanation sheet, then the system dialog if the
///   user agrees. "Not now" returns [ReminderPermission.skipped].
/// - Sheet already shown before: goes straight to the system dialog.
Future<ReminderPermission> ensureReminderPermission(
  BuildContext context,
) async {
  final service = NotificationService.instance;

  if (await service.notificationsEnabled()) {
    return ReminderPermission.granted;
  }

  final prefs = await SharedPreferences.getInstance();
  final explained = prefs.getBool(_explainedKey) ?? false;

  if (!explained) {
    if (!context.mounted) return ReminderPermission.skipped;

    final allow = await _showPermissionSheet(context);
    await prefs.setBool(_explainedKey, true);

    if (allow != true) return ReminderPermission.skipped;
  }

  final granted = await service.ensurePermissions();
  return granted ? ReminderPermission.granted : ReminderPermission.denied;
}

bool _settingsDialogShown = false;

/// Tells the user notifications are off and offers to open the app settings.
/// Shown once per app session, unless [force] is true (user tapped a button).
Future<void> showNotificationSettingsDialog(
  BuildContext context, {
  bool force = false,
}) async {
  if (_settingsDialogShown && !force) return;
  if (!context.mounted) return;

  _settingsDialogShown = true;

  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text(
        'Notifications are off',
        style: TextStyle(
          color: AppColors.text,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
      content: Text(
        'Your reminder is saved, but SnapKeep cannot alert you until you '
        'turn notifications on in Settings.',
        style: TextStyle(
          color: AppColors.secondaryText,
          fontSize: 14,
          height: 1.4,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: Text(
            'Not now',
            style: TextStyle(color: AppColors.secondaryText),
          ),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(dialogContext);
            openAppSettings();
          },
          child: Text(
            'Open Settings',
            style: TextStyle(color: AppColors.accent),
          ),
        ),
      ],
    ),
  );
}

/// Explanation sheet. Returns true for "Allow", false or null otherwise.
Future<bool?> _showPermissionSheet(BuildContext context) {
  return showModalBottomSheet<bool>(
    context: context,
    // The sheet takes the height it needs instead of 9/16 of the screen.
    isScrollControlled: true,
    // Keeps the sheet below the status bar.
    useSafeArea: true,
    backgroundColor: AppColors.surface,
    // Not too wide on tablets and landscape.
    constraints: const BoxConstraints(maxWidth: 600),
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => SafeArea(
      // Scrolls on small screens or with a large system font,
      // so the content can never overflow.
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.softAccent,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: AppColors.accent.withValues(alpha: 0.25),
                  width: 1,
                ),
              ),
              child: Icon(
                Icons.notifications_active_rounded,
                color: AppColors.accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Allow reminders?',
              style: TextStyle(
                color: AppColors.text,
                fontSize: 19,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Two quick permissions so reminders work properly.',
              style: TextStyle(
                color: AppColors.secondaryText,
                fontSize: 13.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 18),
            _point(
              Icons.notifications_none_rounded,
              'Notifications: get an alert at your reminder time.',
            ),
            const SizedBox(height: 10),
            _point(
              Icons.alarm_rounded,
              'Exact alarm: your reminder rings at the exact minute, never late.',
            ),
            const SizedBox(height: 10),
            _point(
              Icons.lock_outline_rounded,
              'Your screenshots and reminders stay only on your phone.',
            ),
            const SizedBox(height: 24),

            // Primary button: full width
            SizedBox(
              width: double.infinity,
              height: 52,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(sheetContext, true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.accent,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: const Text(
                  'Allow reminders',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
            const SizedBox(height: 6),

            // Secondary button: full width, centered text
            SizedBox(
              width: double.infinity,
              height: 46,
              child: TextButton(
                onPressed: () => Navigator.pop(sheetContext, false),
                style: TextButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  'Not now',
                  style: TextStyle(
                    color: AppColors.secondaryText,
                    fontSize: 14.5,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

Widget _point(IconData icon, String text) {
  return Row(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, size: 18, color: AppColors.accent),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          text,
          style: TextStyle(color: AppColors.text, fontSize: 13.5, height: 1.4),
        ),
      ),
    ],
  );
}
