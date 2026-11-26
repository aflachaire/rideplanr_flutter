import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/app_config.dart';
import '../models/app_models.dart';
import 'nearby_airport_service.dart';
import 'service_utilities.dart';

class FlightArrivalsServiceError implements Exception {
  FlightArrivalsServiceError.missingAPIKey()
      : message =
            'Add your flight API key in the build settings to load live flight arrivals.';

  FlightArrivalsServiceError.api(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Port of the iOS `FlightArrivalsService` (AeroDataBox via RapidAPI).
/// The Aviationstack provider is intentionally disabled, like on iOS.
class FlightArrivalsService {
  FlightArrivalsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  bool get isConfigured => AppConfig.aeroDataBoxAPIKey.isNotEmpty;

  Future<List<Opportunity>> fetchArrivalOpportunities({
    required LatLng coordinate,
    required List<NearbyAirport> airports,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    DateTime? windowEnd,
  }) async {
    if (!isConfigured) {
      throw FlightArrivalsServiceError.missingAPIKey();
    }

    final resolvedWindowEnd =
        windowEnd ?? windowStart.add(const Duration(hours: 12));

    final prioritizedAirports = [...airports]..sort((lhs, rhs) {
        final lhsPriority = _airportPriorityScore(lhs);
        final rhsPriority = _airportPriorityScore(rhs);
        if (lhsPriority == rhsPriority) {
          return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
        }
        return rhsPriority.compareTo(lhsPriority);
      });

    final opportunities = <Opportunity>[];
    FlightArrivalsServiceError? firstError;

    for (final airport in prioritizedAirports.take(3)) {
      try {
        final airportOpportunities = await _fetchAeroDataBoxArrivalOpportunities(
          airport: airport,
          userCoordinate: coordinate,
          timeDisplayFormat: timeDisplayFormat,
          windowStart: windowStart,
          windowEnd: resolvedWindowEnd,
        );
        opportunities.addAll(airportOpportunities);

        if (opportunities.isNotEmpty) {
          break;
        }
      } on FlightArrivalsServiceError catch (error) {
        firstError ??= error;
      } catch (_) {
        firstError ??= FlightArrivalsServiceError.api(
            'Live flight arrivals could not be loaded right now.');
      }
    }

    if (opportunities.isEmpty && firstError != null) {
      throw firstError;
    }

    opportunities.sort((lhs, rhs) {
      if (lhs.score == rhs.score) {
        return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
      }
      return rhs.score.compareTo(lhs.score);
    });
    return opportunities;
  }

  Future<List<Opportunity>> _fetchAeroDataBoxArrivalOpportunities({
    required NearbyAirport airport,
    required LatLng userCoordinate,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    required DateTime windowEnd,
  }) async {
    final apiKey = AppConfig.aeroDataBoxAPIKey;
    if (apiKey.isEmpty) {
      return [];
    }

    // The iOS app resolves the airport's timezone via reverse geocoding.
    // Airports are within 50 km of the user, so the device timezone is the
    // same in practice; use the device-local representation here.
    final fromLocal = _localRangeString(windowStart.toLocal());
    final toLocal = _localRangeString(windowEnd.toLocal());

    final codeType = airport.icaoCode == null ? 'iata' : 'icao';
    final code = airport.icaoCode ?? airport.iataCode;

    final url = Uri.https(
      'aerodatabox.p.rapidapi.com',
      '/flights/airports/$codeType/$code/$fromLocal/$toLocal',
      {
        'direction': 'Arrival',
        'withLeg': 'false',
        'withCancelled': 'false',
        'withCodeshared': 'true',
        'withCargo': 'false',
        'withPrivate': 'false',
      },
    );

    final response = await _client.get(url, headers: {
      'X-RapidAPI-Key': apiKey,
      'X-RapidAPI-Host': 'aerodatabox.p.rapidapi.com',
      'Accept': 'application/json',
    });

    if (response.statusCode < 200 || response.statusCode > 299) {
      throw FlightArrivalsServiceError.api(
          'AeroDataBox fallback request failed with status ${response.statusCode}.');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final flights = (payload['arrivals'] as List?) ?? const [];
    final arrivals = _relevantArrivals(
      flights,
      windowStart: windowStart,
      windowEnd: windowEnd,
    );
    final arrivalWindows = groupedArrivalWindows(arrivals);
    if (arrivalWindows.isEmpty) {
      return [];
    }

    final distanceKilometers =
        distanceKilometersBetween(userCoordinate, airport.coordinate);
    final driveTimeMinutes =
        (distanceKilometers / 55 * 60).round().clamp(8, 1 << 31).toInt();

    return arrivalWindows.map((window) {
      final startsInMinutes =
          (window.start.difference(DateTime.now()).inSeconds ~/ 60)
              .clamp(0, 1 << 31).toInt();
      final arrivalCount = window.arrivals.length;
      final potentialCustomers = (arrivalCount * 2).clamp(4, 18).toInt();
      final proximityBoost =
          (22 - (distanceKilometers ~/ 4)).clamp(0, 1 << 31).toInt();
      final score = (42 + (arrivalCount * 8) + proximityBoost).clamp(0, 96).toInt();
      final startText = timeDisplayFormat.compactTimeString(window.start);
      final endText = timeDisplayFormat.compactTimeString(window.end);
      final pluralizedAircraft = arrivalCount == 1 ? 'airplane' : 'airplanes';
      final pluralizedArrival = arrivalCount == 1 ? 'arrival' : 'arrivals';
      final windowIdentifier = windowID(window.start);

      return Opportunity(
        id: 'live-flight-aerodatabox-${airport.iataCode.toLowerCase()}-$windowIdentifier',
        title: airport.name,
        subtitle:
            '$arrivalCount $pluralizedAircraft landing from $startText to $endText',
        zoneName: airport.iataCode,
        latitude: airport.coordinate.latitude,
        longitude: airport.coordinate.longitude,
        startsInMinutes: startsInMinutes,
        distanceKilometers: distanceKilometers,
        driveTimeMinutes: driveTimeMinutes,
        potentialCustomers: potentialCustomers,
        score: score,
        categories: const [SignalCategory.flights],
        recommendation:
            'Strong $pluralizedArrival flow expected near ${airport.iataCode}.',
        detail:
            'AeroDataBox fallback arrivals show a focused 1-hour wave for ${airport.iataCode} from $startText to $endText, with $arrivalCount flights expected in that window.',
      );
    }).toList();
  }

  String _localRangeString(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    final hh = date.hour.toString().padLeft(2, '0');
    final min = date.minute.toString().padLeft(2, '0');
    return '${date.year}-$mm-${dd}T$hh:$min';
  }

  List<DateTime> _relevantArrivals(
    List flights, {
    required DateTime windowStart,
    required DateTime windowEnd,
  }) {
    final arrivals = <DateTime>[];

    for (final raw in flights) {
      final flight = raw as Map<String, dynamic>;
      final status = ((flight['status'] as String?) ?? '').toLowerCase();
      if (const ['canceled', 'cancelled', 'diverted', 'canceleduncertain']
          .contains(status)) {
        continue;
      }

      final movement = (flight['movement'] as Map?)?.cast<String, dynamic>();
      if (movement == null) continue;

      String? utc(String key) =>
          ((movement[key] as Map?)?.cast<String, dynamic>())?['utc'] as String?;

      final dateString = utc('revisedTime') ??
          utc('runwayTime') ??
          utc('predictedTime') ??
          utc('scheduledTime');

      if (dateString == null) continue;
      final date = parseFlexibleDate(dateString);
      if (date == null) continue;

      if (date.isBefore(windowStart) || date.isAfter(windowEnd)) continue;

      arrivals.add(date);
    }

    arrivals.sort();
    return arrivals;
  }

  int _airportPriorityScore(NearbyAirport airport) {
    final normalizedName = airport.name.toLowerCase();
    var score = 0;

    if (normalizedName.contains('international')) {
      score += 40;
    }

    if (normalizedName.contains('fields') ||
        normalizedName.contains('municipal')) {
      score -= 30;
    }

    if (airport.iataCode.length == 3) {
      score += 10;
    }

    if (airport.distanceKilometers <= 35) {
      score += 12;
    }

    return score;
  }
}
