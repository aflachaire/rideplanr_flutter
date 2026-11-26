import 'package:flutter/foundation.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../app/app_state.dart';
import '../config/app_config.dart';
import 'telemetry_service.dart';

enum IntegrationMode { localPreview, revenueCat }

enum PackageKind { yearly, monthly }

class SubscriptionPackage {
  const SubscriptionPackage({
    required this.kind,
    required this.title,
    required this.detail,
    required this.priceText,
    required this.badgeText,
    required this.productIdentifier,
    required this.introductoryOfferText,
  });

  final PackageKind kind;
  final String title;
  final String detail;
  final String priceText;
  final String? badgeText;
  final String? productIdentifier;
  final String? introductoryOfferText;

  String get id => kind.name;
}

class SubscriptionOffering {
  const SubscriptionOffering({
    required this.identifier,
    required this.entitlementIdentifier,
    required this.packages,
    required this.trialCTA,
    required this.cancellationCopy,
  });

  final String identifier;
  final String entitlementIdentifier;
  final List<SubscriptionPackage> packages;
  final String trialCTA;
  final String cancellationCopy;

  SubscriptionPackage? get monthlyPackage {
    for (final package in packages) {
      if (package.kind == PackageKind.monthly) return package;
    }
    return null;
  }

  SubscriptionPackage? get yearlyPackage {
    for (final package in packages) {
      if (package.kind == PackageKind.yearly) return package;
    }
    return null;
  }

  String get pricingSummary {
    final monthly = monthlyPackage;
    final yearly = yearlyPackage;

    if (monthly != null && yearly != null) {
      final badgeText = yearly.badgeText;
      if (badgeText != null && badgeText.isNotEmpty) {
        return 'Then ${monthly.priceText} or ${yearly.priceText} (${badgeText.toLowerCase()})';
      }

      return 'Then ${monthly.priceText} or ${yearly.priceText}';
    }

    return packages.map((p) => p.priceText).join(' • ');
  }
}

class CustomerState {
  const CustomerState({
    required this.accessTier,
    required this.integrationMode,
    required this.entitlementIdentifier,
    required this.offeringIdentifier,
    required this.activeProductIdentifier,
    required this.managementURL,
  });

  final AccessTier accessTier;
  final IntegrationMode integrationMode;
  final String entitlementIdentifier;
  final String offeringIdentifier;
  final String? activeProductIdentifier;
  final Uri? managementURL;

  bool get hasProAccess => accessTier.hasProAccess;

  bool get isRevenueCatReady => integrationMode == IntegrationMode.revenueCat;
}

class SubscriptionConfiguration {
  const SubscriptionConfiguration({
    required this.publicAPIKey,
    required this.entitlementIdentifier,
    required this.offeringIdentifier,
    required this.lifetimeProductIdentifier,
    required this.monthlyProductIdentifier,
    required this.yearlyProductIdentifier,
  });

  final String? publicAPIKey;
  final String entitlementIdentifier;
  final String offeringIdentifier;
  final String? lifetimeProductIdentifier;
  final String? monthlyProductIdentifier;
  final String? yearlyProductIdentifier;

  bool get isRevenueCatReady => (publicAPIKey ?? '').isNotEmpty;

  factory SubscriptionConfiguration.loadFromEnvironment() {
    return SubscriptionConfiguration(
      publicAPIKey: AppConfig.sanitized(AppConfig.revenueCatPublicAPIKey),
      entitlementIdentifier:
          AppConfig.sanitized(AppConfig.revenueCatEntitlementID) ??
              'RidePlanr Pro',
      offeringIdentifier:
          AppConfig.sanitized(AppConfig.revenueCatOfferingID) ?? 'default',
      lifetimeProductIdentifier:
          AppConfig.sanitized(AppConfig.revenueCatLifetimeProductID),
      monthlyProductIdentifier:
          AppConfig.sanitized(AppConfig.revenueCatMonthlyProductID),
      yearlyProductIdentifier:
          AppConfig.sanitized(AppConfig.revenueCatYearlyProductID),
    );
  }
}

/// Port of the iOS `SubscriptionService` on top of purchases_flutter.
class SubscriptionService extends ChangeNotifier {
  SubscriptionService({required AccessTier initialAccessTier})
      : configuration = SubscriptionConfiguration.loadFromEnvironment() {
    currentOffering = _makeFallbackOffering(configuration);
    customerState = _makeCustomerState(
      accessTier: initialAccessTier,
      configuration: configuration,
      activeProductIdentifier: null,
    );
  }

  final SubscriptionConfiguration configuration;

  late CustomerState customerState;
  late SubscriptionOffering currentOffering;
  rc.Offering? revenueCatOffering;
  bool isLoading = false;
  String? lastErrorMessage;

  static Future<void> configureSDKIfNeeded() async {
    final configuration = SubscriptionConfiguration.loadFromEnvironment();
    final apiKey = configuration.publicAPIKey;
    if (apiKey == null || apiKey.isEmpty) {
      return;
    }

    await rc.Purchases.setLogLevel(rc.LogLevel.debug);
    await rc.Purchases.configure(rc.PurchasesConfiguration(apiKey));
  }

  void syncPersistedAccessTier(AccessTier accessTier) {
    if (customerState.accessTier == accessTier) return;

    customerState = _makeCustomerState(
      accessTier: accessTier,
      configuration: configuration,
      activeProductIdentifier: customerState.activeProductIdentifier,
    );
    notifyListeners();
  }

  void startIntroTrial() {
    customerState = _makeCustomerState(
      accessTier: AccessTier.trial,
      configuration: configuration,
      activeProductIdentifier: currentOffering.yearlyPackage?.productIdentifier ??
          currentOffering.monthlyPackage?.productIdentifier,
    );
    notifyListeners();
  }

  Future<void> refreshCustomerState() async {
    if (!configuration.isRevenueCatReady) {
      lastErrorMessage = 'RevenueCat is not configured yet.';
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      final offerings = await rc.Purchases.getOfferings();
      final customerInfo = await rc.Purchases.getCustomerInfo();
      _applyRevenueCatState(offerings: offerings, customerInfo: customerInfo);
      lastErrorMessage = null;
    } catch (error) {
      TelemetryService.shared
          .record(error: error, context: 'subscription_refresh');
      lastErrorMessage = '$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<void> restorePurchases() async {
    if (!configuration.isRevenueCatReady) {
      lastErrorMessage = 'RevenueCat is not configured yet.';
      notifyListeners();
      return;
    }

    isLoading = true;
    notifyListeners();

    try {
      final customerInfo = await rc.Purchases.restorePurchases();
      rc.Offerings? offerings;
      try {
        offerings = await rc.Purchases.getOfferings();
      } catch (_) {
        offerings = null;
      }
      _applyRevenueCatState(offerings: offerings, customerInfo: customerInfo);
      lastErrorMessage = null;
    } catch (error) {
      TelemetryService.shared
          .record(error: error, context: 'subscription_restore');
      lastErrorMessage = '$error';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void handleCustomerInfoUpdate(rc.CustomerInfo customerInfo) {
    final accessTier = _accessTier(customerInfo);
    customerState = _makeCustomerState(
      accessTier: accessTier,
      configuration: configuration,
      activeProductIdentifier: _activeProductIdentifier(customerInfo),
    );
    notifyListeners();
  }

  void _applyRevenueCatState({
    rc.Offerings? offerings,
    required rc.CustomerInfo customerInfo,
  }) {
    final liveOffering = offerings?.current ??
        offerings?.all[configuration.offeringIdentifier];
    if (liveOffering != null) {
      revenueCatOffering = liveOffering;
      currentOffering = _makeOffering(liveOffering, configuration);
    }

    final accessTier = _accessTier(customerInfo);
    customerState = _makeCustomerState(
      accessTier: accessTier,
      configuration: configuration,
      activeProductIdentifier: _activeProductIdentifier(customerInfo),
    );
  }

  AccessTier _accessTier(rc.CustomerInfo customerInfo) {
    final entitlement =
        customerInfo.entitlements.all[configuration.entitlementIdentifier];
    if (entitlement == null || !entitlement.isActive) {
      return AccessTier.free;
    }

    if (entitlement.periodType == rc.PeriodType.trial) {
      return AccessTier.trial;
    }

    return AccessTier.pro;
  }

  String? _activeProductIdentifier(rc.CustomerInfo customerInfo) {
    return customerInfo
        .entitlements.all[configuration.entitlementIdentifier]?.productIdentifier;
  }

  static SubscriptionOffering _makeFallbackOffering(
      SubscriptionConfiguration configuration) {
    return SubscriptionOffering(
      identifier: configuration.offeringIdentifier,
      entitlementIdentifier: configuration.entitlementIdentifier,
      packages: [
        SubscriptionPackage(
          kind: PackageKind.yearly,
          title: 'Yearly',
          detail: 'Best value for regular drivers.',
          priceText: 'Yearly',
          badgeText: 'Save more',
          productIdentifier: configuration.yearlyProductIdentifier,
          introductoryOfferText: '7-day free trial',
        ),
        SubscriptionPackage(
          kind: PackageKind.monthly,
          title: 'Monthly',
          detail: 'Flexible access, billed monthly.',
          priceText: 'Monthly',
          badgeText: null,
          productIdentifier: configuration.monthlyProductIdentifier,
          introductoryOfferText: null,
        ),
      ],
      trialCTA: '7-day free trial',
      cancellationCopy: 'Try for free, Cancel anytime.',
    );
  }

  static SubscriptionOffering _makeOffering(
    rc.Offering offering,
    SubscriptionConfiguration fallbackConfiguration,
  ) {
    final packages = <SubscriptionPackage>[];

    for (final package in offering.availablePackages) {
      final kind = _packageKind(package, fallbackConfiguration);
      if (kind == null) continue;

      final storeProduct = package.storeProduct;

      packages.add(
        SubscriptionPackage(
          kind: kind,
          title: _packageTitle(kind),
          detail: _packageDetail(kind),
          priceText: storeProduct.priceString,
          badgeText: _packageBadge(kind),
          productIdentifier: storeProduct.identifier,
          introductoryOfferText: storeProduct.introductoryPrice == null
              ? null
              : 'Trial or intro offer available',
        ),
      );
    }

    packages.sort(
        (lhs, rhs) => _packageOrder(lhs.kind).compareTo(_packageOrder(rhs.kind)));

    return SubscriptionOffering(
      identifier: offering.identifier,
      entitlementIdentifier: fallbackConfiguration.entitlementIdentifier,
      packages: packages,
      trialCTA: '7-day free trial',
      cancellationCopy: 'Try for free, Cancel anytime.',
    );
  }

  static PackageKind? _packageKind(
    rc.Package package,
    SubscriptionConfiguration configuration,
  ) {
    final identifier = package.storeProduct.identifier;

    if (identifier == configuration.yearlyProductIdentifier ||
        package.packageType == rc.PackageType.annual) {
      return PackageKind.yearly;
    }

    if (identifier == configuration.monthlyProductIdentifier ||
        package.packageType == rc.PackageType.monthly) {
      return PackageKind.monthly;
    }

    switch (package.identifier.toLowerCase()) {
      case 'yearly':
      case 'annual':
        return PackageKind.yearly;
      case 'monthly':
        return PackageKind.monthly;
      default:
        return null;
    }
  }

  static String _packageTitle(PackageKind kind) {
    switch (kind) {
      case PackageKind.yearly:
        return 'Yearly';
      case PackageKind.monthly:
        return 'Monthly';
    }
  }

  static String _packageDetail(PackageKind kind) {
    switch (kind) {
      case PackageKind.yearly:
        return 'Best value for regular drivers.';
      case PackageKind.monthly:
        return 'Flexible access, billed monthly.';
    }
  }

  static String? _packageBadge(PackageKind kind) {
    switch (kind) {
      case PackageKind.yearly:
        return 'Best value';
      case PackageKind.monthly:
        return null;
    }
  }

  static int _packageOrder(PackageKind kind) {
    switch (kind) {
      case PackageKind.yearly:
        return 0;
      case PackageKind.monthly:
        return 1;
    }
  }

  static CustomerState _makeCustomerState({
    required AccessTier accessTier,
    required SubscriptionConfiguration configuration,
    required String? activeProductIdentifier,
  }) {
    return CustomerState(
      accessTier: accessTier,
      integrationMode: configuration.isRevenueCatReady
          ? IntegrationMode.revenueCat
          : IntegrationMode.localPreview,
      entitlementIdentifier: configuration.entitlementIdentifier,
      offeringIdentifier: configuration.offeringIdentifier,
      activeProductIdentifier: activeProductIdentifier,
      managementURL: Uri.parse('https://apps.apple.com/account/subscriptions'),
    );
  }
}
