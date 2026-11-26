import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../../design/app_theme.dart';
import '../../models/app_models.dart';
import '../../services/subscription_service.dart';
import '../../viewmodels/opportunity_feed_store.dart';
import '../components/components.dart';
import '../home/pro_trial_paywall_view.dart';

enum _PlanningFilter {
  all('All'),
  flights('Flights'),
  trains('Trains'),
  events('Events'),
  lifestyle('Lifestyle');

  const _PlanningFilter(this.label);

  final String label;
}

enum _SpotSortOption {
  soonest('Soonest'),
  score('Best score'),
  closest('Nearest');

  const _SpotSortOption(this.label);

  final String label;
}

class OpportunitiesView extends StatefulWidget {
  const OpportunitiesView({
    super.key,
    required this.opportunities,
    required this.flightFeedState,
    required this.trainFeedState,
    required this.eventFeedState,
    required this.lifestyleFeedState,
    required this.reminderOpportunityIDs,
    required this.distanceDisplayUnit,
    required this.hasProAccess,
    required this.subscriptionOffering,
    required this.pendingFocusedOpportunityID,
    required this.onSetReminder,
    required this.onClaimTrial,
    required this.onSubscriptionInfoUpdated,
    required this.onHandledFocusedOpportunity,
    required this.onRefresh,
  });

  final List<Opportunity> opportunities;
  final FeedState flightFeedState;
  final FeedState trainFeedState;
  final FeedState eventFeedState;
  final FeedState lifestyleFeedState;
  final Set<String> reminderOpportunityIDs;
  final DistanceDisplayUnit distanceDisplayUnit;
  final bool hasProAccess;
  final SubscriptionOffering subscriptionOffering;
  final String? pendingFocusedOpportunityID;
  final void Function(Opportunity) onSetReminder;
  final VoidCallback onClaimTrial;
  final void Function(rc.CustomerInfo) onSubscriptionInfoUpdated;
  final VoidCallback onHandledFocusedOpportunity;
  final Future<void> Function() onRefresh;

  @override
  State<OpportunitiesView> createState() => _OpportunitiesViewState();
}

class _OpportunitiesViewState extends State<OpportunitiesView> {
  _PlanningFilter _selectedFilter = _PlanningFilter.all;
  _SpotSortOption _selectedSort = _SpotSortOption.soonest;
  final Map<String, GlobalKey> _cardKeys = {};

  List<Opportunity> get _filteredOpportunities {
    final matchingOpportunities = widget.opportunities.where((opportunity) {
      switch (_selectedFilter) {
        case _PlanningFilter.all:
          return true;
        case _PlanningFilter.flights:
          return opportunity.categories.contains(SignalCategory.flights);
        case _PlanningFilter.trains:
          return opportunity.categories.contains(SignalCategory.trains);
        case _PlanningFilter.events:
          return opportunity.categories.contains(SignalCategory.events);
        case _PlanningFilter.lifestyle:
          return opportunity.categories.contains(SignalCategory.lifestyle);
      }
    }).toList();

    matchingOpportunities.sort(_sortComparator);
    return matchingOpportunities;
  }

  int _sortComparator(Opportunity lhs, Opportunity rhs) {
    switch (_selectedSort) {
      case _SpotSortOption.soonest:
        if (lhs.startsInMinutes == rhs.startsInMinutes) {
          if (lhs.potentialCustomers == rhs.potentialCustomers) {
            return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
          }
          return rhs.potentialCustomers.compareTo(lhs.potentialCustomers);
        }

        return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
      case _SpotSortOption.score:
        final lhsStars = starCountForOpportunity(lhs);
        final rhsStars = starCountForOpportunity(rhs);

        if (lhsStars == rhsStars) {
          if (lhs.score == rhs.score) {
            if (lhs.startsInMinutes == rhs.startsInMinutes) {
              return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
            }
            return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
          }

          return rhs.score.compareTo(lhs.score);
        }

        return rhsStars.compareTo(lhsStars);
      case _SpotSortOption.closest:
        if (lhs.distanceKilometers == rhs.distanceKilometers) {
          if (lhs.startsInMinutes == rhs.startsInMinutes) {
            return rhs.potentialCustomers.compareTo(lhs.potentialCustomers);
          }
          return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
        }

        return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
    }
  }

  bool get _isLoadingCurrentFeed {
    switch (_selectedFilter) {
      case _PlanningFilter.flights:
        return widget.flightFeedState.isLoading;
      case _PlanningFilter.trains:
        return widget.trainFeedState.isLoading;
      case _PlanningFilter.events:
        return widget.eventFeedState.isLoading;
      case _PlanningFilter.lifestyle:
        return widget.lifestyleFeedState.isLoading;
      case _PlanningFilter.all:
        return _allFeedsAreLoading;
    }
  }

  bool get _allFeedsAreLoading =>
      widget.flightFeedState.isLoading &&
      widget.trainFeedState.isLoading &&
      widget.eventFeedState.isLoading &&
      widget.lifestyleFeedState.isLoading;

  String? get _feedStatusMessage {
    switch (_selectedFilter) {
      case _PlanningFilter.flights:
        return widget.flightFeedState.message(
          sourceName: 'flight arrivals',
          nearbySourcePluralName: 'airports',
          configurationName: 'flight arrivals',
          radiusKilometers: 50,
        );
      case _PlanningFilter.trains:
        return widget.trainFeedState.message(
          sourceName: 'train arrivals',
          nearbySourcePluralName: 'train stations',
          configurationName: 'train arrivals',
          radiusKilometers: 10,
        );
      case _PlanningFilter.events:
        return widget.eventFeedState.message(
          sourceName: 'events ending soon',
          nearbySourcePluralName: 'venues',
          configurationName: 'events',
          radiusKilometers: 50,
        );
      case _PlanningFilter.lifestyle:
        return widget.lifestyleFeedState.message(
          sourceName: 'business district spots',
          nearbySourcePluralName: 'business districts',
          configurationName: 'lifestyle spots',
          radiusKilometers: 15,
        );
      case _PlanningFilter.all:
        return null;
    }
  }

  IconData get _statusIcon {
    switch (_selectedFilter) {
      case _PlanningFilter.trains:
        return Icons.tram;
      case _PlanningFilter.events:
        return Icons.queue_music;
      case _PlanningFilter.lifestyle:
        return Icons.wb_twilight;
      default:
        return Icons.flight_land;
    }
  }

  Color get _statusTint {
    switch (_selectedFilter) {
      case _PlanningFilter.trains:
        return AppTheme.blue;
      case _PlanningFilter.events:
        return AppTheme.coral;
      case _PlanningFilter.lifestyle:
        return AppTheme.mint;
      default:
        return AppTheme.cyan;
    }
  }

  String get _emptyStateTitle {
    switch (_selectedFilter) {
      case _PlanningFilter.flights:
        return 'No flight spots available';
      case _PlanningFilter.trains:
        return 'No train spots available';
      default:
        return 'No spots available in this filter';
    }
  }

  String get _emptyStateMessage {
    return _feedStatusMessage ??
        'Pull to refresh later or try another filter to explore more spots.';
  }

  @override
  void didUpdateWidget(covariant OpportunitiesView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _focusOpportunityIfNeeded(widget.pendingFocusedOpportunityID);
  }

  void _focusOpportunityIfNeeded(String? opportunityID) {
    if (opportunityID == null) return;

    if (_selectedFilter != _PlanningFilter.all) {
      setState(() => _selectedFilter = _PlanningFilter.all);
      return;
    }

    final hasOpportunity =
        _filteredOpportunities.any((o) => o.id == opportunityID);
    if (!hasOpportunity) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      final key = _cardKeys[opportunityID];
      final keyContext = key?.currentContext;
      if (keyContext != null) {
        Scrollable.ensureVisible(
          keyContext,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
      widget.onHandledFocusedOpportunity();
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredOpportunities = _filteredOpportunities;
    final shouldShowLoadingSkeletons =
        _isLoadingCurrentFeed && filteredOpportunities.isEmpty;
    final feedStatusMessage = _feedStatusMessage;

    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: SafeArea(
        child: Stack(
          children: [
            IgnorePointer(
              ignoring: !widget.hasProAccess,
              child: _blurredWhenLocked(
                child: RefreshIndicator(
                  color: AppTheme.gold,
                  onRefresh: () async {
                    if (!widget.hasProAccess) return;
                    await widget.onRefresh();
                  },
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(20),
                    children: [
                      _headerRow(context),
                      const SizedBox(height: 18),
                      _filterControlsRow(context),
                      if (feedStatusMessage != null) ...[
                        const SizedBox(height: 18),
                        _feedStatusMessageView(
                          context,
                          message: feedStatusMessage,
                          icon: _statusIcon,
                          tint: _statusTint,
                        ),
                      ],
                      const SizedBox(height: 18),
                      if (shouldShowLoadingSkeletons)
                        for (var i = 0; i < 4; i++)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 18),
                            child: LoadingCardView(),
                          )
                      else if (filteredOpportunities.isEmpty)
                        _filteredEmptyState(context)
                      else
                        for (final opportunity in filteredOpportunities)
                          Padding(
                            key: _cardKeys.putIfAbsent(
                                opportunity.id, () => GlobalKey()),
                            padding: const EdgeInsets.only(bottom: 18),
                            child: _opportunityCard(context, opportunity),
                          ),
                    ],
                  ),
                ),
              ),
            ),
            if (!widget.hasProAccess) _lockedOverlay(context),
            Positioned(
              top: 18,
              right: 20,
              child: _sortMenuButton(context),
            ),
            if (!widget.hasProAccess)
              Align(
                alignment: Alignment.bottomCenter,
                child: _claimTrialBanner(context),
              ),
          ],
        ),
      ),
    );
  }

  Widget _blurredWhenLocked({required Widget child}) {
    if (widget.hasProAccess) return child;

    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: 2, sigmaY: 2),
      child: child,
    );
  }

  Widget _opportunityCard(BuildContext context, Opportunity opportunity) {
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

  Widget _headerRow(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Spots',
          style: TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            color: AppTheme.textPrimary(context),
          ),
        ),
        const Spacer(),
        // Leave space for the floating sort button.
        const SizedBox(width: 56),
      ],
    );
  }

  Widget _filterControlsRow(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in _PlanningFilter.values)
            Padding(
              padding: EdgeInsets.only(
                  left: filter == _PlanningFilter.values.first ? 0 : 10),
              child: GestureDetector(
                onTap: () => setState(() => _selectedFilter = filter),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                  decoration: BoxDecoration(
                    color: _selectedFilter == filter
                        ? AppTheme.gold
                        : AppTheme.elevated(context),
                    borderRadius: BorderRadius.circular(99),
                  ),
                  child: Text(
                    filter.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: _selectedFilter == filter
                          ? AppTheme.textOnAccent(context)
                          : AppTheme.textPrimary(context),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _feedStatusMessageView(
    BuildContext context, {
    required String message,
    required IconData icon,
    required Color tint,
  }) {
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: tint),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 15,
                color: AppTheme.textSecondary(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filteredEmptyState(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _emptyStateTitle,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            _emptyStateMessage,
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sortMenuButton(BuildContext context) {
    return PopupMenuButton<_SpotSortOption>(
      onSelected: (option) => setState(() => _selectedSort = option),
      color: AppTheme.surface(context),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => [
        const PopupMenuItem<_SpotSortOption>(
          enabled: false,
          height: 32,
          child: Text('Sort by'),
        ),
        for (final option in _SpotSortOption.values)
          PopupMenuItem<_SpotSortOption>(
            value: option,
            child: Row(
              children: [
                if (_selectedSort == option) ...[
                  const Icon(Icons.check, size: 16),
                  const SizedBox(width: 8),
                ],
                Text(option.label),
              ],
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
                      sourceContext: 'spots',
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
