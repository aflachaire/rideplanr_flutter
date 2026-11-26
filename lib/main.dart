import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app/app_state.dart';
import 'design/app_theme.dart';
import 'services/location_service.dart';
import 'services/mock_data_service.dart';
import 'services/notification_service.dart';
import 'services/referral_service.dart';
import 'services/subscription_service.dart';
import 'services/weather_service.dart';
import 'views/root/root_tab_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final preferences = await SharedPreferences.getInstance();
  final appState = AppState(preferences);

  final notificationService = NotificationService();
  await notificationService.initialize();

  await SubscriptionService.configureSDKIfNeeded();

  // Capture affiliate / referral deep links and attach the code to the
  // RevenueCat customer (must run after RevenueCat is configured).
  final referralService = ReferralService(preferences);
  await referralService.initialize();

  runApp(
    DriverIntelApp(
      appState: appState,
      notificationService: notificationService,
    ),
  );
}

class DriverIntelApp extends StatefulWidget {
  const DriverIntelApp({
    super.key,
    required this.appState,
    required this.notificationService,
  });

  final AppState appState;
  final NotificationService notificationService;

  @override
  State<DriverIntelApp> createState() => _DriverIntelAppState();
}

class _DriverIntelAppState extends State<DriverIntelApp> {
  final MockDataService _mockDataService = MockDataService();
  final WeatherService _weatherService = WeatherService();
  late final LocationService _locationService = LocationService();
  bool _hasPromptedForNotifications = false;

  @override
  void initState() {
    super.initState();
    widget.appState.addListener(_onAppStateChanged);
  }

  @override
  void dispose() {
    widget.appState.removeListener(_onAppStateChanged);
    super.dispose();
  }

  void _onAppStateChanged() => setState(() {});

  Future<void> _promptForNotificationsIfNeeded(BuildContext context) async {
    if (_hasPromptedForNotifications) return;
    _hasPromptedForNotifications = true;

    await _locationService.requestAuthorizationIfNeeded();

    // Request notification permission straight from the OS. The iOS system
    // prompt only appears when authorization is still undetermined, so no
    // custom in-app pre-permission dialog is shown.
    await widget.notificationService.requestAuthorizationIfNeeded();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'RidePlanr',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.themeData(Brightness.light),
      darkTheme: AppTheme.themeData(Brightness.dark),
      themeMode: widget.appState.settings.appearanceMode.themeMode,
      home: Builder(
        builder: (context) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _promptForNotificationsIfNeeded(context);
          });

          return RootTabView(
            appState: widget.appState,
            mockDataService: _mockDataService,
            notificationService: widget.notificationService,
            weatherService: _weatherService,
            locationService: _locationService,
          );
        },
      ),
    );
  }
}
