import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_models.dart';

enum AccessTier {
  free,
  trial,
  pro;

  bool get hasProAccess => this == AccessTier.trial || this == AccessTier.pro;

  static AccessTier fromName(String? name) {
    for (final tier in AccessTier.values) {
      if (tier.name == name) return tier;
    }
    return AccessTier.free;
  }
}

enum HomeScrollTarget { opportunities }

class _PersistenceKeys {
  static const onboarding = 'driverintel.hasCompletedOnboarding';
  static const plannedOpportunities = 'driverintel.plannedOpportunities';
  static const reminderOpportunityIDs = 'driverintel.reminderOpportunityIDs';
  static const accessTier = 'driverintel.accessTier';
}

class AppState extends ChangeNotifier {
  AppState(this._defaults)
      : _hasCompletedOnboarding =
            _defaults.getBool(_PersistenceKeys.onboarding) ?? false,
        settings = UserSettings.load(_defaults),
        _accessTier = AccessTier.fromName(
            _defaults.getString(_PersistenceKeys.accessTier)) {
    _plannedOpportunities = _loadPlannedOpportunities();
    _reminderOpportunityIDs = Set<String>.from(
        _loadStringList(_PersistenceKeys.reminderOpportunityIDs) ?? const []);
  }

  final SharedPreferences _defaults;

  bool _hasCompletedOnboarding;
  UserSettings settings;
  List<Opportunity> _plannedOpportunities = [];
  Set<String> _reminderOpportunityIDs = {};
  AccessTier _accessTier;
  HomeScrollTarget? pendingHomeScrollTarget;
  String? pendingSpotsOpportunityID;

  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  set hasCompletedOnboarding(bool value) {
    _hasCompletedOnboarding = value;
    _defaults.setBool(_PersistenceKeys.onboarding, value);
    notifyListeners();
  }

  List<Opportunity> get plannedOpportunities =>
      List.unmodifiable(_plannedOpportunities);

  Set<String> get reminderOpportunityIDs =>
      Set.unmodifiable(_reminderOpportunityIDs);

  AccessTier get accessTier => _accessTier;

  set accessTier(AccessTier tier) {
    if (_accessTier == tier) return;
    _accessTier = tier;
    _defaults.setString(_PersistenceKeys.accessTier, tier.name);
    notifyListeners();
  }

  void updateSettings(UserSettings newSettings) {
    settings = newSettings;
    settings.persist(_defaults);
    notifyListeners();
  }

  void addToPlanning(Opportunity opportunity) {
    if (_plannedOpportunities.contains(opportunity)) return;
    _plannedOpportunities = [..._plannedOpportunities, opportunity];
    _persistPlannedOpportunities();
    notifyListeners();
  }

  void removeFromPlanning(Opportunity opportunity) {
    _plannedOpportunities =
        _plannedOpportunities.where((o) => o.id != opportunity.id).toList();
    _reminderOpportunityIDs = {..._reminderOpportunityIDs}
      ..remove(opportunity.id);
    _persistPlannedOpportunities();
    _persistReminderIDs();
    notifyListeners();
  }

  bool isPlanned(Opportunity opportunity) =>
      _plannedOpportunities.contains(opportunity);

  bool isReminderEnabled(Opportunity opportunity) =>
      _reminderOpportunityIDs.contains(opportunity.id);

  void setReminderEnabled(bool isEnabled, Opportunity opportunity) {
    final updated = {..._reminderOpportunityIDs};
    if (isEnabled) {
      updated.add(opportunity.id);
    } else {
      updated.remove(opportunity.id);
    }
    _reminderOpportunityIDs = updated;
    _persistReminderIDs();
    notifyListeners();
  }

  void scrollHome(HomeScrollTarget target) {
    pendingHomeScrollTarget = target;
    notifyListeners();
  }

  void clearPendingHomeScrollTarget() {
    pendingHomeScrollTarget = null;
  }

  void focusSpots(String opportunityID) {
    pendingSpotsOpportunityID = opportunityID;
    notifyListeners();
  }

  void clearPendingSpotsOpportunity() {
    pendingSpotsOpportunityID = null;
  }

  void claimTrial() {
    accessTier = AccessTier.trial;
  }

  void _persistPlannedOpportunities() {
    final encoded =
        jsonEncode(_plannedOpportunities.map((o) => o.toJson()).toList());
    _defaults.setString(_PersistenceKeys.plannedOpportunities, encoded);
  }

  void _persistReminderIDs() {
    _defaults.setString(_PersistenceKeys.reminderOpportunityIDs,
        jsonEncode(_reminderOpportunityIDs.toList()));
  }

  List<Opportunity> _loadPlannedOpportunities() {
    final raw = _defaults.getString(_PersistenceKeys.plannedOpportunities);
    if (raw == null) return [];

    try {
      final decoded = jsonDecode(raw) as List;
      return decoded
          .map((json) => Opportunity.fromJson(json as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  List<String>? _loadStringList(String key) {
    final raw = _defaults.getString(key);
    if (raw == null) return null;

    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return null;
    }
  }
}
