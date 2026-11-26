import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/app_models.dart';
import 'service_utilities.dart';

class TicketmasterServiceError implements Exception {
  TicketmasterServiceError.missingAPIKey()
      : message = 'Add your Ticketmaster API key to load live events.';

  TicketmasterServiceError.api(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _VenueScale { small, medium, large }

/// Port of the iOS `TicketmasterEventsService` (Discovery v2).
class TicketmasterEventsService {
  TicketmasterEventsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  bool get isConfigured => AppConfig.ticketmasterAPIKey.isNotEmpty;

  Future<List<Opportunity>> fetchEventOpportunities({
    required LatLng coordinate,
    String? countryCode,
    double radiusKilometers = 50,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    DateTime? windowEnd,
  }) async {
    final apiKey = AppConfig.ticketmasterAPIKey;
    if (apiKey.isEmpty) {
      throw TicketmasterServiceError.missingAPIKey();
    }

    final now = DateTime.now();
    var searchStartWindow = windowStart.subtract(const Duration(hours: 8));
    if (searchStartWindow.isBefore(now)) {
      searchStartWindow = now;
    }
    final visibleWindowEnd =
        windowEnd ?? windowStart.add(const Duration(hours: 12));

    var events = await _fetchEventsPayload(
      coordinate: coordinate,
      radiusKilometers: radiusKilometers,
      countryCode: countryCode,
      startWindow: searchStartWindow,
      endWindow: visibleWindowEnd,
      apiKey: apiKey,
    );

    if (events.isEmpty && countryCode != null) {
      events = await _fetchEventsPayload(
        coordinate: coordinate,
        radiusKilometers: radiusKilometers,
        countryCode: null,
        startWindow: searchStartWindow,
        endWindow: visibleWindowEnd,
        apiKey: apiKey,
      );
    }

    final opportunities = events
        .map((event) => _buildOpportunity(
              event: event,
              userCoordinate: coordinate,
              timeDisplayFormat: timeDisplayFormat,
              visibleWindowStart: windowStart,
              visibleWindowEnd: visibleWindowEnd,
            ))
        .whereType<Opportunity>()
        .toList();

    opportunities.sort((lhs, rhs) {
      if (lhs.startsInMinutes == rhs.startsInMinutes) {
        if (lhs.score == rhs.score) {
          return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
        }
        return rhs.score.compareTo(lhs.score);
      }

      return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
    });
    return opportunities;
  }

  Future<List<Map<String, dynamic>>> _fetchEventsPayload({
    required LatLng coordinate,
    required double radiusKilometers,
    String? countryCode,
    required DateTime startWindow,
    required DateTime endWindow,
    required String apiKey,
  }) async {
    final queryParameters = {
      'apikey': apiKey,
      'latlong': '${coordinate.latitude},${coordinate.longitude}',
      'radius': '${radiusKilometers.toInt()}',
      'unit': 'km',
      'startDateTime': _apiDateString(startWindow),
      'endDateTime': _apiDateString(endWindow),
      'size': '40',
      'sort': 'date,asc',
      'includeTBA': 'no',
      'includeTest': 'no',
    };

    final trimmedCountry = countryCode?.trim();
    if (trimmedCountry != null && trimmedCountry.isNotEmpty) {
      queryParameters['countryCode'] = trimmedCountry.toUpperCase();
    }

    final url = Uri.parse('https://app.ticketmaster.com/discovery/v2/events.json')
        .replace(queryParameters: queryParameters);

    final response = await _client.get(url);
    final payload = jsonDecode(response.body) as Map<String, dynamic>;

    final errors = (payload['errors'] as List?)?.cast<Map>();
    if (errors != null && errors.isNotEmpty) {
      final firstError = errors.first.cast<String, dynamic>();
      throw TicketmasterServiceError.api(
        (firstError['detail'] as String?) ??
            (firstError['title'] as String?) ??
            'Ticketmaster event lookup failed.',
      );
    }

    final embedded = (payload['_embedded'] as Map?)?.cast<String, dynamic>();
    return ((embedded?['events'] as List?) ?? const [])
        .map((event) => (event as Map).cast<String, dynamic>())
        .toList();
  }

  Opportunity? _buildOpportunity({
    required Map<String, dynamic> event,
    required LatLng userCoordinate,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime visibleWindowStart,
    required DateTime visibleWindowEnd,
  }) {
    if (!_isSupportedEvent(event)) {
      return null;
    }

    final embedded = (event['_embedded'] as Map?)?.cast<String, dynamic>();
    final venues = (embedded?['venues'] as List?)?.cast<Map>() ?? const [];
    if (venues.isEmpty) return null;

    final venue = venues.first.cast<String, dynamic>();
    final venueLocation = (venue['location'] as Map?)?.cast<String, dynamic>();
    final latitude = double.tryParse('${venueLocation?['latitude']}');
    final longitude = double.tryParse('${venueLocation?['longitude']}');
    if (latitude == null || longitude == null) return null;

    final dates = (event['dates'] as Map?)?.cast<String, dynamic>() ?? const {};
    final statusCode =
        ((((dates['status'] as Map?)?.cast<String, dynamic>())?['code'])
                    as String? ??
                '')
            .toLowerCase();
    if (const ['cancelled', 'canceled', 'postponed'].contains(statusCode)) {
      return null;
    }

    final finishInfo = _resolvedFinishInfo(event);
    if (finishInfo == null) return null;

    if (finishInfo.date.isBefore(visibleWindowStart) ||
        finishInfo.date.isAfter(visibleWindowEnd)) {
      return null;
    }

    final venueCoordinate = LatLng(latitude, longitude);
    final distanceKilometers =
        distanceKilometersBetween(userCoordinate, venueCoordinate);
    final driveTimeMinutes =
        (distanceKilometers / 35 * 60).round().clamp(6, 1 << 31).toInt();
    final startsInMinutes =
        (finishInfo.date.difference(DateTime.now()).inSeconds ~/ 60)
            .clamp(0, 1 << 31).toInt();
    final eventTypeBoost = _eventTypeBoost(event);
    final eventSizeBoost = _eventSizeBoost(event, venue);
    final proximityBoost = (18 - (distanceKilometers ~/ 3)).clamp(0, 1 << 31).toInt();
    final urgencyBoost = (20 - startsInMinutes ~/ 15).clamp(0, 1 << 31).toInt();
    final score = (48 + eventTypeBoost + eventSizeBoost ~/ 2 + proximityBoost + urgencyBoost)
        .clamp(0, 94).toInt();
    final potentialCustomers = _estimatedPotentialCustomers(
      eventTypeBoost: eventTypeBoost,
      eventSizeBoost: eventSizeBoost,
      proximityBoost: proximityBoost,
    );
    final finishLabel = timeDisplayFormat.compactTimeString(finishInfo.date);
    final eventName = ((event['name'] as String?) ?? '').trim();
    final subtitlePrefix = finishInfo.isEstimated ? 'ending around' : 'ending at';
    final detailPrefix =
        finishInfo.isEstimated ? 'Estimated finish' : 'Scheduled finish';
    final venueName = (venue['name'] as String?) ?? 'Venue';
    final cityName =
        (((venue['city'] as Map?)?.cast<String, dynamic>())?['name'] as String?);
    final areaName = cityName ?? venueName;

    return Opportunity(
      id: 'live-event-${event['id']}',
      title: venueName,
      subtitle: '$eventName $subtitlePrefix $finishLabel',
      zoneName: areaName,
      latitude: latitude,
      longitude: longitude,
      startsInMinutes: startsInMinutes,
      distanceKilometers: distanceKilometers,
      driveTimeMinutes: driveTimeMinutes,
      potentialCustomers: potentialCustomers,
      score: score,
      categories: const [SignalCategory.events],
      recommendation: 'Position near $venueName before the crowd release.',
      detail:
          '$detailPrefix: $finishLabel. $eventName is expected to release riders around $venueName, with demand likely building near exits and pickup zones.',
    );
  }

  ({DateTime date, bool isEstimated})? _resolvedFinishInfo(
      Map<String, dynamic> event) {
    final dates = (event['dates'] as Map?)?.cast<String, dynamic>() ?? const {};
    final start = (dates['start'] as Map?)?.cast<String, dynamic>() ?? const {};
    final end = (dates['end'] as Map?)?.cast<String, dynamic>();

    final startDate = _resolvedDate(
      dateTime: start['dateTime'] as String?,
      localDate: start['localDate'] as String?,
      localTime: _localTimeString(start['localTime']),
      fallbackDate: null,
    );

    if (end != null) {
      final explicitEnd = _resolvedDate(
        dateTime: end['dateTime'] as String?,
        localDate: (end['localDate'] as String?) ?? start['localDate'] as String?,
        localTime: _localTimeString(end['localTime']),
        fallbackDate: startDate,
      );
      if (explicitEnd != null) {
        return (date: explicitEnd, isEstimated: (end['approximate'] as bool?) ?? false);
      }
    }

    if (startDate == null) {
      return null;
    }

    return (
      date: startDate.add(_estimatedDuration(event)),
      isEstimated: true,
    );
  }

  String? _localTimeString(Object? localTime) {
    if (localTime is String) return localTime;

    if (localTime is Map) {
      final components = localTime.cast<String, dynamic>();
      final hour = components['hourOfDay'] as int?;
      final minute = components['minuteOfHour'] as int?;
      if (hour != null && minute != null) {
        return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00';
      }
    }

    return null;
  }

  DateTime? _resolvedDate({
    String? dateTime,
    String? localDate,
    String? localTime,
    DateTime? fallbackDate,
  }) {
    if (dateTime != null) {
      final parsed = DateTime.tryParse(dateTime);
      if (parsed != null) return parsed;
    }

    if (localDate == null) {
      return fallbackDate;
    }

    // The iOS app resolves the event's timezone; here the event venue is near
    // the user, so local device time is used as the practical equivalent.
    final timeValue = localTime ?? '20:00:00';
    return DateTime.tryParse('$localDate $timeValue') ?? fallbackDate;
  }

  Duration _estimatedDuration(Map<String, dynamic> event) =>
      const Duration(hours: 1);

  String _combinedClassificationText(Map<String, dynamic> event) {
    final classifications =
        (event['classifications'] as List?)?.cast<Map>() ?? const [];
    final first = classifications.isEmpty
        ? const <String, dynamic>{}
        : classifications.first.cast<String, dynamic>();

    String nameOf(String key) =>
        (((first[key] as Map?)?.cast<String, dynamic>())?['name'] as String?) ??
        '';

    return [
      (event['name'] as String?) ?? '',
      nameOf('segment'),
      nameOf('genre'),
      nameOf('subGenre'),
    ].join(' ').toLowerCase();
  }

  bool _isSupportedEvent(Map<String, dynamic> event) {
    final combinedText = _combinedClassificationText(event);

    if (const ['parking', 'package', 'vip', 'hotel']
        .any(combinedText.contains)) {
      return false;
    }

    if (combinedText.contains('festival') || combinedText.contains('concert')) {
      return true;
    }

    const supportedSegments = ['music', 'sports', 'arts & theatre'];
    return supportedSegments.contains(_primarySegmentName(event).toLowerCase());
  }

  String _primarySegmentName(Map<String, dynamic> event) {
    final classifications =
        (event['classifications'] as List?)?.cast<Map>() ?? const [];
    if (classifications.isEmpty) return 'Events';
    final first = classifications.first.cast<String, dynamic>();
    return (((first['segment'] as Map?)?.cast<String, dynamic>())?['name']
            as String?) ??
        'Events';
  }

  int _eventTypeBoost(Map<String, dynamic> event) {
    final combinedText = _combinedClassificationText(event);

    if (combinedText.contains('festival')) {
      return 24;
    }

    switch (_primarySegmentName(event).toLowerCase()) {
      case 'sports':
        return 22;
      case 'music':
        return 18;
      case 'arts & theatre':
        return 14;
      default:
        return 12;
    }
  }

  int _eventSizeBoost(Map<String, dynamic> event, Map<String, dynamic> venue) {
    final combinedEventText = _combinedClassificationText(event);

    var boost = 0;

    if (combinedEventText.contains('festival')) {
      boost += 14;
    }

    switch (_venueScale(((venue['name'] as String?) ?? '').toLowerCase())) {
      case _VenueScale.large:
        boost += 12;
      case _VenueScale.medium:
        boost += 7;
      case _VenueScale.small:
        boost += 2;
    }

    int? upcomingEventsCount(Map<String, dynamic>? container) {
      final upcoming =
          (container?['upcomingEvents'] as Map?)?.cast<String, dynamic>();
      return (upcoming?['_total'] as int?) ?? (upcoming?['ticketmaster'] as int?);
    }

    final venueEventCount = upcomingEventsCount(venue);
    if (venueEventCount != null) {
      if (venueEventCount >= 20) {
        boost += 8;
      } else if (venueEventCount >= 8) {
        boost += 4;
      }
    }

    final embedded = (event['_embedded'] as Map?)?.cast<String, dynamic>();
    final attractions =
        (embedded?['attractions'] as List?)?.cast<Map>() ?? const [];
    if (attractions.length >= 3) {
      boost += 8;
    } else if (attractions.length == 2) {
      boost += 4;
    }

    var attractionDemand = 0;
    for (final attraction in attractions) {
      final count = upcomingEventsCount(attraction.cast<String, dynamic>()) ?? 0;
      if (count > attractionDemand) attractionDemand = count;
    }

    if (attractionDemand >= 25) {
      boost += 8;
    } else if (attractionDemand >= 10) {
      boost += 5;
    } else if (attractionDemand >= 4) {
      boost += 2;
    }

    return boost;
  }

  int _estimatedPotentialCustomers({
    required int eventTypeBoost,
    required int eventSizeBoost,
    required int proximityBoost,
  }) {
    final blendedScore = eventTypeBoost + eventSizeBoost + (proximityBoost ~/ 2);

    if (blendedScore >= 38) return 18;
    if (blendedScore >= 28) return 14;
    if (blendedScore >= 18) return 10;
    return 6;
  }

  _VenueScale _venueScale(String name) {
    if (const ['stadium', 'arena', 'park', 'racecourse', 'hippodrome', 'oval']
        .any(name.contains)) {
      return _VenueScale.large;
    }

    if (const ['hall', 'forum', 'center', 'centre', 'palace', 'grounds']
        .any(name.contains)) {
      return _VenueScale.medium;
    }

    return _VenueScale.small;
  }

  String _apiDateString(DateTime date) {
    final utc = date.toUtc();
    final mm = utc.month.toString().padLeft(2, '0');
    final dd = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    return '${utc.year}-$mm-${dd}T$hh:$min:${ss}Z';
  }
}
