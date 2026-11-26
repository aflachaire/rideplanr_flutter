import 'package:flutter/foundation.dart';

import '../models/app_models.dart';
import '../services/notification_service.dart';

class SettingsViewModel extends ChangeNotifier {
  SettingsViewModel({
    required this.settings,
    required NotificationService notificationService,
  }) : _notificationService = notificationService;

  UserSettings settings;
  String demoStatusMessage =
      'Schedule local notifications for the founder demo.';

  final NotificationService _notificationService;

  Future<void> triggerDemoNotifications() async {
    await _notificationService.scheduleDemoNotifications();
    demoStatusMessage =
        '3 demo notifications have been scheduled over the next 20 seconds.';
    notifyListeners();
  }
}
