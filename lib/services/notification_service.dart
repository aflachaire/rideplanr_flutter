import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../models/app_models.dart';

/// Port of the iOS `NotificationService` on top of flutter_local_notifications.
class NotificationService extends ChangeNotifier {
  static const String _reminderPrefix = 'driverintel.reminder.';
  static const String _opportunityIDKey = 'driverintel.opportunityID';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  String? pendingReminderOpportunityID;
  bool _isInitialized = false;

  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;

    tz_data.initializeTimeZones();

    const initializationSettings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
    );

    await _plugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: _handleNotificationResponse,
    );
  }

  void _handleNotificationResponse(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;

    try {
      final decoded = jsonDecode(payload) as Map<String, dynamic>;
      pendingReminderOpportunityID = decoded[_opportunityIDKey] as String?;
    } catch (_) {
      pendingReminderOpportunityID = null;
    }

    notifyListeners();
  }

  Future<bool> isAuthorizationDetermined() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      final settings = await ios.checkPermissions();
      if (settings == null) return false;
      return settings.isEnabled ||
          settings.isAlertEnabled ||
          settings.isBadgeEnabled ||
          settings.isSoundEnabled;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      return await android.areNotificationsEnabled() ?? false;
    }

    return false;
  }

  Future<void> requestAuthorizationIfNeeded() async {
    final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    if (ios != null) {
      await ios.requestPermissions(alert: true, badge: true, sound: true);
      return;
    }

    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.requestNotificationsPermission();
    }
  }

  Future<void> scheduleReminder(
    Opportunity opportunity, {
    required int leadTimeMinutes,
  }) async {
    await requestAuthorizationIfNeeded();

    final identifier = _reminderIdentifier(opportunity);
    await _plugin.cancel(identifier.hashCode);

    final triggerSeconds =
        ((opportunity.startsInMinutes - leadTimeMinutes) * 60).clamp(1, 1 << 31).toInt();
    final bodyText = _reminderSubtitle(opportunity, leadTimeMinutes);

    final scheduledDate =
        tz.TZDateTime.now(tz.local).add(Duration(seconds: triggerSeconds));

    try {
      await _plugin.zonedSchedule(
        identifier.hashCode,
        'Go now to ${opportunity.title}',
        bodyText,
        scheduledDate,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'driverintel.reminders',
            'Spot reminders',
            channelDescription: 'Reminders before a saved spot starts',
            importance: Importance.high,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(presentSound: true),
        ),
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        payload: jsonEncode({_opportunityIDKey: opportunity.id}),
      );
    } catch (_) {
      // Mirror the iOS `try?` behaviour: scheduling failures are silent.
    }
  }

  Future<void> cancelReminder(Opportunity opportunity) async {
    await _plugin.cancel(_reminderIdentifier(opportunity).hashCode);
  }

  void clearPendingReminderNavigation() {
    pendingReminderOpportunityID = null;
  }

  Future<void> scheduleDemoNotifications() async {
    await _plugin.cancelAll();

    const payloads = [
      (5, 'Priority signal', 'CDG is now the top zone to monitor over the next 25 minutes.'),
      (12, 'Premium window', 'Heavy TGV release at Gare de Lyon. Position now.'),
      (20, 'Traffic tradeoff', 'Bercy remains attractive, but avoid the Maillot corridor.'),
    ];

    for (var index = 0; index < payloads.length; index++) {
      final payload = payloads[index];

      try {
        await _plugin.zonedSchedule(
          'driverintel.demo.$index'.hashCode,
          payload.$2,
          payload.$3,
          tz.TZDateTime.now(tz.local).add(Duration(seconds: payload.$1)),
          const NotificationDetails(
            android: AndroidNotificationDetails(
              'driverintel.demo',
              'Demo notifications',
              channelDescription: 'Founder demo notifications',
              importance: Importance.high,
              priority: Priority.high,
            ),
            iOS: DarwinNotificationDetails(presentSound: true),
          ),
          uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        );
      } catch (_) {
        // Silent, like the iOS prototype.
      }
    }
  }

  String _reminderIdentifier(Opportunity opportunity) =>
      _reminderPrefix + opportunity.id;

  String _reminderSubtitle(Opportunity opportunity, int leadTimeMinutes) {
    final String timeText;
    if (opportunity.startsInMinutes > leadTimeMinutes) {
      timeText = '$leadTimeMinutes min';
    } else if (opportunity.startsInMinutes.isDriverIntelImmediateTime) {
      timeText = 'now';
    } else {
      timeText = opportunity.startsInMinutes.driverIntelTimeRemainingText
          .replaceAll('In ', '')
          .toLowerCase();
    }

    if (opportunity.categories.contains(SignalCategory.flights)) {
      return 'Flights landing in $timeText';
    }

    if (opportunity.categories.contains(SignalCategory.trains)) {
      return 'Trains arriving in $timeText';
    }

    if (opportunity.categories.contains(SignalCategory.events)) {
      return 'Event ends in $timeText';
    }

    return 'Busy area in $timeText';
  }
}
