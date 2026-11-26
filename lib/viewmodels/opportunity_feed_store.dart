import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import '../services/flight_arrivals_service.dart';
import '../services/lifestyle_spots_service.dart';
import '../services/mock_data_service.dart';
import '../services/nearby_airport_service.dart';
import '../services/predicthq_events_service.dart';
import '../services/ticketmaster_events_service.dart';
import '../services/train_departures_service.dart';

enum FeedStateKind {
  idle,
  loading,
  loaded,
  noLocation,
  noNearbySources,
  noData,
  notConfigured,
  failed,
}

class FeedState {
  const FeedState._(this.kind, {this.count = 0, this.errorMessage});

  final FeedStateKind kind;
  final int count;
  final String? errorMessage;

  static const idle = FeedState._(FeedStateKind.idle);
  static const loading = FeedState._(FeedStateKind.loading);
  static const noLocation = FeedState._(FeedStateKind.noLocation);
  static const noNearbySources = FeedState._(FeedStateKind.noNearbySources);
  static const noData = FeedState._(FeedStateKind.noData);
  static const notConfigured = FeedState._(FeedStateKind.notConfigured);

  factory FeedState.loaded(int count) =>
      FeedState._(FeedStateKind.loaded, count: count);

  factory FeedState.failed(String message) =>
      FeedState._(FeedStateKind.failed, errorMessage: message);

  bool get isLoading => kind == FeedStateKind.loading;

  String? message({
    required String sourceName,
    required String nearbySourcePluralName,
    required String configurationName,
    required int radiusKilometers,
  }) {
    switch (kind) {
      case FeedStateKind.idle:
      case FeedStateKind.loading:
      case FeedStateKind.loaded:
        return null;
      case FeedStateKind.noLocation:
        return 'Enable location access to discover nearby $nearbySourcePluralName.';
      case FeedStateKind.noNearbySources:
        return 'No $nearbySourcePluralName found within $radiusKilometers km of your location.';
      case FeedStateKind.noData:
        return 'No $sourceName found right now for nearby $nearbySourcePluralName.';
      case FeedStateKind.notConfigured:
        return 'Live $configurationName are not configured yet.';
      case FeedStateKind.failed:
        return errorMessage;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is FeedState &&
      other.kind == kind &&
      other.count == count &&
      other.errorMessage == errorMessage;

  @override
  int get hashCode => Object.hash(kind, count, errorMessage);
}

enum _SourceKind {
  flights,
  trains,
  events,
  lifestyle;

  int get postStartGraceMinutes {
    switch (this) {
      case _SourceKind.flights:
      case _SourceKind.trains:
      case _SourceKind.lifestyle:
        return 120;
      case _SourceKind.events:
        return 60;
    }
  }
}

class _SourceCacheKey {
  const _SourceCacheKey({
    required this.latitudeBucket,
    required this.longitudeBucket,
    required this.countryCode,
    required this.timeDisplayFormat,
  });

  final int latitudeBucket;
  final int longitudeBucket;
  final String? countryCode;
  final TimeDisplayFormat timeDisplayFormat;

  @override
  bool operator ==(Object other) =>
      other is _SourceCacheKey &&
      other.latitudeBucket == latitudeBucket &&
      other.longitudeBucket == longitudeBucket &&
      other.countryCode == countryCode &&
      other.timeDisplayFormat == timeDisplayFormat;

  @override
  int get hashCode =>
      Object.hash(latitudeBucket, longitudeBucket, countryCode, timeDisplayFormat);
}

class _SourceCacheEntry {
  const _SourceCacheEntry({
    required this.opportunities,
    required this.feedState,
    required this.createdAt,
    required this.coveredUntil,
  });

  final List<Opportunity> opportunities;
  final FeedState feedState;
  final DateTime createdAt;
  final DateTime coveredUntil;
}

class _CachedSnapshot {
  const _CachedSnapshot({
    required this.opportunities,
    required this.feedState,
    required this.coveredUntil,
  });

  final List<Opportunity> opportunities;
  final FeedState feedState;
  final DateTime coveredUntil;
}

/// Per-source state container used by the generic loader below.
class _SourceFeed {
  _SourceFeed(this.kind);

  final _SourceKind kind;
  FeedState state = FeedState.idle;
  List<Opportunity> cachedOpportunities = [];
  final Map<_SourceCacheKey, _SourceCacheEntry> cache = {};
}

/// Port of the iOS `OpportunityFeedStore`: merges live flight, train, event,
/// and lifestyle feeds with per-source caching, rebasing, and top-ups.
class OpportunityFeedStore extends ChangeNotifier {
  static const int maxUpcomingWindowMinutes = 12 * 60;
  static const Duration _liveFeedTimeout = Duration(seconds: 12);
  static const double _cacheBucketPrecision = 100.0;
  static const Duration _cacheTopUpTolerance = Duration(seconds: 60);

  OpportunityFeedStore({
    required MockDataService mockDataService,
    NearbyAirportService? nearbyAirportService,
    FlightArrivalsService? flightArrivalsService,
    TrainDeparturesService? trainDeparturesService,
    TicketmasterEventsService? ticketmasterEventsService,
    PredictHQEventsService? predictHQEventsService,
    LifestyleSpotsService? lifestyleSpotsService,
  })  : _mockDataService = mockDataService,
        _nearbyAirportService = nearbyAirportService ?? NearbyAirportService(),
        _flightArrivalsService =
            flightArrivalsService ?? FlightArrivalsService(),
        _trainDeparturesService =
            trainDeparturesService ?? TrainDeparturesService(),
        _ticketmasterEventsService =
            ticketmasterEventsService ?? TicketmasterEventsService(),
        _predictHQEventsService =
            predictHQEventsService ?? PredictHQEventsService(),
        _lifestyleSpotsService =
            lifestyleSpotsService ?? LifestyleSpotsService() {
    opportunities = _cappedOpportunities(_mockDataService.allOpportunities());
  }

  final MockDataService _mockDataService;
  final NearbyAirportService _nearbyAirportService;
  final FlightArrivalsService _flightArrivalsService;
  final TrainDeparturesService _trainDeparturesService;
  final TicketmasterEventsService _ticketmasterEventsService;
  final PredictHQEventsService _predictHQEventsService;
  final LifestyleSpotsService _lifestyleSpotsService;

  late List<Opportunity> opportunities;

  final _SourceFeed _flights = _SourceFeed(_SourceKind.flights);
  final _SourceFeed _trains = _SourceFeed(_SourceKind.trains);
  final _SourceFeed _events = _SourceFeed(_SourceKind.events);
  final _SourceFeed _lifestyle = _SourceFeed(_SourceKind.lifestyle);

  FeedState get flightFeedState => _flights.state;
  FeedState get trainFeedState => _trains.state;
  FeedState get eventFeedState => _events.state;
  FeedState get lifestyleFeedState => _lifestyle.state;

  Future<void> refresh({
    required LatLng? coordinate,
    String? countryCode,
    TimeDisplayFormat timeDisplayFormat = TimeDisplayFormat.twelveHour,
  }) async {
    final fallback = _cappedOpportunities(_mockDataService.allOpportunities());

    if (coordinate == null) {
      opportunities = fallback;
      _flights.state = FeedState.noLocation;
      _trains.state = FeedState.noLocation;
      _events.state = FeedState.noLocation;
      _lifestyle.state = FeedState.noLocation;
      notifyListeners();
      return;
    }

    final sourceCacheKey = _cacheKey(
      coordinate,
      countryCode: countryCode,
      timeDisplayFormat: timeDisplayFormat,
    );

    final results = await Future.wait([
      _loadSource(
        feed: _flights,
        cacheKey: sourceCacheKey,
        fetchWithTimeout: (windowStart, windowEnd) =>
            _fetchLiveFlightOpportunitiesWithTimeout(
          coordinate: coordinate,
          timeDisplayFormat: timeDisplayFormat,
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
      _loadSource(
        feed: _trains,
        cacheKey: sourceCacheKey,
        fetchWithTimeout: (windowStart, windowEnd) =>
            _fetchLiveTrainOpportunitiesWithTimeout(
          coordinate: coordinate,
          countryCode: countryCode,
          timeDisplayFormat: timeDisplayFormat,
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
      _loadSource(
        feed: _events,
        cacheKey: sourceCacheKey,
        fetchWithTimeout: (windowStart, windowEnd) =>
            _fetchLiveEventOpportunitiesWithTimeout(
          coordinate: coordinate,
          countryCode: countryCode,
          timeDisplayFormat: timeDisplayFormat,
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
      _loadSource(
        feed: _lifestyle,
        cacheKey: sourceCacheKey,
        fetchWithTimeout: (windowStart, windowEnd) =>
            _fetchLiveLifestyleOpportunitiesWithTimeout(
          coordinate: coordinate,
          timeDisplayFormat: timeDisplayFormat,
          windowStart: windowStart,
          windowEnd: windowEnd,
        ),
      ),
    ]);

    final effectiveFlightOpportunities = _resolvedOpportunities(
      latest: _cappedOpportunities(results[0]),
      cached: _cappedOpportunities(_flights.cachedOpportunities),
      feedState: _flights.state,
    );
    final effectiveTrainOpportunities = _resolvedOpportunities(
      latest: _cappedOpportunities(results[1]),
      cached: _cappedOpportunities(_trains.cachedOpportunities),
      feedState: _trains.state,
    );
    final effectiveEventOpportunities = _resolvedOpportunities(
      latest: _cappedOpportunities(results[2]),
      cached: _cappedOpportunities(_events.cachedOpportunities),
      feedState: _events.state,
    );
    final effectiveLifestyleOpportunities = _resolvedOpportunities(
      latest: _cappedOpportunities(results[3]),
      cached: _cappedOpportunities(_lifestyle.cachedOpportunities),
      feedState: _lifestyle.state,
    );

    _flights.cachedOpportunities = effectiveFlightOpportunities;
    _trains.cachedOpportunities = effectiveTrainOpportunities;
    _events.cachedOpportunities = effectiveEventOpportunities;
    _lifestyle.cachedOpportunities = effectiveLifestyleOpportunities;

    final shouldReplaceFlightFallback = effectiveFlightOpportunities.isNotEmpty;
    final shouldReplaceTrainFallback = effectiveTrainOpportunities.isNotEmpty;
    final shouldReplaceEventFallback = effectiveEventOpportunities.isNotEmpty;
    final shouldReplaceLifestyleFallback =
        effectiveLifestyleOpportunities.isNotEmpty;

    final remainingFallbacks = fallback.where((opportunity) {
      final hasFlights = opportunity.categories.contains(SignalCategory.flights);
      final hasTrains = opportunity.categories.contains(SignalCategory.trains);
      final hasEvents = opportunity.categories.contains(SignalCategory.events);
      final hasLifestyle =
          opportunity.categories.contains(SignalCategory.lifestyle);

      if (hasFlights && shouldReplaceFlightFallback) return false;
      if (hasTrains && shouldReplaceTrainFallback) return false;
      if (hasEvents && shouldReplaceEventFallback) return false;
      if (hasLifestyle && shouldReplaceLifestyleFallback) return false;

      return true;
    }).toList();

    final mergedOpportunities = [
      _notificationTestOpportunity(timeDisplayFormat),
      ...effectiveFlightOpportunities,
      ...effectiveTrainOpportunities,
      ...effectiveEventOpportunities,
      ...effectiveLifestyleOpportunities,
      ...remainingFallbacks,
    ];
    final resolved = mergedOpportunities.isEmpty ? fallback : mergedOpportunities;
    opportunities = _cappedOpportunities(resolved);
    notifyListeners();
  }

  static List<Opportunity> _cappedOpportunities(List<Opportunity> opportunities) {
    return opportunities
        .where((o) => o.startsInMinutes <= maxUpcomingWindowMinutes)
        .toList();
  }

  Opportunity _notificationTestOpportunity(TimeDisplayFormat timeDisplayFormat) {
    final startDate = DateTime.now().add(const Duration(minutes: 31));
    final endDate = startDate.add(const Duration(hours: 1));
    final startText = timeDisplayFormat.compactTimeString(startDate);
    final endText = timeDisplayFormat.compactTimeString(endDate);

    return Opportunity(
      id: 'notification-test-miami',
      title: 'MiamiCentral Station',
      subtitle: '3 Brightline arrivals from $startText to $endText',
      zoneName: 'MiamiCentral',
      latitude: 25.7783,
      longitude: -80.1955,
      startsInMinutes: 31,
      distanceKilometers: 1.8,
      driveTimeMinutes: 8,
      potentialCustomers: 7,
      score: 84,
      categories: const [SignalCategory.trains],
      recommendation:
          'Test reminder timing before the next rail arrivals at MiamiCentral.',
      detail:
          'Notification test spot: a compact train-arrival wave is scheduled from $startText to $endText, so you can verify the 31-minute reminder flow.',
    );
  }

  List<Opportunity> _resolvedOpportunities({
    required List<Opportunity> latest,
    required List<Opportunity> cached,
    required FeedState feedState,
  }) {
    if (latest.isNotEmpty) {
      return latest;
    }

    if (cached.isEmpty) {
      return [];
    }

    if (feedState.kind == FeedStateKind.failed) {
      return cached;
    }

    return [];
  }

  /// Generic per-source loader implementing the cache / rebase / top-up logic
  /// that the iOS store duplicates per source.
  Future<List<Opportunity>> _loadSource({
    required _SourceFeed feed,
    required _SourceCacheKey cacheKey,
    required Future<List<Opportunity>> Function(
            DateTime windowStart, DateTime windowEnd)
        fetchWithTimeout,
  }) async {
    final now = DateTime.now();
    final targetWindowEnd = _targetWindowEnd(now);

    final snapshot = _cachedSnapshot(cacheKey, feed);
    if (snapshot != null) {
      feed.state = snapshot.feedState;

      if (!_shouldTopUp(snapshot, targetWindowEnd)) {
        return snapshot.opportunities;
      }

      final topUpStart = snapshot.coveredUntil.isAfter(now)
          ? snapshot.coveredUntil
          : now;
      final topUpOpportunities =
          await fetchWithTimeout(topUpStart, targetWindowEnd);
      final latestFetchState = feed.state;

      if (latestFetchState.kind == FeedStateKind.failed &&
          snapshot.opportunities.isNotEmpty) {
        feed.state = FeedState.loaded(snapshot.opportunities.length);
        return snapshot.opportunities;
      }

      final mergedOpportunities = _mergedOpportunities(
        current: snapshot.opportunities,
        additional: topUpOpportunities,
      );
      final resolvedState = _resolvedFeedState(
        mergedCount: mergedOpportunities.length,
        latestFetchState: latestFetchState,
        cachedFeedState: snapshot.feedState,
      );

      feed.state = resolvedState;
      _storeCachedEntry(
        feed: feed,
        key: cacheKey,
        opportunities: mergedOpportunities,
        feedState: resolvedState,
        createdAt: now,
        coveredUntil: targetWindowEnd,
      );
      return mergedOpportunities;
    }

    feed.state = FeedState.loading;
    notifyListeners();
    final freshOpportunities = await fetchWithTimeout(now, targetWindowEnd);
    final resolvedState = _resolvedFeedState(
      mergedCount: freshOpportunities.length,
      latestFetchState: feed.state,
      cachedFeedState: FeedState.idle,
    );
    feed.state = resolvedState;
    _storeCachedEntry(
      feed: feed,
      key: cacheKey,
      opportunities: freshOpportunities,
      feedState: resolvedState,
      createdAt: now,
      coveredUntil: targetWindowEnd,
    );
    return freshOpportunities;
  }

  static _SourceCacheKey _cacheKey(
    LatLng coordinate, {
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
  }) {
    return _SourceCacheKey(
      latitudeBucket: (coordinate.latitude * _cacheBucketPrecision).round(),
      longitudeBucket: (coordinate.longitude * _cacheBucketPrecision).round(),
      countryCode: countryCode?.toUpperCase(),
      timeDisplayFormat: timeDisplayFormat,
    );
  }

  _CachedSnapshot? _cachedSnapshot(_SourceCacheKey key, _SourceFeed feed) {
    final entry = feed.cache[key];
    if (entry == null) {
      return null;
    }

    final now = DateTime.now();
    if (!entry.coveredUntil.isAfter(now)) {
      feed.cache.remove(key);
      return null;
    }

    final rebasedOpportunities = _rebaseCachedOpportunities(
      entry.opportunities,
      sourceKind: feed.kind,
      createdAt: entry.createdAt,
      now: now,
    );

    return _CachedSnapshot(
      opportunities: rebasedOpportunities,
      feedState:
          _currentFeedState(entry.feedState, rebasedOpportunities.length),
      coveredUntil: entry.coveredUntil,
    );
  }

  bool _shouldTopUp(_CachedSnapshot snapshot, DateTime targetWindowEnd) {
    switch (snapshot.feedState.kind) {
      case FeedStateKind.notConfigured:
      case FeedStateKind.noNearbySources:
        return false;
      default:
        return snapshot.coveredUntil
            .isBefore(targetWindowEnd.subtract(_cacheTopUpTolerance));
    }
  }

  List<Opportunity> _rebaseCachedOpportunities(
    List<Opportunity> opportunities, {
    required _SourceKind sourceKind,
    required DateTime createdAt,
    required DateTime now,
  }) {
    final rebased = <Opportunity>[];

    for (final opportunity in opportunities) {
      final startDate =
          createdAt.add(Duration(minutes: opportunity.startsInMinutes));
      final expiryDate =
          startDate.add(Duration(minutes: sourceKind.postStartGraceMinutes));

      if (!expiryDate.isAfter(now)) continue;

      final rebasedMinutes =
          (startDate.difference(now).inSeconds ~/ 60).clamp(0, 1 << 31).toInt();
      if (rebasedMinutes > maxUpcomingWindowMinutes) continue;

      rebased.add(opportunity.copyWith(startsInMinutes: rebasedMinutes));
    }

    rebased.sort(_sourceSortComparator);
    return rebased;
  }

  List<Opportunity> _mergedOpportunities({
    required List<Opportunity> current,
    required List<Opportunity> additional,
  }) {
    final mergedByID = <String, Opportunity>{};

    for (final opportunity in current) {
      mergedByID[opportunity.id] = opportunity;
    }

    for (final opportunity in additional) {
      mergedByID[opportunity.id] = opportunity;
    }

    final merged = mergedByID.values.toList()..sort(_sourceSortComparator);
    return merged;
  }

  FeedState _currentFeedState(FeedState feedState, int currentCount) {
    if (currentCount > 0) {
      return FeedState.loaded(currentCount);
    }

    if (feedState.kind == FeedStateKind.loaded) {
      return FeedState.noData;
    }

    return feedState;
  }

  FeedState _resolvedFeedState({
    required int mergedCount,
    required FeedState latestFetchState,
    required FeedState cachedFeedState,
  }) {
    if (mergedCount > 0) {
      return FeedState.loaded(mergedCount);
    }

    if (_isCacheable(latestFetchState)) {
      return latestFetchState;
    }

    if (_isCacheable(cachedFeedState)) {
      return cachedFeedState;
    }

    return latestFetchState;
  }

  void _storeCachedEntry({
    required _SourceFeed feed,
    required _SourceCacheKey key,
    required List<Opportunity> opportunities,
    required FeedState feedState,
    required DateTime createdAt,
    required DateTime coveredUntil,
  }) {
    if (!_isCacheable(feedState)) {
      return;
    }

    feed.cache[key] = _SourceCacheEntry(
      opportunities: opportunities,
      feedState: feedState,
      createdAt: createdAt,
      coveredUntil: coveredUntil,
    );
  }

  static bool _isCacheable(FeedState feedState) {
    switch (feedState.kind) {
      case FeedStateKind.loaded:
      case FeedStateKind.noNearbySources:
      case FeedStateKind.noData:
      case FeedStateKind.notConfigured:
        return true;
      case FeedStateKind.idle:
      case FeedStateKind.loading:
      case FeedStateKind.noLocation:
      case FeedStateKind.failed:
        return false;
    }
  }

  static DateTime _targetWindowEnd(DateTime date) =>
      date.add(const Duration(minutes: maxUpcomingWindowMinutes));

  int _sourceSortComparator(Opportunity lhs, Opportunity rhs) {
    if (lhs.startsInMinutes == rhs.startsInMinutes) {
      if (lhs.score == rhs.score) {
        return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
      }
      return rhs.score.compareTo(lhs.score);
    }

    return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
  }

  // MARK: Timeout racing

  Future<List<Opportunity>> _raceAgainstTimeout({
    required Future<List<Opportunity>> Function() operation,
    required void Function() onTimeout,
  }) async {
    final completer = Completer<List<Opportunity>>();

    operation().then((opportunities) {
      if (!completer.isCompleted) completer.complete(opportunities);
    }).catchError((Object _) {
      if (!completer.isCompleted) completer.complete(<Opportunity>[]);
    });

    Future<void>.delayed(_liveFeedTimeout).then((_) {
      if (!completer.isCompleted) {
        onTimeout();
        completer.complete(<Opportunity>[]);
      }
    });

    return completer.future;
  }

  // MARK: Flights

  Future<List<Opportunity>> _fetchLiveFlightOpportunities({
    required LatLng coordinate,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    if (!_flightArrivalsService.isConfigured) {
      _flights.state = FeedState.notConfigured;
      return [];
    }

    final nearbyAirports =
        await _nearbyAirportService.fetchNearbyAirports(coordinate);
    if (nearbyAirports.isEmpty) {
      _flights.state = FeedState.noNearbySources;
      return [];
    }

    try {
      final liveFlightOpportunities =
          await _flightArrivalsService.fetchArrivalOpportunities(
        coordinate: coordinate,
        airports: nearbyAirports,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      _flights.state = liveFlightOpportunities.isEmpty
          ? FeedState.noData
          : FeedState.loaded(liveFlightOpportunities.length);
      return liveFlightOpportunities;
    } on FlightArrivalsServiceError catch (error) {
      _flights.state = FeedState.failed(error.message);
      return [];
    } catch (_) {
      _flights.state =
          FeedState.failed('Live flight arrivals could not be loaded right now.');
      return [];
    }
  }

  Future<List<Opportunity>> _fetchLiveFlightOpportunitiesWithTimeout({
    required LatLng coordinate,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    return _raceAgainstTimeout(
      operation: () => _fetchLiveFlightOpportunities(
        coordinate: coordinate,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      ),
      onTimeout: () {
        if (_flights.state == FeedState.loading) {
          _flights.state = FeedState.failed(
              'Flight arrivals are taking too long to respond right now.');
        }
      },
    );
  }

  // MARK: Trains

  Future<List<Opportunity>> _fetchLiveTrainOpportunities({
    required LatLng coordinate,
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    if (!_trainDeparturesService.isConfigured) {
      _trains.state = FeedState.notConfigured;
      return [];
    }

    try {
      final effectiveTrainRadius = _effectiveTrainRadiusKilometers(countryCode);
      final liveTrainOpportunities =
          await _trainDeparturesService.fetchArrivalOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        radiusKilometers: effectiveTrainRadius,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      _trains.state = liveTrainOpportunities.isEmpty
          ? FeedState.noData
          : FeedState.loaded(liveTrainOpportunities.length);
      return liveTrainOpportunities;
    } on TrainNoNearbyStationsError {
      _trains.state = FeedState.noNearbySources;
      return [];
    } on TrainDeparturesServiceError catch (error) {
      _trains.state = FeedState.failed(error.message);
      return [];
    } catch (_) {
      _trains.state =
          FeedState.failed('Train arrivals could not be loaded right now.');
      return [];
    }
  }

  Future<List<Opportunity>> _fetchLiveTrainOpportunitiesWithTimeout({
    required LatLng coordinate,
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    return _raceAgainstTimeout(
      operation: () => _fetchLiveTrainOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      ),
      onTimeout: () {
        if (_trains.state == FeedState.loading) {
          _trains.state = FeedState.failed(
              'Train arrivals are taking too long to respond right now.');
        }
      },
    );
  }

  // MARK: Events

  Future<List<Opportunity>> _fetchLiveEventOpportunities({
    required LatLng coordinate,
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final hasTicketmaster = _ticketmasterEventsService.isConfigured;
    final hasPredictHQ = _predictHQEventsService.isConfigured;

    if (!hasTicketmaster && !hasPredictHQ) {
      _events.state = FeedState.notConfigured;
      return [];
    }

    final results = await Future.wait([
      _fetchTicketmasterEventOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        timeDisplayFormat: timeDisplayFormat,
        isEnabled: hasTicketmaster,
        windowStart: windowStart,
        windowEnd: windowEnd,
      ),
      _fetchPredictHQConventionOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        timeDisplayFormat: timeDisplayFormat,
        isEnabled: hasPredictHQ,
        windowStart: windowStart,
        windowEnd: windowEnd,
      ),
    ]);

    final ticketmasterResponse = results[0];
    final predictHQResponse = results[1];
    final combined = _cappedOpportunities([
      ...ticketmasterResponse.opportunities,
      ...predictHQResponse.opportunities,
    ])
      ..sort(_sourceSortComparator);

    if (combined.isNotEmpty) {
      _events.state = FeedState.loaded(combined.length);
      return combined;
    }

    final failures = [
      ticketmasterResponse.errorMessage,
      predictHQResponse.errorMessage,
    ].whereType<String>().toList();
    final enabledCount = (hasTicketmaster ? 1 : 0) + (hasPredictHQ ? 1 : 0);
    if (failures.isNotEmpty && failures.length == enabledCount) {
      _events.state = FeedState.failed(failures.first);
      return [];
    }

    _events.state = FeedState.noData;
    return [];
  }

  Future<List<Opportunity>> _fetchLiveEventOpportunitiesWithTimeout({
    required LatLng coordinate,
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    return _raceAgainstTimeout(
      operation: () => _fetchLiveEventOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      ),
      onTimeout: () {
        if (_events.state == FeedState.loading) {
          _events.state = FeedState.failed(
              'Events are taking too long to respond right now.');
        }
      },
    );
  }

  Future<({List<Opportunity> opportunities, String? errorMessage})>
      _fetchTicketmasterEventOpportunities({
    required LatLng coordinate,
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
    required bool isEnabled,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    if (!isEnabled) {
      return (opportunities: <Opportunity>[], errorMessage: null);
    }

    try {
      final opportunities =
          await _ticketmasterEventsService.fetchEventOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        radiusKilometers: 50,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      return (opportunities: opportunities, errorMessage: null);
    } on TicketmasterServiceError catch (error) {
      return (opportunities: <Opportunity>[], errorMessage: error.message);
    } catch (_) {
      return (
        opportunities: <Opportunity>[],
        errorMessage: 'Ticketmaster events could not be loaded right now.',
      );
    }
  }

  Future<({List<Opportunity> opportunities, String? errorMessage})>
      _fetchPredictHQConventionOpportunities({
    required LatLng coordinate,
    String? countryCode,
    required TimeDisplayFormat timeDisplayFormat,
    required bool isEnabled,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    if (!isEnabled) {
      return (opportunities: <Opportunity>[], errorMessage: null);
    }

    try {
      final opportunities =
          await _predictHQEventsService.fetchConventionOpportunities(
        coordinate: coordinate,
        countryCode: countryCode,
        radiusKilometers: 75,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );
      return (opportunities: opportunities, errorMessage: null);
    } on PredictHQServiceError catch (error) {
      return (opportunities: <Opportunity>[], errorMessage: error.message);
    } catch (_) {
      return (
        opportunities: <Opportunity>[],
        errorMessage: 'Convention and expo events could not be loaded right now.',
      );
    }
  }

  // MARK: Lifestyle

  Future<List<Opportunity>> _fetchLiveLifestyleOpportunities({
    required LatLng coordinate,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    try {
      final opportunities = await _lifestyleSpotsService.fetchOfficeOpportunities(
        coordinate: coordinate,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      );

      _lifestyle.state = opportunities.isEmpty
          ? FeedState.noData
          : FeedState.loaded(opportunities.length);
      return opportunities;
    } catch (_) {
      _lifestyle.state =
          FeedState.failed('Lifestyle spots could not be loaded right now.');
      return [];
    }
  }

  Future<List<Opportunity>> _fetchLiveLifestyleOpportunitiesWithTimeout({
    required LatLng coordinate,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    return _raceAgainstTimeout(
      operation: () => _fetchLiveLifestyleOpportunities(
        coordinate: coordinate,
        timeDisplayFormat: timeDisplayFormat,
        windowStart: windowStart,
        windowEnd: windowEnd,
      ),
      onTimeout: () {
        if (_lifestyle.state == FeedState.loading) {
          _lifestyle.state = FeedState.failed(
              'Lifestyle spots are taking too long to respond right now.');
        }
      },
    );
  }

  double _effectiveTrainRadiusKilometers(String? countryCode) {
    switch (countryCode?.toUpperCase()) {
      case 'GB':
        return 10;
      default:
        return 30;
    }
  }
}
