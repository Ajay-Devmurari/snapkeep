import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:snapkeep/core/notifications/snooze_sheet.dart';
import 'package:snapkeep/core/theme/app_colors.dart';
import 'package:snapkeep/features/data/saved_items_storage.dart';
import 'package:snapkeep/features/home/models/saved_item.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:permission_handler/permission_handler.dart';

class SnoozeAction {
  SnoozeAction._();

  static const defaultSnooze = 'snooze_default';
  static const custom = 'snooze_custom';
  static const markDone = 'mark_done';
  static const defaultDuration = Duration(minutes: 5);

  // Button labels. Short, because Android cuts long labels.

  static const defaultSnoozeLabel = '+5 min';
  static const customLabel = 'Custom';
  static const markDoneLabel = 'Done';
}

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  /// Used to open the snooze sheet from anywhere. Set in MaterialApp.
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  /// Increments after every change made from a notification. Home screen
  /// listens to it and reloads the list.
  static final ValueNotifier<int> changes = ValueNotifier<int>(0);

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Payload waiting for the UI to be ready (app opened from a notification).
  String? _pendingCustomPayload;

  static const _channelId = 'snapkeep_reminders';
  static const _channelName = 'Reminders';
  static const _channelDescription = 'Reminders for your saved screenshots';

  /// A repeating reminder is scheduled as its next time (the normal id) plus
  /// a few more times ahead (ids made from "itemId#k"). The app refreshes them
  /// every time it opens, so the series keeps going even if the app stays
  /// closed for a while.
  static const _maxExtra = 13;

  int _extraCount(RepeatRule rule) => switch (rule) {
    RepeatRule.daily => 13, // about two weeks ahead
    RepeatRule.weekly => 7, // about two months ahead
    RepeatRule.monthly => 5, // about half a year ahead
    RepeatRule.none => 0,
  };

  /// Look of every reminder notification.
  ///
  /// Built per notification (not a constant) so that a long note can expand
  /// instead of being cut off, and so the app accent colour can be used.
  NotificationDetails _detailsFor(String title, String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        // Tints the small icon and the app name in the notification.
        color: AppColors.accent,
        ticker: title,
        // Pull the notification down to read the whole note.
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
        actions: const <AndroidNotificationAction>[
          AndroidNotificationAction(
            SnoozeAction.defaultSnooze,
            SnoozeAction.defaultSnoozeLabel,
            showsUserInterface: true,
            cancelNotification: true,
          ),
          // Not cancelled here: if the user closes the sheet, the reminder
          // stays.
          AndroidNotificationAction(
            SnoozeAction.custom,
            SnoozeAction.customLabel,
            showsUserInterface: true,
            cancelNotification: false,
          ),
          AndroidNotificationAction(
            SnoozeAction.markDone,
            SnoozeAction.markDoneLabel,
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        categoryIdentifier: 'snapkeep_reminder',
      ),
    );
  }

  AndroidFlutterLocalNotificationsPlugin? get _android => _plugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();

  IOSFlutterLocalNotificationsPlugin? get _ios => _plugin
      .resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();

  // ───────────────────────── SETUP ─────────────────────────

  Future<void> init() async {
    const android = AndroidInitializationSettings('@drawable/ic_stat_snapkeep');
    if (_ready) return;

    tzdata.initializeTimeZones();

    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'snapkeep_reminder',
          actions: <DarwinNotificationAction>[
            DarwinNotificationAction.plain(
              SnoozeAction.defaultSnooze,
              SnoozeAction.defaultSnoozeLabel,
            ),
            DarwinNotificationAction.plain(
              SnoozeAction.custom,
              SnoozeAction.customLabel,
            ),
            DarwinNotificationAction.plain(
              SnoozeAction.markDone,
              SnoozeAction.markDoneLabel,
            ),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: _onResponse,
    );

    _ready = true;
  }

  /// Call once in main() after init(). Handles the case where the app was
  /// closed and got opened by tapping a notification button.
  Future<void> checkLaunchFromNotification() async {
    await init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    final response = details?.notificationResponse;
    if (details?.didNotificationLaunchApp == true && response != null) {
      _onResponse(response);
    }
  }

  /// Call from the home screen after the first frame.
  /// Opens the custom sheet if it was waiting for the UI.
  void flushPending() {
    final payload = _pendingCustomPayload;
    if (payload == null) return;
    _pendingCustomPayload = null;
    _openCustomSheet(payload);
  }

  Future<bool> ensurePermissions() async {
    await init();

    final android = _android;

    if (android != null) {
      var enabled = await android.areNotificationsEnabled() ?? false;

      if (!enabled) {
        enabled = await android.requestNotificationsPermission() ?? false;
      }

      if (enabled) {
        final canExact = await android.canScheduleExactNotifications() ?? false;
        if (!canExact) await android.requestExactAlarmsPermission();
      }

      return enabled;
    }

    final ios = _ios;

    if (ios != null) {
      return await ios.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          ) ??
          false;
    }

    return true;
  }

  // ───────────────────────── RESPONSE HANDLING ─────────────────────────

  void _onResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null) return;

    switch (response.actionId) {
      case SnoozeAction.defaultSnooze:
        snooze(payload, DateTime.now().add(SnoozeAction.defaultDuration));
      case SnoozeAction.custom:
        _openCustomSheet(payload);
      case SnoozeAction.markDone:
        _markDone(payload);
      default:
        // Plain tap: the app just opens.
        debugPrint('SnapKeep: notification tapped, payload=$payload');
    }
  }

  void _openCustomSheet(String payload) {
    final context = navigatorKey.currentContext;

    // UI is not ready yet (cold start). Try again after the first frame.
    if (context == null) {
      _pendingCustomPayload = payload;
      return;
    }

    showSnoozeSheet(context).then((picked) {
      if (picked != null) {
        snooze(payload, picked);
      }
    });
  }

  /// "Done" from the notification. Works even when the app was closed,
  /// because it only touches storage and notifications.
  ///
  /// A repeating reminder is not finished: it moves to its next time.
  Future<void> _markDone(String payload) async {
    try {
      await init();

      final itemId = payload.split('|').first;
      final advanced = await SavedItemsStorage.instance.markDoneOrAdvance(
        itemId,
      );

      if (advanced != null) {
        // Repeating: schedule the next time (and the ones after it).
        await schedule(advanced);
      } else {
        await _plugin.cancel(id: _idForId(itemId));
        await _cancelAdvance(itemId);
      }

      changes.value++;
      debugPrint('SnapKeep: done from notification ($itemId)');
    } catch (e) {
      debugPrint('SnapKeep: mark done failed: $e');
    }
  }

  /// Moves the reminder to [until] for the item in [payload]. Updates the
  /// notification and the saved reminderDate, so the app shows the new time.
  ///
  /// For a repeating reminder only this one alert moves. The later times of
  /// the series stay as they are.
  Future<void> snooze(String payload, DateTime until) async {
    try {
      await init();

      final parts = payload.split('|');
      final itemId = parts[0];
      final title = parts.length > 1 ? parts[1] : 'SnapKeep reminder';
      final body = parts.length > 2 ? parts.sublist(2).join('|') : '';
      final id = _idForId(itemId);

      // Removes the shown notification and any pending one with this id.
      await _plugin.cancel(id: id);

      await _plugin.zonedSchedule(
        id: id,
        title: title,
        body: body,
        scheduledDate: tz.TZDateTime.from(until, tz.UTC),
        notificationDetails: _detailsFor(title, body),
        androidScheduleMode: await _scheduleMode(),
        payload: payload,
      );

      await SavedItemsStorage.instance.updateReminderDate(itemId, until);
      changes.value++;

      debugPrint('SnapKeep: snoozed "$title" until $until');
    } catch (e) {
      debugPrint('SnapKeep: snooze failed: $e');
    }
  }

  /// Snooze for an item from inside the app (the "Snooze 10 min" button on a
  /// missed item). Same flow as the notification snooze.
  Future<void> snoozeItem(SavedItem item, DateTime until) {
    return snooze(_buildPayload(item, _bodyFor(item)), until);
  }

  // ───────────────────────── SCHEDULE ─────────────────────────

  int _idForId(String value) {
    var hash = 0x811C9DC5;

    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }

    return hash & 0x7FFFFFFF;
  }

  /// Id of the k-th extra alert of a repeating reminder.
  int _occurrenceId(String itemId, int k) => _idForId('$itemId#$k');

  /// Id of the "heads up" alert before the k-th time of a reminder
  /// (k = 0 is the first time).
  int _advanceId(String itemId, int k) => _idForId('$itemId@$k');

  Future<void> _cancelAdvance(String itemId) async {
    for (var k = 0; k <= _maxExtra; k++) {
      await _plugin.cancel(id: _advanceId(itemId, k));
    }
  }

  /// "8:35 PM" style time.
  String _timeText(DateTime d) {
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final m = d.minute.toString().padLeft(2, '0');
    return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
  }

  String _headsUpBody(AdvanceAlert advance, DateTime when, String note) {
    final lead = switch (advance) {
      AdvanceAlert.hour => 'In 1 hour, at ${_timeText(when)}',
      AdvanceAlert.day => 'Tomorrow at ${_timeText(when)}',
      AdvanceAlert.none => '',
    };

    return note.isEmpty ? lead : '$lead\n$note';
  }

  /// A heads-up has no buttons, so it can never move the real reminder.
  NotificationDetails _headsUpDetailsFor(String title, String body) {
    return NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: _channelDescription,
        importance: Importance.max,
        priority: Priority.high,
        category: AndroidNotificationCategory.reminder,
        color: AppColors.accent,
        ticker: title,
        styleInformation: BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    );
  }

  Future<void> _cancelOccurrences(String itemId) async {
    for (var k = 1; k <= _maxExtra; k++) {
      await _plugin.cancel(id: _occurrenceId(itemId, k));
    }
  }

  /// The note if there is one, otherwise the category.
  String _bodyFor(SavedItem item) {
    final note = item.note.trim();
    return note.isNotEmpty ? note : '${item.category} · Tap to open';
  }

  /// Payload format: itemId|title|body
  String _buildPayload(SavedItem item, String body) {
    final safeTitle = item.title.replaceAll('|', ' ');
    final safeBody = body.replaceAll('|', ' ');
    return '${item.id}|$safeTitle|$safeBody';
  }

  Future<AndroidScheduleMode> _scheduleMode() async {
    final android = _android;
    if (android == null) return AndroidScheduleMode.exactAllowWhileIdle;

    final canExact = await android.canScheduleExactNotifications() ?? false;

    return canExact
        ? AndroidScheduleMode.exactAllowWhileIdle
        : AndroidScheduleMode.inexactAllowWhileIdle;
  }

  /// Schedules the reminder of [item]. A repeating reminder also gets its
  /// next few times. [clearOccurrences] removes the old extra times first
  /// (needed when the rule changed, for example from Daily to Never).
  /// Schedules the reminder of [item]. A repeating reminder also gets its
  /// next few times, and an item with an early alert gets a heads-up before
  /// each of them. [clearOccurrences] removes the old extra times first
  /// (needed when the rule changed, for example from Daily to Never).
  Future<void> schedule(SavedItem item, {bool clearOccurrences = true}) async {
    await init();

    if (clearOccurrences) {
      await _cancelOccurrences(item.id);
      await _cancelAdvance(item.id);
    }

    final now = DateTime.now();
    var when = item.reminderDate;

    // A repeating reminder that already passed jumps to its next time.
    if (item.repeat.repeats && when != null && !when.isAfter(now)) {
      when = item.repeat.nextAfter(item.repeatAnchor ?? when, now);
    }

    if (when == null || !when.isAfter(now)) {
      await _plugin.cancel(id: _idForId(item.id));
      return;
    }

    final body = _bodyFor(item);
    final payload = _buildPayload(item, body);
    final mode = await _scheduleMode();

    await _plugin.zonedSchedule(
      id: _idForId(item.id),
      title: item.title,
      body: body,
      scheduledDate: tz.TZDateTime.from(when, tz.UTC),
      notificationDetails: _detailsFor(item.title, body),
      androidScheduleMode: mode,
      payload: payload,
    );

    // Every time of the series, the next one first.
    final times = <DateTime>[when];

    if (item.repeat.repeats) {
      final extra = item.repeat.upcoming(
        item.repeatAnchor ?? when,
        when,
        _extraCount(item.repeat),
      );

      for (var k = 0; k < extra.length; k++) {
        await _plugin.zonedSchedule(
          id: _occurrenceId(item.id, k + 1),
          title: item.title,
          body: body,
          scheduledDate: tz.TZDateTime.from(extra[k], tz.UTC),
          notificationDetails: _detailsFor(item.title, body),
          androidScheduleMode: mode,
          payload: payload,
        );
      }

      times.addAll(extra);
    }

    // Early alert ("1 hour before", "1 day before") for each time.
    if (item.advance.enabled) {
      final note = item.note.trim();

      for (var k = 0; k < times.length; k++) {
        final alertAt = item.advance.before(times[k]);
        if (!alertAt.isAfter(now)) continue;

        final headsUpTitle = 'Coming up · ${item.title}';
        final headsUpBody = _headsUpBody(item.advance, times[k], note);

        await _plugin.zonedSchedule(
          id: _advanceId(item.id, k),
          title: headsUpTitle,
          body: headsUpBody,
          scheduledDate: tz.TZDateTime.from(alertAt, tz.UTC),
          notificationDetails: _headsUpDetailsFor(headsUpTitle, headsUpBody),
          androidScheduleMode: mode,
          payload: payload,
        );
      }
    }

    debugPrint(
      'SnapKeep: reminder scheduled for $when (${item.title}, '
      'repeat: ${item.repeat.name}, early alert: ${item.advance.name})',
    );
  }

  Future<void> cancel(SavedItem item) async {
    try {
      await init();
      await _plugin.cancel(id: _idForId(item.id));

      if (item.repeat.repeats) await _cancelOccurrences(item.id);
      await _cancelAdvance(item.id);
    } catch (e) {
      debugPrint('SnapKeep: could not cancel reminder: $e');
    }
  }

  Future<void> rescheduleAll(List<SavedItem> items) async {
    for (final item in items) {
      try {
        // Extra times are cleared only for repeating items, so a normal
        // reminder costs no extra work.
        await schedule(item, clearOccurrences: item.repeat.repeats);
      } catch (e) {
        debugPrint('SnapKeep: could not reschedule "${item.title}": $e');
      }
    }
  }

  /// True when the user has allowed notifications. Does not show any dialog.
  /// True when the user has allowed notifications. Does not show any dialog.
  Future<bool> notificationsEnabled() async {
    await init();

    final android = _android;
    if (android != null) {
      final appEnabled = await android.areNotificationsEnabled() ?? false;
      final permissionOk = await Permission.notification.isGranted;

      // The "Reminders" channel can be switched off on its own.
      var channelOk = true;
      try {
        final channels = await android.getNotificationChannels();
        final mine = (channels ?? []).where((c) => c.id == _channelId);
        if (mine.isNotEmpty) {
          channelOk = mine.first.importance != Importance.none;
        }
      } catch (_) {}

      debugPrint(
        'SnapKeep: notifications app=$appEnabled permission=$permissionOk '
        'channel=$channelOk',
      );

      return appEnabled && permissionOk && channelOk;
    }

    final ios = _ios;
    if (ios != null) {
      final options = await ios.checkPermissions();
      return options?.isEnabled ?? false;
    }

    return true;
  }
}
