import 'package:flutter/material.dart';

import '../../app/app_state.dart';
import '../../design/app_theme.dart';
import '../../models/app_models.dart';
import '../../services/location_service.dart';
import '../../services/mock_data_service.dart';
import '../../services/notification_service.dart';
import '../../services/subscription_service.dart';
import '../../services/telemetry_service.dart';
import '../../services/weather_service.dart';
import '../../viewmodels/home_view_model.dart';
import '../../viewmodels/opportunity_feed_store.dart';
import '../../viewmodels/settings_view_model.dart';
import '../home/home_view.dart';
import '../home/pro_trial_paywall_view.dart';
import '../map/map_view.dart';
import '../opportunities/opportunities_view.dart';
import '../settings/settings_view.dart';
import 'onboarding_flow_view.dart';

enum _AppTab { home, opportunities, map, settings }

extension on _AppTab {
  TelemetryScreen get telemetryScreen {
    switch (this) {
      case _AppTab.home:
        return TelemetryScreen.home;
      case _AppTab.opportunities:
        return TelemetryScreen.spots;
      case _AppTab.map:
        return TelemetryScreen.map;
      case _AppTab.settings:
        return TelemetryScreen.account;
    }
  }
}

class RootTabView extends StatefulWidget {
  const RootTabView({
    super.key,
    required this.appState,
    required this.mockDataService,
    required this.notificationService,
    required this.weatherService,
    required this.locationService,
  });

  final AppState appState;
  final MockDataService mockDataService;
  final NotificationService notificationService;
  final WeatherService weatherService;
  final LocationService locationService;

  @override
  State<RootTabView> createState() => _RootTabViewState();
}

class _RootTabViewState extends State<RootTabView>
    with WidgetsBindingObserver {
  _AppTab _selectedTab = _AppTab.home;
  bool _introPaywallShown = false;
  late final OpportunityFeedStore _opportunityFeedStore;
  late final SubscriptionService _subscriptionService;
  late final HomeViewModel _homeViewModel;
  final TelemetryService _telemetryService = TelemetryService.shared;

  String _lastFeedRefreshKey = '';
  AccessTier _lastKnownSubscriptionTier = AccessTier.free;
  AccessTier _lastKnownAppTier = AccessTier.free;

  bool get _isOpportunityFeedLoading =>
      _opportunityFeedStore.flightFeedState.isLoading ||
      _opportunityFeedStore.trainFeedState.isLoading ||
      _opportunityFeedStore.eventFeedState.isLoading ||
      _opportunityFeedStore.lifestyleFeedState.isLoading;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _opportunityFeedStore =
        OpportunityFeedStore(mockDataService: widget.mockDataService);
    _subscriptionService =
        SubscriptionService(initialAccessTier: widget.appState.accessTier);
    _homeViewModel = HomeViewModel(
      service: widget.mockDataService,
      weatherService: widget.weatherService,
    );
    _lastKnownSubscriptionTier =
        _subscriptionService.customerState.accessTier;
    _lastKnownAppTier = widget.appState.accessTier;

    widget.appState.addListener(_onStateChanged);
    widget.locationService.addListener(_onStateChanged);
    widget.notificationService.addListener(_onNotificationServiceChanged);
    _opportunityFeedStore.addListener(_onStateChanged);
    _subscriptionService.addListener(_onSubscriptionChanged);

    _telemetryService.trackTabSelection(_selectedTab.telemetryScreen);
    _telemetryService.updateUserContext(
      accessTier: _subscriptionService.customerState.accessTier,
      settings: widget.appState.settings,
      countryCode: widget.locationService.countryCode,
    );

    _refreshOpportunityFeedIfNeeded();
    _subscriptionService.refreshCustomerState();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.appState.removeListener(_onStateChanged);
    widget.locationService.removeListener(_onStateChanged);
    widget.notificationService.removeListener(_onNotificationServiceChanged);
    _opportunityFeedStore.removeListener(_onStateChanged);
    _subscriptionService.removeListener(_onSubscriptionChanged);
    _opportunityFeedStore.dispose();
    _subscriptionService.dispose();
    _homeViewModel.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;

    _telemetryService.recordMessage('app_became_active', context: 'lifecycle');
    _subscriptionService.refreshCustomerState();
  }

  void _onStateChanged() {
    if (!mounted) return;
    setState(() {});
    _refreshOpportunityFeedIfNeeded();
    _syncAppTierIfNeeded();
  }

  void _onSubscriptionChanged() {
    if (!mounted) return;
    setState(() {});

    final newTier = _subscriptionService.customerState.accessTier;
    if (_lastKnownSubscriptionTier != newTier) {
      _lastKnownSubscriptionTier = newTier;
      if (widget.appState.accessTier != newTier) {
        widget.appState.accessTier = newTier;
        _telemetryService.updateUserContext(
          accessTier: newTier,
          settings: widget.appState.settings,
          countryCode: widget.locationService.countryCode,
        );
      }
    }
  }

  void _syncAppTierIfNeeded() {
    final newTier = widget.appState.accessTier;
    if (_lastKnownAppTier == newTier) return;
    _lastKnownAppTier = newTier;
    _subscriptionService.syncPersistedAccessTier(newTier);
    _telemetryService.updateUserContext(
      accessTier: newTier,
      settings: widget.appState.settings,
      countryCode: widget.locationService.countryCode,
    );
  }

  void _onNotificationServiceChanged() {
    final opportunityID =
        widget.notificationService.pendingReminderOpportunityID;
    if (opportunityID == null) return;

    setState(() => _selectedTab = _AppTab.opportunities);
    widget.appState.focusSpots(opportunityID);
    widget.notificationService.clearPendingReminderNavigation();
  }

  /// Mirrors the iOS `.task(id: refreshToken|timeFormat)` modifier.
  void _refreshOpportunityFeedIfNeeded() {
    final refreshKey =
        '${widget.locationService.refreshToken}|${widget.appState.settings.timeDisplayFormat.label}';
    if (refreshKey == _lastFeedRefreshKey) return;
    _lastFeedRefreshKey = refreshKey;

    _opportunityFeedStore.refresh(
      coordinate: widget.locationService.currentCoordinate,
      countryCode: widget.locationService.countryCode,
      timeDisplayFormat: widget.appState.settings.timeDisplayFormat,
    );
  }

  Future<void> _refreshOpportunities() async {
    await _opportunityFeedStore.refresh(
      coordinate: widget.locationService.currentCoordinate,
      countryCode: widget.locationService.countryCode,
      timeDisplayFormat: widget.appState.settings.timeDisplayFormat,
    );
  }

  void _handleSetReminder(Opportunity opportunity) {
    final isReminderEnabled = widget.appState.isReminderEnabled(opportunity);

    if (isReminderEnabled) {
      widget.appState.setReminderEnabled(false, opportunity);
      widget.appState.removeFromPlanning(opportunity);
      widget.notificationService.cancelReminder(opportunity);
      _telemetryService.trackReminderChanged(
          isEnabled: false, opportunity: opportunity);
      return;
    }

    widget.appState.addToPlanning(opportunity);
    widget.appState.setReminderEnabled(true, opportunity);
    _telemetryService.trackReminderChanged(
        isEnabled: true, opportunity: opportunity);

    widget.notificationService.scheduleReminder(
      opportunity,
      leadTimeMinutes: widget.appState.settings.leadTimeMinutes.toInt(),
    );
  }

  void _presentIntroPaywall() {
    if (_subscriptionService.customerState.hasProAccess) return;
    _telemetryService.trackPaywallViewed(source: 'intro');
    ProTrialPaywallView.present(
      context,
      sourceContext: 'intro',
      offering: _subscriptionService.currentOffering,
      onClaimTrial: () {
        _telemetryService.trackTrialClaimed(source: 'intro');
        _subscriptionService.startIntroTrial();
      },
      onCustomerInfoUpdated: _subscriptionService.handleCustomerInfoUpdate,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.appState.hasCompletedOnboarding) {
      return OnboardingFlowView(appState: widget.appState);
    }

    // Trial-first gate: once past onboarding, auto-present the paywall on
    // launch for users without an active trial/subscription. It's dismissible
    // (X), leaving them in the locked app with persistent "Start free trial"
    // nudges on every tab.
    if (!_introPaywallShown &&
        !_subscriptionService.customerState.hasProAccess) {
      _introPaywallShown = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _presentIntroPaywall();
      });
    }

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: IndexedStack(
        index: _AppTab.values.indexOf(_selectedTab),
        children: [
          HomeView(
            viewModel: _homeViewModel,
            locationService: widget.locationService,
            opportunities: _opportunityFeedStore.opportunities,
            timeDisplayFormat: widget.appState.settings.timeDisplayFormat,
            distanceDisplayUnit: widget.appState.settings.distanceDisplayUnit,
            reminderOpportunityIDs: widget.appState.reminderOpportunityIDs,
            isOpportunityFeedLoading: _isOpportunityFeedLoading,
            hasProAccess: _subscriptionService.customerState.hasProAccess,
            subscriptionOffering: _subscriptionService.currentOffering,
            onSetReminder: _handleSetReminder,
            onClaimTrial: () {
              _telemetryService.trackTrialClaimed(source: 'home');
              _subscriptionService.startIntroTrial();
            },
            onSubscriptionInfoUpdated:
                _subscriptionService.handleCustomerInfoUpdate,
            onRefreshOpportunities: _refreshOpportunities,
            pendingScrollTarget: widget.appState.pendingHomeScrollTarget,
            onHandledScrollTarget: widget.appState.clearPendingHomeScrollTarget,
          ),
          OpportunitiesView(
            opportunities: _opportunityFeedStore.opportunities,
            flightFeedState: _opportunityFeedStore.flightFeedState,
            trainFeedState: _opportunityFeedStore.trainFeedState,
            eventFeedState: _opportunityFeedStore.eventFeedState,
            lifestyleFeedState: _opportunityFeedStore.lifestyleFeedState,
            reminderOpportunityIDs: widget.appState.reminderOpportunityIDs,
            distanceDisplayUnit: widget.appState.settings.distanceDisplayUnit,
            hasProAccess: _subscriptionService.customerState.hasProAccess,
            subscriptionOffering: _subscriptionService.currentOffering,
            pendingFocusedOpportunityID:
                widget.appState.pendingSpotsOpportunityID,
            onSetReminder: _handleSetReminder,
            onClaimTrial: () {
              _telemetryService.trackTrialClaimed(source: 'spots');
              _subscriptionService.startIntroTrial();
            },
            onSubscriptionInfoUpdated:
                _subscriptionService.handleCustomerInfoUpdate,
            onHandledFocusedOpportunity:
                widget.appState.clearPendingSpotsOpportunity,
            onRefresh: _refreshOpportunities,
          ),
          MapView(
            locationService: widget.locationService,
            plannedOpportunities: widget.appState.plannedOpportunities,
            fallbackOpportunities: _opportunityFeedStore.opportunities,
            distanceDisplayUnit: widget.appState.settings.distanceDisplayUnit,
            reminderOpportunityIDs: widget.appState.reminderOpportunityIDs,
            hasProAccess: _subscriptionService.customerState.hasProAccess,
            subscriptionOffering: _subscriptionService.currentOffering,
            onSetReminder: _handleSetReminder,
            onClaimTrial: () {
              _telemetryService.trackTrialClaimed(source: 'map');
              _subscriptionService.startIntroTrial();
            },
            onSubscriptionInfoUpdated:
                _subscriptionService.handleCustomerInfoUpdate,
          ),
          SettingsView(
            viewModel: SettingsViewModel(
              settings: widget.appState.settings,
              notificationService: widget.notificationService,
            ),
            accessTier: _subscriptionService.customerState.accessTier,
            subscriptionOffering: _subscriptionService.currentOffering,
            subscriptionCustomerState: _subscriptionService.customerState,
            onClaimTrial: () {
              _telemetryService.trackTrialClaimed(source: 'account');
              _subscriptionService.startIntroTrial();
            },
            onSubscriptionInfoUpdated:
                _subscriptionService.handleCustomerInfoUpdate,
            onSwitchToFreeAccount: () {
              widget.appState.accessTier = AccessTier.free;
            },
            onRestorePurchases: () async {
              _telemetryService.recordMessage('restore_purchases_tapped',
                  context: 'subscription');
              await _subscriptionService.restorePurchases();
            },
            onSettingsChanged: widget.appState.updateSettings,
          ),
        ],
      ),
      bottomNavigationBar: NavigationBarTheme(
        data: NavigationBarThemeData(
          indicatorColor: AppTheme.gold.withValues(alpha: 0.18),
          labelTextStyle: WidgetStatePropertyAll(
            TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ),
        child: NavigationBar(
          backgroundColor: AppTheme.surface(context),
          selectedIndex: _AppTab.values.indexOf(_selectedTab),
          onDestinationSelected: (index) {
            final tab = _AppTab.values[index];
            setState(() => _selectedTab = tab);
            _telemetryService.trackTabSelection(tab.telemetryScreen);
          },
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home, color: AppTheme.gold),
              label: 'Home',
            ),
            NavigationDestination(
              icon: const Icon(Icons.bolt_outlined),
              selectedIcon: const Icon(Icons.bolt, color: AppTheme.gold),
              label: 'Spots',
            ),
            NavigationDestination(
              icon: const Icon(Icons.map_outlined),
              selectedIcon: const Icon(Icons.map, color: AppTheme.gold),
              label: 'Map',
            ),
            NavigationDestination(
              icon: const Icon(Icons.account_circle_outlined),
              selectedIcon:
                  const Icon(Icons.account_circle, color: AppTheme.gold),
              label: 'Account',
            ),
          ],
        ),
      ),
    );
  }
}
