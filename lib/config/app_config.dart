/// Build-time configuration, mirroring the Xcode Info.plist keys of the iOS app.
///
/// Values are injected with `--dart-define`, e.g.:
///   flutter run --dart-define=REVENUECAT_PUBLIC_API_KEY=appl_xxx
///
/// When a key is not provided the same prototype fallback keys as the iOS
/// prototype are used (for AeroDataBox, Transitland, Ticketmaster, PredictHQ).
class AppConfig {
  AppConfig._();

  static const String revenueCatPublicAPIKey =
      String.fromEnvironment('REVENUECAT_PUBLIC_API_KEY');
  static const String revenueCatEntitlementID = String.fromEnvironment(
    'REVENUECAT_ENTITLEMENT_ID',
    defaultValue: 'RidePlanr Pro',
  );
  static const String revenueCatOfferingID = String.fromEnvironment(
    'REVENUECAT_OFFERING_ID',
    defaultValue: 'default',
  );
  static const String revenueCatLifetimeProductID =
      String.fromEnvironment('REVENUECAT_LIFETIME_PRODUCT_ID');
  static const String revenueCatMonthlyProductID =
      String.fromEnvironment('REVENUECAT_MONTHLY_PRODUCT_ID');
  static const String revenueCatYearlyProductID =
      String.fromEnvironment('REVENUECAT_YEARLY_PRODUCT_ID');

  // API keys are provided at build time via
  // `--dart-define-from-file=config/dart_defines.json` (gitignored). No keys
  // are hardcoded in source. An empty key means that data source is disabled.
  static const String aeroDataBoxAPIKey =
      String.fromEnvironment('AERODATABOX_API_KEY');
  static const String transitlandAPIKey =
      String.fromEnvironment('TRANSITLAND_API_KEY');
  static const String ticketmasterAPIKey =
      String.fromEnvironment('TICKETMASTER_API_KEY');
  static const String predictHQAPIKey =
      String.fromEnvironment('PREDICTHQ_API_KEY');

  static bool get isRevenueCatConfigured =>
      revenueCatPublicAPIKey.trim().isNotEmpty;

  static String? sanitized(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
