import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/app_models.dart';
import 'service_utilities.dart';

class NearbyTrainStation {
  const NearbyTrainStation({
    required this.id,
    required this.name,
    required this.coordinate,
    required this.distanceKilometers,
  });

  final String id;
  final String name;
  final LatLng coordinate;
  final double distanceKilometers;
}

sealed class TrainDeparturesServiceError implements Exception {
  String get message;

  @override
  String toString() => message;
}

class TrainMissingAPIKeyError extends TrainDeparturesServiceError {
  @override
  String get message => 'Add your Transitland API key to load train arrivals.';
}

class TrainNoNearbyStationsError extends TrainDeparturesServiceError {
  @override
  String get message => 'No train stations found within 30 km of your location.';
}

class TrainAPIError extends TrainDeparturesServiceError {
  TrainAPIError(this.message);

  @override
  final String message;
}

/// Port of the iOS `TrainDeparturesService` (Transitland REST v2).
class TrainDeparturesService {
  TrainDeparturesService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;
  static const int _maxStationsToQuery = 8;

  static const List<String> _excludedUrbanRailKeywords = [
    'dlr',
    'underground',
    'tube',
    'tram',
    'metro',
  ];

  bool get isConfigured => AppConfig.transitlandAPIKey.isNotEmpty;

  Future<List<Opportunity>> fetchArrivalOpportunities({
    required LatLng coordinate,
    String? countryCode,
    double radiusKilometers = 30,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    DateTime? windowEnd,
  }) async {
    final apiKey = AppConfig.transitlandAPIKey;
    if (apiKey.isEmpty) {
      throw TrainMissingAPIKeyError();
    }

    final resolvedWindowEnd =
        windowEnd ?? windowStart.add(const Duration(hours: 12));

    final stations = await _fetchNearbyStations(
      coordinate,
      radiusKilometers: radiusKilometers,
      countryCode: countryCode,
      apiKey: apiKey,
    );

    if (stations.isEmpty) {
      throw TrainNoNearbyStationsError();
    }

    final opportunities = <Opportunity>[];
    TrainDeparturesServiceError? firstError;

    final results = await Future.wait(
      stations.take(_maxStationsToQuery).map((station) async {
        try {
          return await _fetchStationArrivalOpportunities(
            station: station,
            userCoordinate: coordinate,
            apiKey: apiKey,
            timeDisplayFormat: timeDisplayFormat,
            windowStart: windowStart,
            windowEnd: resolvedWindowEnd,
          );
        } on TrainDeparturesServiceError catch (error) {
          firstError ??= error;
          return <Opportunity>[];
        } catch (_) {
          firstError ??=
              TrainAPIError('Train arrivals could not be loaded right now.');
          return <Opportunity>[];
        }
      }),
    );

    for (final stationOpportunities in results) {
      opportunities.addAll(stationOpportunities);
    }

    if (opportunities.isEmpty && firstError != null) {
      throw firstError!;
    }

    opportunities.sort((lhs, rhs) {
      if (lhs.score == rhs.score) {
        return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
      }
      return rhs.score.compareTo(lhs.score);
    });
    return opportunities;
  }

  Future<List<NearbyTrainStation>> _fetchNearbyStations(
    LatLng coordinate, {
    required double radiusKilometers,
    String? countryCode,
    required String apiKey,
  }) async {
    final bbox = boundingBoxAround(coordinate, radiusKilometers);
    final url = Uri.parse('https://transit.land/api/v2/rest/stops').replace(
      queryParameters: {
        'apikey': apiKey,
        'bbox':
            '${bbox.minLongitude},${bbox.minLatitude},${bbox.maxLongitude},${bbox.maxLatitude}',
        'served_by_route_type': '2',
        'limit': '150',
      },
    );

    final response = await _client.get(url);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final metaError =
        ((payload['meta'] as Map?)?.cast<String, dynamic>())?['error'];
    if (metaError is String) {
      throw TrainAPIError(metaError);
    }

    final stops = (payload['stops'] as List?) ?? const [];
    final stationsByName = <String, _StationCandidate>{};

    for (final raw in stops) {
      final stop = raw as Map<String, dynamic>;
      final geometry = (stop['geometry'] as Map?)?.cast<String, dynamic>();
      final coordinates =
          (geometry?['coordinates'] as List?)?.cast<num>() ?? const [];
      if (coordinates.length < 2) continue;

      final stopID = (stop['stop_id'] as String?)?.toLowerCase();
      if (stopID != null && stopID.contains('car')) continue;

      final stopName = (stop['stop_name'] as String?) ?? '';
      final normalizedName = stopName.toLowerCase();
      if (_excludedUrbanRailKeywords
          .any((keyword) => normalizedName.contains(keyword))) {
        continue;
      }

      final longitude = coordinates[0].toDouble();
      final latitude = coordinates[1].toDouble();
      final stationCoordinate = LatLng(latitude, longitude);
      final distanceKilometers =
          distanceKilometersBetween(coordinate, stationCoordinate);

      if (distanceKilometers > radiusKilometers) continue;

      if (countryCode != null) {
        final stopCountryCode =
            (((stop['place'] as Map?)?.cast<String, dynamic>())?['adm0_iso']
                    as String?)
                ?.toUpperCase();
        if (stopCountryCode != null &&
            stopCountryCode != countryCode.toUpperCase()) {
          continue;
        }
      }

      final station = NearbyTrainStation(
        id: '${stop['id']}',
        name: stopName,
        coordinate: stationCoordinate,
        distanceKilometers: distanceKilometers,
      );
      final locationType = stop['location_type'] as int?;

      final dedupeKey = stopName.toLowerCase();
      final existing = stationsByName[dedupeKey];
      if (existing == null ||
          _shouldReplace(existing.station, station, locationType)) {
        stationsByName[dedupeKey] =
            _StationCandidate(station: station, locationType: locationType);
      }
    }

    final stations = stationsByName.values.map((c) => c.station).toList()
      ..sort((lhs, rhs) {
        final lhsPreferred = _isPreferredRailHubName(lhs.name);
        final rhsPreferred = _isPreferredRailHubName(rhs.name);

        if (lhsPreferred != rhsPreferred) {
          return lhsPreferred ? -1 : 1;
        }

        return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
      });

    return stations;
  }

  Future<List<Opportunity>> _fetchStationArrivalOpportunities({
    required NearbyTrainStation station,
    required LatLng userCoordinate,
    required String apiKey,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final nextSeconds =
        windowEnd.difference(DateTime.now()).inSeconds.clamp(60, 1 << 31).toInt();

    final url = Uri.parse(
            'https://transit.land/api/v2/rest/stops/${station.id}/departures')
        .replace(queryParameters: {
      'apikey': apiKey,
      'next': '$nextSeconds',
      'limit': '10',
    });

    final response = await _client.get(url);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final metaError =
        ((payload['meta'] as Map?)?.cast<String, dynamic>())?['error'];
    if (metaError is String) {
      throw TrainAPIError(metaError);
    }

    final stops = (payload['stops'] as List?) ?? const [];
    if (stops.isEmpty) return [];

    final stop = (stops.first as Map).cast<String, dynamic>();
    final departures = (stop['departures'] as List?) ?? const [];

    final arrivals = _relevantArrivals(
      departures,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );

    final arrivalWindows = groupedArrivalWindows(arrivals);
    if (arrivalWindows.isEmpty) return [];

    final distanceKilometers =
        distanceKilometersBetween(userCoordinate, station.coordinate);
    final driveTimeMinutes =
        (distanceKilometers / 40 * 60).round().clamp(6, 1 << 31).toInt();

    return arrivalWindows.map((window) {
      final startsInMinutes =
          (window.start.difference(DateTime.now()).inSeconds ~/ 60)
              .clamp(0, 1 << 31).toInt();
      final arrivalCount = window.arrivals.length;
      final potentialCustomers = (arrivalCount * 2).clamp(3, 16).toInt();
      final proximityBoost = (18 - (distanceKilometers ~/ 3)).clamp(0, 1 << 31).toInt();
      final score = (42 + (arrivalCount * 6) + proximityBoost).clamp(0, 90).toInt();
      final startText = timeDisplayFormat.compactTimeString(window.start);
      final endText = timeDisplayFormat.compactTimeString(window.end);
      final pluralizedArrival = arrivalCount == 1 ? 'arrival' : 'arrivals';
      final windowIdentifier = windowID(window.start);

      return Opportunity(
        id: 'live-train-${station.id}-$windowIdentifier',
        title: station.name,
        subtitle:
            '$arrivalCount train $pluralizedArrival from $startText to $endText',
        zoneName: station.name,
        latitude: station.coordinate.latitude,
        longitude: station.coordinate.longitude,
        startsInMinutes: startsInMinutes,
        distanceKilometers: distanceKilometers,
        driveTimeMinutes: driveTimeMinutes,
        potentialCustomers: potentialCustomers,
        score: score,
        categories: const [SignalCategory.trains],
        recommendation:
            'Steady rail arrivals expected around ${station.name}.',
        detail:
            'Transitland arrivals show a focused 1-hour wave around ${station.name} from $startText to $endText, with $arrivalCount upcoming rail arrivals in that window.',
      );
    }).toList();
  }

  List<DateTime> _relevantArrivals(
    List departures, {
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final arrivals = <DateTime>[];

    for (final raw in departures) {
      final departure = (raw as Map).cast<String, dynamic>();
      final date = _resolvedDate(departure);
      if (date == null) continue;

      if (date.isBefore(windowStart) || date.isAfter(windowEnd)) continue;

      final scheduleRelationship =
          ((departure['schedule_relationship'] as String?) ?? 'STATIC')
              .toUpperCase();
      if (scheduleRelationship == 'CANCELED' ||
          scheduleRelationship == 'DELETED') {
        continue;
      }

      arrivals.add(date);
    }

    arrivals.sort();
    return arrivals;
  }

  DateTime? _resolvedDate(Map<String, dynamic> departure) {
    DateTime? fromStopTimeEvent(String key) {
      final event = (departure[key] as Map?)?.cast<String, dynamic>();
      if (event == null) return null;
      final estimated = (event['estimated_time'] ?? event['scheduled_time']);
      if (estimated is! String) return null;
      return DateTime.tryParse(estimated);
    }

    final arrivalDate = fromStopTimeEvent('arrival');
    if (arrivalDate != null) return arrivalDate;

    final departureDate = fromStopTimeEvent('departure');
    if (departureDate != null) return departureDate;

    final date = departure['date'] as String?;
    final arrivalTime = departure['arrival_time'] as String?;
    final departureTime = departure['departure_time'] as String?;

    if (date != null && arrivalTime != null) {
      return _calendarDate(date: date, time: arrivalTime);
    }

    if (date == null || departureTime == null) return null;

    return _calendarDate(date: date, time: departureTime);
  }

  /// Combines a GTFS service date with a possibly >24h "HH:mm:ss" time of day.
  DateTime? _calendarDate({required String date, required String time}) {
    final parts =
        time.split(':').map(int.tryParse).whereType<int>().toList();
    if (parts.length < 2) return null;

    final baseDate = DateTime.tryParse(date);
    if (baseDate == null) return null;

    final hour = parts[0];
    var resolvedDate = DateTime(
      baseDate.year,
      baseDate.month,
      baseDate.day,
      hour % 24,
      parts[1],
      parts.length > 2 ? parts[2] : 0,
    );

    if (hour >= 24) {
      resolvedDate = resolvedDate.add(Duration(days: hour ~/ 24));
    }

    return resolvedDate;
  }

  bool _shouldReplace(
    NearbyTrainStation existing,
    NearbyTrainStation candidate,
    int? locationType,
  ) {
    if (locationType == 1) {
      return true;
    }

    return candidate.distanceKilometers < existing.distanceKilometers;
  }

  static bool _isPreferredRailHubName(String name) {
    final normalized = name.toLowerCase();
    const preferredKeywords = [
      'station',
      'international',
      "int'l",
      'london ',
      'paddington',
      'victoria',
      'waterloo',
      'euston',
      'st pancras',
      "king's cross",
      'kings cross',
      'liverpool street',
      'bridge',
    ];

    return preferredKeywords.any(normalized.contains);
  }
}

class _StationCandidate {
  const _StationCandidate({required this.station, required this.locationType});

  final NearbyTrainStation station;
  final int? locationType;
}
