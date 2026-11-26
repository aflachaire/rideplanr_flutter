import '../app/app_state.dart';
import '../models/app_models.dart';

enum TelemetryScreen {
  onboarding,
  home,
  spots,
  map,
  account,
  subscription,
  paywall,
}

/// Telemetry is intentionally a no-op, mirroring the iOS prototype where
/// Firebase-backed analytics are disabled until App Store preparation.
class TelemetryService {
  TelemetryService._();

  static final TelemetryService shared = TelemetryService._();

  bool get isConfigured => false;

  void configureIfNeeded() {}

  void trackScreen(TelemetryScreen screen) {}

  void trackTabSelection(TelemetryScreen screen) {}

  void trackOnboardingCompleted({required String entryPoint}) {}

  void trackPaywallViewed({required String source}) {}

  void trackTrialClaimed({required String source}) {}

  void trackPurchaseCompleted({required String source, String? productIdentifier}) {}

  void trackRestoreCompleted({required String source, String? productIdentifier}) {}

  void trackReminderChanged({required bool isEnabled, required Opportunity opportunity}) {}

  void updateUserContext({
    required AccessTier accessTier,
    required UserSettings settings,
    String? countryCode,
  }) {}

  void record({required Object error, required String context, Map<String, String> metadata = const {}}) {}

  void recordMessage(String message, {required String context}) {}
}
