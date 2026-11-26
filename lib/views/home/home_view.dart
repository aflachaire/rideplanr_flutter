import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:latlong2/latlong.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;

import '../../app/app_state.dart';
import '../../design/app_theme.dart';
import '../../models/app_models.dart';
import '../../services/location_service.dart';
import '../../services/subscription_service.dart';
import '../../viewmodels/home_view_model.dart';
import '../components/components.dart';
import 'pro_trial_paywall_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({
    super.key,
    required this.viewModel,
    required this.locationService,
    required this.opportunities,
    required this.timeDisplayFormat,
    required this.distanceDisplayUnit,
    required this.reminderOpportunityIDs,
    required this.isOpportunityFeedLoading,
    required this.hasProAccess,
    required this.subscriptionOffering,
    required this.onSetReminder,
    required this.onClaimTrial,
    required this.onSubscriptionInfoUpdated,
    required this.onRefreshOpportunities,
    required this.pendingScrollTarget,
    required this.onHandledScrollTarget,
  });

  final HomeViewModel viewModel;
  final LocationService locationService;
  final List<Opportunity> opportunities;
  final TimeDisplayFormat timeDisplayFormat;
  final DistanceDisplayUnit distanceDisplayUnit;
  final Set<String> reminderOpportunityIDs;
  final bool isOpportunityFeedLoading;
  final bool hasProAccess;
  final SubscriptionOffering subscriptionOffering;
  final void Function(Opportunity) onSetReminder;
  final VoidCallback onClaimTrial;
  final void Function(rc.CustomerInfo) onSubscriptionInfoUpdated;
  final Future<void> Function() onRefreshOpportunities;
  final HomeScrollTarget? pendingScrollTarget;
  final VoidCallback onHandledScrollTarget;

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _opportunitiesSectionKey = GlobalKey();
  final GlobalKey _weatherSectionKey = GlobalKey();
  final PageController _nextMovePageController = PageController();
  int _selectedNextMoveIndex = 0;
  double _nextMoveCardHeight = 0;
  String _lastRefreshToken = '';

  @override
  void initState() {
    super.initState();
    widget.viewModel.addListener(_onViewModelChanged);
    _refreshForLocation();
  }

  @override
  void dispose() {
    widget.viewModel.removeListener(_onViewModelChanged);
    _scrollController.dispose();
    _nextMovePageController.dispose();
    super.dispose();
  }

  void _onViewModelChanged() => setState(() {});

  void _refreshForLocation() {
    final token = widget.locationService.refreshToken;
    if (token == _lastRefreshToken) return;
    _lastRefreshToken = token;
    widget.viewModel.refreshAll(widget.locationService.currentCoordinate);
  }

  @override
  void didUpdateWidget(covariant HomeView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _refreshForLocation();

    if (widget.pendingScrollTarget != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        switch (widget.pendingScrollTarget!) {
          case HomeScrollTarget.opportunities:
            _scrollToKey(_opportunitiesSectionKey);
        }
        widget.onHandledScrollTarget();
      });
    }

    final maxIndex =
        (_featuredOpportunities.length - 1).clamp(0, 1 << 31).toInt();
    if (_selectedNextMoveIndex > maxIndex) {
      _selectedNextMoveIndex = 0;
      if (_nextMovePageController.hasClients) {
        _nextMovePageController.jumpToPage(0);
      }
    }
  }

  void _scrollToKey(GlobalKey key) {
    final keyContext = key.currentContext;
    if (keyContext == null) return;
    Scrollable.ensureVisible(
      keyContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  // MARK: Derived data (port of the HomeView computed properties)

  List<Opportunity> get _availableOpportunities {
    final sorted = [...widget.opportunities]..sort((lhs, rhs) {
        if (lhs.potentialCustomers == rhs.potentialCustomers) {
          return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
        }
        return rhs.potentialCustomers.compareTo(lhs.potentialCustomers);
      });
    return sorted;
  }

  List<HourlyPotential> get _trendValues {
    final fallbackValues = widget.viewModel.dashboard.hourlyPotential;
    final availableOpportunities = _availableOpportunities;
    if (availableOpportunities.isEmpty) {
      return fallbackValues;
    }

    final currentHour = DateTime.now().hour;
    final liveWeights = List<double>.filled(12, 0);

    for (final opportunity in availableOpportunities) {
      final clampedMinutes =
          opportunity.startsInMinutes < 0 ? 0 : opportunity.startsInMinutes;
      final bucketIndex = (clampedMinutes ~/ 60).clamp(0, 11).toInt();
      var weight = opportunity.potentialCustomers * 4 + opportunity.score ~/ 2;
      if (weight < 12) weight = 12;

      // Spread each spot's weight across its hour and the next couple of hours
      // (with falloff) so a near-term cluster forms a smooth hump instead of a
      // single dominating spike on the current-hour bar.
      const falloff = [1.0, 0.5, 0.25];
      for (var offset = 0; offset < falloff.length; offset++) {
        final target = bucketIndex + offset;
        if (target < 12) liveWeights[target] += weight * falloff[offset];
      }
    }

    // Every opportunity starting within the next 60 min lands in bucket 0, so
    // that bucket accumulates far more than any other and reads as a lone spike
    // on the first bar. Smooth the buckets (blur toward their neighbours) so the
    // near-term cluster becomes a rounded hump rather than a single tall bar.
    final smoothedWeights = List<double>.generate(12, (i) {
      final prev = i > 0 ? liveWeights[i - 1] : liveWeights[i];
      final next = i < 11 ? liveWeights[i + 1] : liveWeights[i];
      return prev * 0.25 + liveWeights[i] * 0.5 + next * 0.25;
    });

    final maxLive =
        smoothedWeights.fold<double>(0, (m, v) => v > m ? v : m);
    if (maxLive == 0) {
      return fallbackValues;
    }

    final maxBase =
        fallbackValues.fold<int>(1, (m, v) => v.score > m ? v.score : m);

    return List.generate(12, (index) {
      final hour = (currentHour + index) % 24;
      final liveNorm = smoothedWeights[index] / maxLive; // 0..1
      final baseNorm = fallbackValues[index].score / maxBase; // 0..1
      // Blend live demand with the typical daily curve so the chart keeps a
      // natural shape even when live spots cluster in the current hour.
      final blended = 0.5 * liveNorm + 0.5 * baseNorm;
      final score = (blended * 100).round().clamp(8, 100).toInt();

      return HourlyPotential(hour: hour, score: score);
    });
  }

  List<Opportunity> get _featuredOpportunities {
    final primaryCards = _nextMoveCandidates.take(3).toList();
    if (primaryCards.length >= 3) {
      return primaryCards;
    }

    final fallbackCards =
        _fallbackNextMoveCards(primaryCards.map((o) => o.id).toSet());
    return [...primaryCards, ...fallbackCards].take(3).toList();
  }

  List<Opportunity> get _nextMoveCandidates {
    final availableOpportunities = _availableOpportunities;
    final primaryWindow = _rankedNextMoveCandidates(
      availableOpportunities
          .where((o) => o.startsInMinutes > 0 && o.startsInMinutes <= 60)
          .toList(),
    );

    if (primaryWindow.length >= 3) {
      return primaryWindow;
    }

    final extendedWindow = _rankedNextMoveCandidates(
      availableOpportunities
          .where((o) => o.startsInMinutes > 60 && o.startsInMinutes <= 12 * 60)
          .toList(),
    );
    final immediateFallback = _rankedNextMoveCandidates(
      availableOpportunities.where((o) => o.startsInMinutes <= 0).toList(),
    );

    return _mergeNextMoveCandidateGroups(
        [primaryWindow, extendedWindow, immediateFallback]);
  }

  List<Opportunity> _rankedNextMoveCandidates(List<Opportunity> opportunities) {
    opportunities.sort((lhs, rhs) {
      final lhsStars = starCountForOpportunity(lhs);
      final rhsStars = starCountForOpportunity(rhs);

      if (lhsStars == rhsStars) {
        if (lhs.startsInMinutes == rhs.startsInMinutes) {
          if (lhs.score == rhs.score) {
            return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
          }

          return rhs.score.compareTo(lhs.score);
        }

        return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
      }

      return rhsStars.compareTo(lhsStars);
    });
    return opportunities;
  }

  List<Opportunity> _mergeNextMoveCandidateGroups(
      List<List<Opportunity>> groups) {
    final seenIDs = <String>{};
    final merged = <Opportunity>[];

    for (final group in groups) {
      for (final opportunity in group) {
        if (seenIDs.add(opportunity.id)) {
          merged.add(opportunity);
        }
      }
    }

    return merged;
  }

  List<Opportunity> _fallbackNextMoveCards(Set<String> excludedIDs) {
    final baseCoordinate = widget.locationService.currentCoordinate ??
        (widget.opportunities.isEmpty
            ? const LatLng(0, 0)
            : widget.opportunities.first.coordinate);
    final fallbackTitleLocation = widget.locationService.cityName;

    final signals = widget.viewModel.dashboard.signals
        .where((s) => !excludedIDs.contains('home-signal-${s.id}'))
        .where((s) => const [
              SignalCategory.flights,
              SignalCategory.trains,
              SignalCategory.events,
              SignalCategory.lifestyle,
            ].contains(s.category))
        .toList()
      ..sort((lhs, rhs) {
        if (lhs.impactScore == rhs.impactScore) {
          return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
        }
        return rhs.impactScore.compareTo(lhs.impactScore);
      });

    return signals.map((signal) {
      final startsInMinutes = signal.startsInMinutes < 1 ? 1 : signal.startsInMinutes;
      final driveBase = signal.startsInMinutes < 8 ? 8 : signal.startsInMinutes;

      return Opportunity(
        id: 'home-signal-${signal.id}',
        title: signal.title,
        subtitle: signal.summary,
        zoneName: fallbackTitleLocation,
        latitude: baseCoordinate.latitude,
        longitude: baseCoordinate.longitude,
        startsInMinutes: startsInMinutes,
        distanceKilometers: 3.0,
        driveTimeMinutes: (driveBase ~/ 2).clamp(6, 18).toInt(),
        potentialCustomers: (signal.impactScore ~/ 8).clamp(4, 16).toInt(),
        score: signal.impactScore,
        categories: [signal.category],
        recommendation: signal.summary,
        detail: signal.summary,
      );
    }).toList();
  }

  /// Short motivational home title. One line per day — stable for the whole
  /// day, advancing to the next line each calendar day.
  static const List<String> _motivationTitles = [
    "Let's go!",
    'Busy day ahead',
    "Let's roll",
    'Time to move',
    'Go time',
    'Wheels up',
    "Demand's building",
    'The city\'s waking up',
    'Spots are heating up',
    'Plenty of moves today',
    'Stay one step ahead',
    'Beat the rush',
    'Be first, not last',
    'Position early',
    'Make it count',
    'Own your shift',
  ];

  String get _greetingTitle {
    final now = DateTime.now();
    final dayIndex = DateTime(now.year, now.month, now.day)
        .difference(DateTime(2020, 1, 1))
        .inDays;
    return _motivationTitles[dayIndex % _motivationTitles.length];
  }

  @override
  Widget build(BuildContext context) {
    final featuredOpportunities = _featuredOpportunities;

    // Home is the free tier: always usable. Free users get a soft upgrade
    // nudge; Spots and Map remain gated behind the trial.
    return Scaffold(
      backgroundColor: AppTheme.background(context),
      body: _homeContent(context, featuredOpportunities),
    );
  }

  Widget _homeContent(
      BuildContext context, List<Opportunity> featuredOpportunities) {
    return SafeArea(
      child: RefreshIndicator(
        color: AppTheme.gold,
        onRefresh: () async {
          await widget.onRefreshOpportunities();
          await widget.viewModel
              .refreshAll(widget.locationService.currentCoordinate);
        },
        child: SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        _greetingTitle,
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: AppTheme.textPrimary(context),
                        ),
                      ),
                    ),
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _scrollToKey(_weatherSectionKey),
                      child: Column(
                        children: [
                          Icon(
                            widget.viewModel.weatherBadge.icon,
                            size: 24,
                            color: AppTheme.gold,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.locationService.cityName,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textSecondary(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                HourlyPotentialCardView(
                  values: _trendValues,
                  timeDisplayFormat: widget.timeDisplayFormat,
                  title: 'Trend',
                ),
                const SizedBox(height: 20),
                Column(
                  key: _opportunitiesSectionKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Your next moves',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (widget.isOpportunityFeedLoading)
                      const LoadingCardView()
                    else if (featuredOpportunities.isNotEmpty)
                      _nextMovesCarousel(context, featuredOpportunities)
                    else
                      _exhaustedOpportunitiesState(context),
                  ],
                ),
                if (!widget.hasProAccess) ...[
                  const SizedBox(height: 20),
                  _proTrialPromoCard(context),
                ],
                const SizedBox(height: 20),
                Column(
                  key: _weatherSectionKey,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Weather',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary(context),
                      ),
                    ),
                    const SizedBox(height: 10),
                    WeatherForecastCardView(
                      badge: widget.viewModel.weatherBadge,
                      city: widget.locationService.cityName,
                      forecast: widget.viewModel.weatherForecast,
                      timeDisplayFormat: widget.timeDisplayFormat,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
  }

  Widget _nextMovesCarousel(
      BuildContext context, List<Opportunity> featuredOpportunities) {
    return Column(
      children: [
        SizedBox(
          // Hug the tallest card so the dots sit just below it.
          height: _nextMoveCardHeight > 0 ? _nextMoveCardHeight : 320,
          child: PageView.builder(
            controller: _nextMovePageController,
            itemCount: featuredOpportunities.length,
            onPageChanged: (index) =>
                setState(() => _selectedNextMoveIndex = index),
            itemBuilder: (context, index) {
              final opportunity = featuredOpportunities[index];
              final isReminderSet =
                  widget.reminderOpportunityIDs.contains(opportunity.id);
              final showsReminder = opportunity.startsInMinutes > 30;

              return SingleChildScrollView(
                physics: const NeverScrollableScrollPhysics(),
                child: _MeasureSize(
                  onChange: (size) {
                    if (size.height > _nextMoveCardHeight) {
                      setState(() => _nextMoveCardHeight = size.height);
                    }
                  },
                  child: OpportunityCardView(
                    opportunity: opportunity,
                    distanceDisplayUnit: widget.distanceDisplayUnit,
                    showsRecommendation: false,
                    actionTitle: 'Go now',
                    actionIcon: Icons.navigation,
                    onAction: () => showNavigationDialog(context, opportunity),
                    secondaryActionTitle: showsReminder
                        ? (isReminderSet ? 'Reminder set' : 'Remind me')
                        : null,
                    secondaryActionForeground: Colors.white,
                    secondaryActionBackground: isReminderSet
                        ? const Color.fromRGBO(23, 84, 56, 1)
                        : Colors.white.withValues(alpha: 0.14),
                    secondaryActionIcon: showsReminder
                        ? (isReminderSet ? Icons.check : Icons.notifications)
                        : null,
                    onSecondaryAction: showsReminder
                        ? () => widget.onSetReminder(opportunity)
                        : null,
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var index = 0; index < featuredOpportunities.length; index++)
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: index == _selectedNextMoveIndex ? 8 : 6,
                height: index == _selectedNextMoveIndex ? 8 : 6,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: index == _selectedNextMoveIndex
                      ? AppTheme.gold
                      : Colors.white.withValues(alpha: 0.22),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _proTrialPromoCard(BuildContext context) {
    return GestureDetector(
      onTap: () {
        ProTrialPaywallView.present(
          context,
          sourceContext: 'home',
          offering: widget.subscriptionOffering,
          onClaimTrial: widget.onClaimTrial,
          onCustomerInfoUpdated: widget.onSubscriptionInfoUpdated,
        );
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          // Static gold shine: a diagonal gold sheen over the surface.
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              AppTheme.gold.withValues(alpha: 0.30),
              AppTheme.surface(context),
              AppTheme.surface(context),
              AppTheme.gold.withValues(alpha: 0.16),
            ],
            stops: const [0.0, 0.40, 0.72, 1.0],
          ),
          border: Border.all(
            color: AppTheme.gold.withValues(alpha: 0.55),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: AppTheme.gold.withValues(alpha: 0.20),
              blurRadius: 22,
              spreadRadius: -6,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Unlock all spots & live map',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: AppTheme.textPrimary(context),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Every live spot, the full forecast, and the map view.',
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary(context),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 4),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                color: AppTheme.gold,
                borderRadius: BorderRadius.circular(18),
              ),
              child: Text(
                'Try free',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.textOnAccent(context),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _exhaustedOpportunitiesState(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No move available right now',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary(context),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Check back soon or refresh later for the next best spot.',
            style: TextStyle(
              fontSize: 15,
              color: AppTheme.textSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

/// Reports its child's rendered size (once, after layout). Used to size the
/// "next moves" carousel to the tallest card so the page dots hug it.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final void Function(Size size) onChange;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
      BuildContext context, _MeasureSizeRenderObject renderObject) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  void Function(Size size) onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize == newSize) return;
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}
