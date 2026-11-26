import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';

import '../../config/app_config.dart';
import '../../services/subscription_service.dart';
import '../../services/telemetry_service.dart';

/// Presents the paywall using RevenueCat's own native paywall
/// ([RevenueCatUI.presentPaywall]) for the configured current offering — no
/// custom in-app paywall screen.
///
/// Kept as a static presenter with the previous signature so every trigger
/// (the post-onboarding auto-present in [RootTabView] and the "Start free
/// trial" banners on Home/Spots/Map/Account) routes through the same native
/// popup. When RevenueCat isn't configured (a dev build with no key), it falls
/// back to the local trial grant so the flow stays testable.
class ProTrialPaywallView {
  const ProTrialPaywallView._();

  static Future<void> present(
    BuildContext context, {
    required String sourceContext,
    required SubscriptionOffering offering,
    required VoidCallback onClaimTrial,
    required void Function(rc.CustomerInfo) onCustomerInfoUpdated,
  }) async {
    TelemetryService.shared.trackPaywallViewed(source: sourceContext);

    if (!AppConfig.isRevenueCatConfigured) {
      // No RevenueCat key in this build — grant the local trial so dev/testing
      // without a key still works.
      onClaimTrial();
      return;
    }

    try {
      await RevenueCatUI.presentPaywall(displayCloseButton: true);
      // Sync entitlement state after the paywall closes so a completed
      // purchase (or started trial) unlocks the app.
      final customerInfo = await rc.Purchases.getCustomerInfo();
      onCustomerInfoUpdated(customerInfo);
    } catch (error) {
      TelemetryService.shared.record(
        error: error,
        context: 'revenuecat_present_paywall',
        metadata: {'source': sourceContext},
      );
    }
  }
}
