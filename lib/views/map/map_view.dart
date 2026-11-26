import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../../design/app_theme.dart';
import '../../models/app_models.dart';
import '../../services/location_service.dart';
import '../../services/service_utilities.dart';
import '../../services/subscription_service.dart';
import '../components/components.dart';
import '../home/pro_trial_paywall_view.dart';

enum _MapSpotFilter {
  flights('Flights', SignalCategory.flights),
  trains('Trains', SignalCategory.trains),
  events('Events', SignalCategory.events),
  lifestyle('Lifestyle', SignalCategory.lifestyle);

  const _MapSpotFilter(this.label, this.category);

  final String label;
  final SignalCategory category;
}

class MapView extends StatefulWidget {
  const MapView({
    super.key,
    required this.locationService,
    required this.plannedOpportunities,
    required this.fallbackOpportunities,
    required this.distanceDisplayUnit,
    required this.reminderOpportunityIDs,
    required this.hasProAccess,
    required this.subscriptionOffering,
    required this.onSetReminder,
    required this.onClaimTrial,
    required this.onSubscriptionInfoUpdated,
  });

  final LocationService locationService;
  final List<Opportunity> plannedOpportunities;
  final List<Opportunity> fallbackOpportunities;
  final DistanceDisplayUnit distanceDisplayUnit;
  final Set<String> reminderOpportunityIDs;
  final bool hasProAccess;
  final SubscriptionOffering subscriptionOffering;
  final void Function(Opportunity) onSetReminder;
  final VoidCallback onClaimTrial;
  final void Function(rc.CustomerInfo) onSubscriptionInfoUpdated;

  @override
  State<MapView> createState() => _MapViewState();
}

class _MapViewState extends State<MapView> {
  static const LatLng _fallbackCoordinate = LatLng(51.5072, -0.1276);
  static const int _maxMapSpots = 20;

  final MapController _mapController = MapController();
  String? _selectedOpportunityID;
  Set<SignalCategory> _enabledCategories =
      _MapSpotFilter.values.map((f) => f.category).toSet();
  bool _showsOnlyThreeStarSpots = false;
  LatLng? _lastCenter;

  @override
  void initState() {
    super.initState();
    widget.locationService.refreshLocation();
  }

  List<Opportunity> get _displayedOpportunities {
    final filteredOpportunities = widget.fallbackOpportunities
        .where((opportunity) {
          final hasEnabledCategory =
              opportunity.categories.any(_enabledCategories.contains);
          final passesStars = !_showsOnlyThreeStarSpots ||
              starCountForOpportunity(opportunity) == 3;
          return hasEnabledCategory && passesStars;
        })
        .toList()
      ..sort((lhs, rhs) {
        if (lhs.startsInMinutes == rhs.startsInMinutes) {
          if (lhs.potentialCustomers == rhs.potentialCustomers) {
            return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
          }
          return rhs.potentialCustomers.compareTo(lhs.potentialCustomers);
        }

        return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
      });

    return _balancedMapOpportunities(filteredOpportunities);
  }

  List<Opportunity> _balancedMapOpportunities(List<Opportunity> opportunities) {
    final buckets = <SignalCategory, List<Opportunity>>{};
    for (final opportunity in opportunities) {
      buckets
          .putIfAbsent(_primaryCategory(opportunity), () => [])
          .add(opportunity);
    }

    const categoryOrder = [
      SignalCategory.flights,
      SignalCategory.trains,
      SignalCategory.events,
      SignalCategory.lifestyle,
    ];
    final balanced = <Opportunity>[];

    while (balanced.length < _maxMapSpots) {
      var appendedAtLeastOne = false;

      for (final category in categoryOrder) {
        final bucket = buckets[category];
        if (bucket == null || bucket.isEmpty) continue;

        balanced.add(bucket.removeAt(0));
        appendedAtLeastOne = true;

        if (balanced.length == _maxMapSpots) break;
      }

      if (!appendedAtLeastOne) break;
    }

    return balanced;
  }

  SignalCategory _primaryCategory(Opportunity opportunity) {
    for (final category in opportunity.categories) {
      if (category != SignalCategory.traffic) return category;
    }
    return SignalCategory.events;
  }

  Opportunity? get _selectedOpportunity {
    final id = _selectedOpportunityID;
    if (id == null) return null;

    for (final opportunity in _displayedOpportunities) {
      if (opportunity.id == id) return opportunity;
    }
    return null;
  }

  LatLng get _centerCoordinate =>
      _selectedOpportunity?.coordinate ??
      widget.locationService.currentCoordinate ??
      _fallbackCoordinate;

  @override
  Widget build(BuildContext context) {
    final displayedOpportunities = _displayedOpportunities;
    final selectedOpportunity = _selectedOpportunity;
    final highlightedIDs = widget.plannedOpportunities.map((o) => o.id).toSet();

    // Drop the selection when the spot disappears from the displayed set.
    if (_selectedOpportunityID != null && selectedOpportunity == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _selectedOpportunityID = null);
      });
    }

    _recentreIfNeeded();

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: Stack(
        children: [
          IgnorePointer(
            ignoring: !widget.hasProAccess,
            child: _blurredWhenLocked(
              child: Stack(
                children: [
                  Positioned.fill(
                    child: FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _centerCoordinate,
                        initialZoom: 12,
                        onTap: (_, __) =>
                            setState(() => _selectedOpportunityID = null),
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                          userAgentPackageName: 'com.codex.driverintel.flutter',
                        ),
                        MarkerLayer(
                          markers: [
                            for (final opportunity in displayedOpportunities)
                              Marker(
                                point: opportunity.coordinate,
                                width: 120,
                                height: 78,
                                alignment: Alignment.topCenter,
                                child: GestureDetector(
                                  onTap: () => setState(() =>
                                      _selectedOpportunityID = opportunity.id),
                                  child: _MapLabelView(
                                    opportunity: opportunity,
                                    isSelected:
                                        opportunity.id == _selectedOpportunityID,
                                    isHighlighted:
                                        highlightedIDs.contains(opportunity.id),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                      child: Align(
                        alignment: Alignment.topRight,
                        child: _filterMenuButton(context),
                      ),
                    ),
                  ),
                  if (widget.hasProAccess && selectedOpportunity != null)
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                        child: _selectedOpportunityCard(selectedOpportunity),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (!widget.hasProAccess) _lockedOverlay(context),
          if (!widget.hasProAccess)
            SafeArea(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: _claimTrialBanner(context),
              ),
            ),
        ],
      ),
    );
  }

  void _recentreIfNeeded() {
    final target = _centerCoordinate;
    final last = _lastCenter;

    if (last == null ||
        distanceKilometersBetween(last, target) * 1000 > 500) {
      _lastCenter = target;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(target, _mapController.camera.zoom);
        } catch (_) {
          // The controller throws before the map is rendered; safe to ignore.
        }
      });
    }
  }

  Widget _blurredWhenLocked({required Widget child}) {
    if (widget.hasProAccess) return child;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: child,
    );
  }

  Widget _filterMenuButton(BuildContext context) {
    return PopupMenuButton<void>(
      color: AppTheme.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        const PopupMenuItem<void>(
          enabled: false,
          height: 32,
          child: Text('Categories'),
        ),
        for (final filter in _MapSpotFilter.values)
          PopupMenuItem<void>(
            child: StatefulBuilder(
              builder: (context, setMenuState) {
                final isEnabled = _enabledCategories.contains(filter.category);
                return Row(
                  children: [
                    Expanded(child: Text(filter.label)),
                    Switch(
                      value: isEnabled,
                      activeTrackColor: AppTheme.gold,
                      onChanged: (value) {
                        setState(() {
                          final updated = {..._enabledCategories};
                          if (value) {
                            updated.add(filter.category);
                          } else {
                            updated.remove(filter.category);
                          }
                          _enabledCategories = updated;
                        });
                        setMenuState(() {});
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        const PopupMenuItem<void>(
          enabled: false,
          height: 32,
          child: Text('Quality'),
        ),
        PopupMenuItem<void>(
          child: StatefulBuilder(
            builder: (context, setMenuState) {
              return Row(
                children: [
                  const Expanded(child: Text('Only 3 stars')),
                  Switch(
                    value: _showsOnlyThreeStarSpots,
                    activeTrackColor: AppTheme.gold,
                    onChanged: (value) {
                      setState(() => _showsOnlyThreeStarSpots = value);
                      setMenuState(() {});
                    },
                  ),
                ],
              );
            },
          ),
        ),
      ],
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AppTheme.surface(context).withValues(alpha: 0.85),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Icon(
          Icons.tune,
          size: 20,
          color: AppTheme.textPrimary(context),
        ),
      ),
    );
  }

  Widget _selectedOpportunityCard(Opportunity opportunity) {
    final isReminderSet =
        widget.reminderOpportunityIDs.contains(opportunity.id);
    final showsReminder = opportunity.startsInMinutes > 30;

    return OpportunityCardView(
      opportunity: opportunity,
      distanceDisplayUnit: widget.distanceDisplayUnit,
      showsRecommendation: false,
      actionTitle: 'Go now',
      actionIcon: Icons.navigation,
      onAction: () => showNavigationDialog(context, opportunity),
      secondaryActionTitle:
          showsReminder ? (isReminderSet ? 'Reminder set' : 'Remind me') : null,
      secondaryActionForeground: Colors.white,
      secondaryActionBackground: isReminderSet
          ? const Color.fromRGBO(23, 84, 56, 1)
          : Colors.white.withValues(alpha: 0.14),
      secondaryActionIcon: showsReminder
          ? (isReminderSet ? Icons.check : Icons.notifications)
          : null,
      onSecondaryAction:
          showsReminder ? () => widget.onSetReminder(opportunity) : null,
    );
  }

  Widget _lockedOverlay(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppTheme.background(context).withValues(alpha: 0.02),
              AppTheme.background(context).withValues(alpha: 0.06),
              AppTheme.background(context).withValues(alpha: 0.14),
            ],
          ),
        ),
        child: const SizedBox.expand(),
      ),
    );
  }

  Widget _claimTrialBanner(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 14),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: AppTheme.surface(context),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: AppTheme.gold.withValues(alpha: 0.55),
            width: 1.2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Unlock Pro features',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: AppTheme.gold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'See every live spot before everyone else with the full forecast and map view.',
              style: TextStyle(
                fontSize: 13,
                color: AppTheme.textPrimary(context),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: Material(
                color: AppTheme.gold,
                borderRadius: BorderRadius.circular(18),
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: () {
                    ProTrialPaywallView.present(
                      context,
                      sourceContext: 'map',
                      offering: widget.subscriptionOffering,
                      onClaimTrial: widget.onClaimTrial,
                      onCustomerInfoUpdated: widget.onSubscriptionInfoUpdated,
                    );
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Center(
                      child: Text(
                        'Try for free',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textOnAccent(context),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Port of the iOS `PlanningMapLabelView`: category icon + time remaining +
/// star row inside a rounded chip.
class _MapLabelView extends StatelessWidget {
  const _MapLabelView({
    required this.opportunity,
    required this.isSelected,
    required this.isHighlighted,
  });

  final Opportunity opportunity;
  final bool isSelected;
  final bool isHighlighted;

  SignalCategory get _displayCategory {
    for (final category in opportunity.categories) {
      if (category != SignalCategory.traffic) return category;
    }
    return SignalCategory.events;
  }

  Color get _borderColor {
    if (isSelected) return AppTheme.gold.withValues(alpha: 0.7);
    if (isHighlighted) return AppTheme.mint.withValues(alpha: 0.75);
    return Colors.white.withValues(alpha: 0.08);
  }

  Color get _shadowColor {
    if (isHighlighted) return AppTheme.mint.withValues(alpha: 0.24);
    return Colors.black.withValues(alpha: 0.24);
  }

  @override
  Widget build(BuildContext context) {
    final category = _displayCategory;
    final filledStars = starCountForOpportunity(opportunity);
    final timeRemainingColor =
        opportunity.startsInMinutes.isDriverIntelImmediateTime
            ? AppTheme.success
            : AppTheme.gold;

    return Container(
      constraints: const BoxConstraints(minWidth: 96),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.surface(context)
            .withValues(alpha: isSelected ? 0.98 : 1.0),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _borderColor,
          width: isSelected || isHighlighted ? 1.2 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: _shadowColor,
            blurRadius: 16,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: category.tint.withValues(alpha: 0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(category.icon, size: 12, color: category.tint),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  opportunity.startsInMinutes.driverIntelTimeRemainingText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: timeRemainingColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var index = 0; index < 3; index++)
                Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 0 : 2),
                  child: Icon(
                    index < filledStars ? Icons.star : Icons.star_border,
                    size: 10,
                    color: index < filledStars
                        ? AppTheme.gold
                        : Colors.white.withValues(alpha: 0.28),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
