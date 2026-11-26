import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/app_models.dart';
import 'service_utilities.dart';

class PredictHQServiceError implements Exception {
  PredictHQServiceError.missingAPIKey()
      : message = 'Add your PredictHQ API token to load convention and expo events.';

  PredictHQServiceError.api(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Port of the iOS `PredictHQEventsService` (conferences & expos).
class PredictHQEventsService {
  PredictHQEventsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  bool get isConfigured => AppConfig.predictHQAPIKey.isNotEmpty;

  Future<List<Opportunity>> fetchConventionOpportunities({
    required LatLng coordinate,
    String? countryCode,
    double radiusKilometers = 75,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    DateTime? windowEnd,
  }) async {
    final apiKey = AppConfig.predictHQAPIKey;
    if (apiKey.isEmpty) {
      throw PredictHQServiceError.missingAPIKey();
    }

    final resolvedWindowEnd =
        windowEnd ?? windowStart.add(const Duration(hours: 12));
    final results = await _fetchEventsPayload(
      coordinate: coordinate,
      countryCode: countryCode,
      radiusKilometers: radiusKilometers,
      activeAfter: windowStart,
      apiKey: apiKey,
    );

    final opportunities = results
        .map((event) => _buildOpportunity(
              event: event,
              userCoordinate: coordinate,
              timeDisplayFormat: timeDisplayFormat,
              visibleWindowStart: windowStart,
              visibleWindowEnd: resolvedWindowEnd,
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
    String? countryCode,
    required double radiusKilometers,
    required DateTime activeAfter,
    required String apiKey,
  }) async {
    final within =
        '${radiusKilometers.toInt()}km@${coordinate.latitude},${coordinate.longitude}';
    final queryParameters = {
      'category': 'conferences,expos',
      'within': within,
      'active.gte': _iso8601UTC(activeAfter),
      'limit': '20',
      'sort': 'rank,start',
    };

    final trimmedCountry = countryCode?.trim();
    if (trimmedCountry != null && trimmedCountry.isNotEmpty) {
      queryParameters['country'] = trimmedCountry.toUpperCase();
    }

    final url = Uri.parse('https://api.predicthq.com/v1/events/')
        .replace(queryParameters: queryParameters);

    final response = await _client.get(url, headers: {
      'Authorization': 'Bearer $apiKey',
      'Accept': 'application/json',
    });

    if (response.statusCode < 200 || response.statusCode > 299) {
      throw PredictHQServiceError.api(
          'PredictHQ event lookup failed (${response.statusCode}). ${response.body}');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    return ((payload['results'] as List?) ?? const [])
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
    final endString = event['end'] as String?;
    if (endString == null) return null;
    final endDate = DateTime.tryParse(endString);
    if (endDate == null) return null;

    if (endDate.isBefore(visibleWindowStart) ||
        endDate.isAfter(visibleWindowEnd)) {
      return null;
    }

    final location = (event['location'] as List?)?.cast<num>() ?? const [];
    if (location.length != 2) return null;

    final longitude = location[0].toDouble();
    final latitude = location[1].toDouble();
    final distanceKilometers =
        distanceKilometersBetween(userCoordinate, LatLng(latitude, longitude));
    final driveTimeMinutes =
        (distanceKilometers / 34 * 60).round().clamp(8, 1 << 31).toInt();
    final startsInMinutes =
        (endDate.difference(DateTime.now()).inSeconds ~/ 60).clamp(0, 1 << 31).toInt();

    final phqAttendance = (event['phq_attendance'] as int?) ?? 0;
    final int attendanceBoost;
    if (phqAttendance >= 20000) {
      attendanceBoost = 24;
    } else if (phqAttendance >= 8000) {
      attendanceBoost = 18;
    } else if (phqAttendance >= 2500) {
      attendanceBoost = 12;
    } else if (phqAttendance >= 800) {
      attendanceBoost = 8;
    } else {
      attendanceBoost = 4;
    }

    final localRank = (event['local_rank'] as int?) ?? 0;
    final rank = (event['rank'] as int?) ?? 0;
    final localRankBoost = (localRank ~/ 6).clamp(0, 18).toInt();
    final rankBoost = (rank ~/ 8).clamp(0, 12).toInt();
    final proximityBoost = (18 - (distanceKilometers ~/ 4)).clamp(0, 1 << 31).toInt();
    final score =
        (44 + attendanceBoost + localRankBoost + rankBoost + proximityBoost)
            .clamp(0, 96).toInt();
    final potentialCustomers = _estimatedPotentialCustomers(
      attendance: phqAttendance,
      localRank: localRank,
    );
    final finishLabel = timeDisplayFormat.compactTimeString(endDate.toLocal());
    final venueName = _preferredVenueName(event);
    final category = event['category'] as String?;
    final crowdType = category == 'expos' ? 'expo' : 'conference';
    final title = (event['title'] as String?) ?? 'Event';
    final attendanceSummary = phqAttendance > 0
        ? ' and estimated attendance of $phqAttendance'
        : '';

    return Opportunity(
      id: 'live-predicthq-${event['id']}',
      title: venueName,
      subtitle: '$title ending at $finishLabel',
      zoneName: venueName,
      latitude: latitude,
      longitude: longitude,
      startsInMinutes: startsInMinutes,
      distanceKilometers: distanceKilometers,
      driveTimeMinutes: driveTimeMinutes,
      potentialCustomers: potentialCustomers,
      score: score,
      categories: const [SignalCategory.events],
      recommendation:
          'Position near $venueName before the $crowdType crowd release.',
      detail:
          '$title is expected to release attendees around $venueName at $finishLabel. PredictHQ demand signals rate this $crowdType event with local rank $localRank$attendanceSummary.',
    );
  }

  String _preferredVenueName(Map<String, dynamic> event) {
    final entities = (event['entities'] as List?)?.cast<Map>() ?? const [];

    for (final raw in entities) {
      final entity = raw.cast<String, dynamic>();
      final type = entity['type'] as String?;
      if (type == 'venue' || type == 'event-group') {
        final name = ((entity['name'] as String?) ?? '').trim();
        if (name.isNotEmpty) return name;
      }
    }

    return (event['title'] as String?) ?? 'Event';
  }

  int _estimatedPotentialCustomers({
    required int attendance,
    required int localRank,
  }) {
    if (attendance >= 20000 || localRank >= 90) return 18;
    if (attendance >= 8000 || localRank >= 70) return 14;
    if (attendance >= 2500 || localRank >= 50) return 10;
    return 6;
  }

  String _iso8601UTC(DateTime date) {
    final utc = date.toUtc();
    final mm = utc.month.toString().padLeft(2, '0');
    final dd = utc.day.toString().padLeft(2, '0');
    final hh = utc.hour.toString().padLeft(2, '0');
    final min = utc.minute.toString().padLeft(2, '0');
    final ss = utc.second.toString().padLeft(2, '0');
    return '${utc.year}-$mm-${dd}T$hh:$min:${ss}Z';
  }
}
