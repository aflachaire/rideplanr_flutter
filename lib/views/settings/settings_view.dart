import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:purchases_ui_flutter/purchases_ui_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/app_state.dart';
import '../../design/app_theme.dart';
import '../../models/app_models.dart';
import '../../services/nav_preference.dart';
import '../../services/subscription_service.dart';
import '../../viewmodels/settings_view_model.dart';
import '../home/pro_trial_paywall_view.dart';
import 'legal_views.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({
    super.key,
    required this.viewModel,
    required this.accessTier,
    required this.subscriptionOffering,
    required this.subscriptionCustomerState,
    required this.onClaimTrial,
    required this.onSubscriptionInfoUpdated,
    required this.onSwitchToFreeAccount,
    required this.onRestorePurchases,
    required this.onSettingsChanged,
  });

  final SettingsViewModel viewModel;
  final AccessTier accessTier;
  final SubscriptionOffering subscriptionOffering;
  final CustomerState subscriptionCustomerState;
  final VoidCallback onClaimTrial;
  final void Function(rc.CustomerInfo) onSubscriptionInfoUpdated;
  final VoidCallback onSwitchToFreeAccount;
  final Future<void> Function() onRestorePurchases;
  final void Function(UserSettings) onSettingsChanged;

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  bool get _showsSubscriptionPage => widget.accessTier.hasProAccess;

  // Preferred navigation app for the "Go now" action (persisted separately
  // from UserSettings, via nav_preference.dart's shared_preferences key).
  NavApp _navApp = NavApp.ask;

  @override
  void initState() {
    super.initState();
    _loadNavApp();
  }

  Future<void> _loadNavApp() async {
    final app = await getPreferredNavApp();
    if (!mounted) return;
    setState(() => _navApp = app);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Account',
                style: TextStyle(
                  fontSize: 34,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
              const SizedBox(height: 20),
              _accountSection(context),
              const SizedBox(height: 20),
              _settingsSection(context),
              const SizedBox(height: 20),
              _appearanceSection(context),
              const SizedBox(height: 20),
              _informationSection(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary(context),
      ),
    );
  }

  Widget _navigationRow(
    BuildContext context,
    String title, {
    Color? titleColor,
    Color? chevronColor,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                  color: titleColor ?? AppTheme.textPrimary(context),
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              size: 18,
              color: chevronColor ?? AppTheme.textSecondary(context),
            ),
          ],
        ),
      ),
    );
  }

  Widget _accountSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Your account'),
          const SizedBox(height: 14),
          if (_showsSubscriptionPage)
            _navigationRow(
              context,
              'Subscription',
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => SubscriptionView(
                      offering: widget.subscriptionOffering,
                      customerState: widget.subscriptionCustomerState,
                      onSwitchToFreeAccount: widget.onSwitchToFreeAccount,
                      onRestorePurchases: widget.onRestorePurchases,
                    ),
                  ),
                );
              },
            )
          else
            _navigationRow(
              context,
              'Try Pro for free',
              titleColor: AppTheme.gold,
              chevronColor: AppTheme.gold.withValues(alpha: 0.9),
              onTap: () {
                ProTrialPaywallView.present(
                  context,
                  sourceContext: 'account',
                  offering: widget.subscriptionOffering,
                  onClaimTrial: widget.onClaimTrial,
                  onCustomerInfoUpdated: widget.onSubscriptionInfoUpdated,
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _settingsSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Settings'),
          const SizedBox(height: 14),
          _settingPicker<DistanceDisplayUnit>(
            context,
            title: 'Distance unit',
            values: DistanceDisplayUnit.values,
            selected: widget.viewModel.settings.distanceDisplayUnit,
            labelOf: (v) => v.label,
            onChanged: (value) {
              setState(() {
                widget.viewModel.settings.distanceDisplayUnit = value;
              });
              widget.onSettingsChanged(widget.viewModel.settings);
            },
          ),
          Divider(color: AppTheme.elevated(context), height: 28),
          _settingPicker<TimeDisplayFormat>(
            context,
            title: 'Time format',
            values: TimeDisplayFormat.values,
            selected: widget.viewModel.settings.timeDisplayFormat,
            labelOf: (v) => v.label,
            onChanged: (value) {
              setState(() {
                widget.viewModel.settings.timeDisplayFormat = value;
              });
              widget.onSettingsChanged(widget.viewModel.settings);
            },
          ),
          Divider(color: AppTheme.elevated(context), height: 28),
          _settingPicker<NavApp>(
            context,
            title: 'Navigation app',
            values: NavApp.values,
            selected: _navApp,
            labelOf: (v) => v.shortLabel,
            onChanged: (value) {
              setState(() => _navApp = value);
              setPreferredNavApp(value);
            },
          ),
        ],
      ),
    );
  }

  Widget _appearanceSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Appearance'),
          const SizedBox(height: 14),
          _settingPicker<AppearanceMode>(
            context,
            title: 'Theme',
            values: AppearanceMode.values,
            selected: widget.viewModel.settings.appearanceMode,
            labelOf: (v) => v.label,
            onChanged: (value) {
              setState(() {
                widget.viewModel.settings.appearanceMode = value;
              });
              widget.onSettingsChanged(widget.viewModel.settings);
            },
          ),
        ],
      ),
    );
  }

  Widget _informationSection(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Information'),
          const SizedBox(height: 14),
          _navigationRow(
            context,
            'Terms of service',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const TermsOfServiceView()),
              );
            },
          ),
          Divider(color: AppTheme.elevated(context), height: 28),
          _navigationRow(
            context,
            'Privacy Policy',
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyView()),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _settingPicker<T>(
    BuildContext context, {
    required String title,
    required List<T> values,
    required T selected,
    required String Function(T) labelOf,
    required void Function(T) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<T>(
            segments: [
              for (final value in values)
                ButtonSegment<T>(value: value, label: Text(labelOf(value))),
            ],
            selected: {selected},
            showSelectedIcon: false,
            style: SegmentedButton.styleFrom(
              selectedBackgroundColor: AppTheme.gold,
              selectedForegroundColor: AppTheme.textOnAccent(context),
              foregroundColor: AppTheme.textPrimary(context),
              backgroundColor: AppTheme.elevated(context),
              side: BorderSide(color: AppTheme.border(context)),
            ),
            onSelectionChanged: (selection) {
              if (selection.isNotEmpty) onChanged(selection.first);
            },
          ),
        ),
      ],
    );
  }
}

class SubscriptionView extends StatefulWidget {
  const SubscriptionView({
    super.key,
    required this.offering,
    required this.customerState,
    required this.onSwitchToFreeAccount,
    required this.onRestorePurchases,
  });

  final SubscriptionOffering offering;
  final CustomerState customerState;
  final VoidCallback onSwitchToFreeAccount;
  final Future<void> Function() onRestorePurchases;

  @override
  State<SubscriptionView> createState() => _SubscriptionViewState();
}

class _SubscriptionViewState extends State<SubscriptionView> {
  String get _statusTitle {
    switch (widget.customerState.accessTier) {
      case AccessTier.trial:
        return 'Pro trial active';
      case AccessTier.pro:
        return 'Pro subscription active';
      case AccessTier.free:
        return 'No active subscription';
    }
  }

  String get _statusDetail {
    switch (widget.customerState.accessTier) {
      case AccessTier.trial:
        return 'All Pro features are unlocked right now. The app is already structured around a RevenueCat entitlement and offering, so the live billing hookup can slot in without another UI rewrite.';
      case AccessTier.pro:
        return 'Your account has full Pro access across spots, filters, reminders, and the live map.';
      case AccessTier.free:
        return 'Upgrade to Pro to unlock the full forecast and live map.';
    }
  }

  Color _statusAccent(BuildContext context) {
    switch (widget.customerState.accessTier) {
      case AccessTier.trial:
      case AccessTier.pro:
        return AppTheme.gold;
      case AccessTier.free:
        return AppTheme.textSecondary(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      appBar: AppBar(
        backgroundColor: AppTheme.background(context),
        foregroundColor: AppTheme.textPrimary(context),
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Subscription',
              style: TextStyle(
                fontSize: 34,
                fontWeight: FontWeight.bold,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 20),
            _statusCard(context),
            const SizedBox(height: 20),
            _actionsCard(context),
          ],
        ),
      ),
    );
  }

  Widget _cardTitle(BuildContext context, String title) {
    return Text(
      title,
      style: TextStyle(
        fontSize: 20,
        fontWeight: FontWeight.w600,
        color: AppTheme.textPrimary(context),
      ),
    );
  }

  Widget _statusCard(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(context, 'Current access'),
          const SizedBox(height: 12),
          Text(
            _statusTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: _statusAccent(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _statusDetail,
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary(context),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Entitlement: ${widget.customerState.entitlementIdentifier}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionsCard(BuildContext context) {
    final customerState = widget.customerState;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _cardTitle(context, 'Actions'),
          const SizedBox(height: 12),
          _filledActionButton(
            context,
            title: 'Restore purchases',
            onTap: () async {
              await widget.onRestorePurchases();
            },
          ),
          if (customerState.hasProAccess) ...[
            const SizedBox(height: 12),
            _outlinedActionButton(
              context,
              title: 'Switch to free account',
              onTap: () async => widget.onSwitchToFreeAccount(),
            ),
          ],
          if (customerState.managementURL != null) ...[
            const SizedBox(height: 12),
            if (customerState.hasProAccess && customerState.isRevenueCatReady)
              _outlinedActionButton(
                context,
                title: 'Open Customer Center',
                onTap: () async {
                  await RevenueCatUI.presentCustomerCenter();
                },
              )
            else
              _outlinedActionButton(
                context,
                title: 'Manage in App Store',
                onTap: () async {
                  await launchUrl(
                    customerState.managementURL!,
                    mode: LaunchMode.externalApplication,
                  );
                },
              ),
          ],
        ],
      ),
    );
  }

  Widget _filledActionButton(
    BuildContext context, {
    required String title,
    required Future<void> Function() onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: AppTheme.elevated(context),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 14),
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _outlinedActionButton(
    BuildContext context, {
    required String title,
    required Future<void> Function() onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppTheme.border(context)),
            ),
            child: Center(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textPrimary(context),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
