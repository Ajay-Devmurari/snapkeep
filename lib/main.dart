import 'package:flutter/material.dart';

import 'app.dart';
import 'core/categories/category_store.dart';
import 'core/notifications/notification_service.dart';
import 'core/theme/theme_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await ThemeController.load();
  await CategoryStore.load();
  await NotificationService.instance.init();
  await NotificationService.instance.checkLaunchFromNotification();

  runApp(const SnapKeepApp());
}