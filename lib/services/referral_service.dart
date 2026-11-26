import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'telemetry_service.dart';

/// Captures an affiliate / referral code from an incoming deep link
/// (e.g. `rideplanr://invite?ref=CODE`, or any link carrying `?ref=` /
/// `utm_source=`), persists it, and attaches it to the RevenueCat customer as
/// subscriber attributes so it flows into RevenueCat webhooks and attribution.
///
/// This is the app-side hook for an affiliate program — RevenueCat has no
/// turnkey affiliate feature, so the referral code must be captured here and
/// forwarded as attributes; payouts/commissions are handled by your backend
/// (or a tool like Insert Affiliate) off the resulting webhook events.
class ReferralService {
  ReferralService(this._defaults);

  static const String _referralCodeKey = 'driverintel.referralCode';
  static const String _utmSourceKey = 'driverintel.utmSource';
  static const String _utmCampaignKey = 'driverintel.utmCampaign';

  final SharedPreferences _defaults;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSubscription;

  String? get referralCode => _defaults.getString(_referralCodeKey);

  /// Starts listening for deep links (cold-start + while running) and applies
  /// any already-stored code to RevenueCat.
  Future<void> initialize() async {
    // Re-attach a code captured on a previous launch (e.g. before the user
    // ever opened the paywall) so it's present on the customer for any purchase.
    await applyStoredAttributesIfNeeded();

    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        await _handleUri(initialUri);
      }
    } catch (_) {
      // No initial link / platform without deep-link support — ignore.
    }

    _linkSubscription = _appLinks.uriLinkStream.listen(
      (uri) {
        _handleUri(uri);
      },
      onError: (_) {},
    );
  }

  void dispose() {
    _linkSubscription?.cancel();
  }

  Future<void> _handleUri(Uri uri) async {
    // Query keys are matched case-insensitively.
    final params = <String, String>{};
    uri.queryParameters.forEach((key, value) {
      params[key.toLowerCase()] = value;
    });

    final code = _firstNonEmpty([params['ref'], params['referral'], params['code']]);
    final utmSource = _nonEmpty(params['utm_source']);
    final utmCampaign = _nonEmpty(params['utm_campaign']);

    if (code == null && utmSource == null && utmCampaign == null) {
      return;
    }

    if (code != null) await _defaults.setString(_referralCodeKey, code);
    if (utmSource != null) await _defaults.setString(_utmSourceKey, utmSource);
    if (utmCampaign != null) {
      await _defaults.setString(_utmCampaignKey, utmCampaign);
    }

    TelemetryService.shared
        .recordMessage('referral_link_captured', context: 'referral');

    await applyStoredAttributesIfNeeded();
  }

  /// Pushes the stored referral/UTM values onto the RevenueCat customer.
  /// No-op when RevenueCat isn't configured or nothing has been captured.
  Future<void> applyStoredAttributesIfNeeded() async {
    if (!AppConfig.isRevenueCatConfigured) return;

    final attributes = <String, String>{};
    final code = _nonEmpty(_defaults.getString(_referralCodeKey));
    final utmSource = _nonEmpty(_defaults.getString(_utmSourceKey));
    final utmCampaign = _nonEmpty(_defaults.getString(_utmCampaignKey));

    if (code != null) attributes['referrer_code'] = code;
    if (utmSource != null) attributes['utm_source'] = utmSource;
    if (utmCampaign != null) attributes['utm_campaign'] = utmCampaign;

    if (attributes.isEmpty) return;

    try {
      await rc.Purchases.setAttributes(attributes);
    } catch (error) {
      TelemetryService.shared.record(error: error, context: 'referral_attributes');
    }
  }

  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final cleaned = _nonEmpty(value);
      if (cleaned != null) return cleaned;
    }
    return null;
  }

  String? _nonEmpty(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }
}
