import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import 'service_utilities.dart';

class NearbyAirport {
  const NearbyAirport({
    required this.id,
    required this.name,
    required this.iataCode,
    required this.icaoCode,
    required this.coordinate,
    required this.distanceKilometers,
  });

  final String id;
  final String name;
  final String iataCode;
  final String? icaoCode;
  final LatLng coordinate;
  final double distanceKilometers;
}

class _FallbackAirport {
  const _FallbackAirport(this.name, this.iataCode, this.icaoCode, this.latitude, this.longitude);

  final String name;
  final String iataCode;
  final String? icaoCode;
  final double latitude;
  final double longitude;
}

class NearbyAirportService {
  NearbyAirportService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const List<_FallbackAirport> _fallbackAirportCatalog = [
    _FallbackAirport('Biarritz Pays Basque', 'BIQ', 'LFBZ', 43.4684, -1.5311),
    _FallbackAirport('San Sebastian', 'EAS', 'LESO', 43.3565, -1.7906),
    _FallbackAirport('Pamplona', 'PNA', 'LEPP', 42.7700, -1.6463),
    _FallbackAirport('Pau Pyrenees', 'PUF', 'LFBP', 43.3800, -0.4186),
    _FallbackAirport('Bilbao', 'BIO', 'LEBB', 43.3011, -2.9106),
    _FallbackAirport('Heathrow', 'LHR', 'EGLL', 51.4700, -0.4543),
    _FallbackAirport('Gatwick', 'LGW', 'EGKK', 51.1537, -0.1821),
    _FallbackAirport('London City', 'LCY', 'EGLC', 51.5053, 0.0553),
    _FallbackAirport('Luton', 'LTN', 'EGGW', 51.8747, -0.3683),
    _FallbackAirport('Stansted', 'STN', 'EGSS', 51.8850, 0.2350),
    _FallbackAirport('Southend', 'SEN', 'EGMC', 51.5714, 0.6956),
    _FallbackAirport('Farnborough', 'FAB', 'EGLF', 51.2758, -0.7763),
    _FallbackAirport('Melbourne', 'MEL', 'YMML', -37.6690, 144.8410),
    _FallbackAirport('Essendon Fields', 'MEB', 'YMEN', -37.7281, 144.9019),
    _FallbackAirport('Avalon', 'AVV', 'YMAV', -38.0394, 144.4695),
    _FallbackAirport('Charles De Gaulle', 'CDG', 'LFPG', 49.0097, 2.5479),
    _FallbackAirport('Orly', 'ORY', 'LFPO', 48.7262, 2.3652),
    _FallbackAirport('Beauvais', 'BVA', 'LFOB', 49.4544, 2.1128),
    _FallbackAirport('Brussels', 'BRU', 'EBBR', 50.9010, 4.4844),
  ];

  Future<List<NearbyAirport>> fetchNearbyAirports(
    LatLng coordinate, {
    double radiusKilometers = 50,
    int limit = 3,
  }) async {
    final fallbackAirports = _airportsFromFallbackCatalog(
      coordinate,
      radiusKilometers: radiusKilometers,
    );

    final url = _overpassURL(coordinate, radiusKilometers: radiusKilometers);

    try {
      final response = await _client.get(url);
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final elements = (payload['elements'] as List?) ?? const [];

      final airports = <NearbyAirport>[];
      for (final raw in elements) {
        final element = raw as Map<String, dynamic>;
        final tags = (element['tags'] as Map?)?.cast<String, dynamic>();
        if (tags == null) continue;

        final iataCode = (tags['iata'] as String?)?.trim();
        final name = (tags['name'] as String?)?.trim();
        if (iataCode == null || iataCode.isEmpty || name == null || name.isEmpty) {
          continue;
        }

        if (tags.containsKey('military') || tags['aeroway'] == 'helipad') {
          continue;
        }

        final center = (element['center'] as Map?)?.cast<String, dynamic>();
        final latitude =
            (element['lat'] as num?)?.toDouble() ?? (center?['lat'] as num?)?.toDouble();
        final longitude =
            (element['lon'] as num?)?.toDouble() ?? (center?['lon'] as num?)?.toDouble();
        if (latitude == null || longitude == null) continue;

        final airportCoordinate = LatLng(latitude, longitude);
        final distanceKilometers =
            distanceKilometersBetween(coordinate, airportCoordinate);

        if (distanceKilometers > radiusKilometers) continue;

        airports.add(
          NearbyAirport(
            id: iataCode.toUpperCase(),
            name: name,
            iataCode: iataCode.toUpperCase(),
            icaoCode: (tags['icao'] as String?)?.toUpperCase(),
            coordinate: airportCoordinate,
            distanceKilometers: distanceKilometers,
          ),
        );
      }

      final deduplicated = <String, NearbyAirport>{};
      for (final airport in airports) {
        final existing = deduplicated[airport.id];
        if (existing == null ||
            airport.distanceKilometers < existing.distanceKilometers) {
          deduplicated[airport.id] = airport;
        }
      }

      for (final airport in fallbackAirports) {
        deduplicated.putIfAbsent(airport.id, () => airport);
      }

      final sorted = deduplicated.values.toList()
        ..sort((a, b) => a.distanceKilometers.compareTo(b.distanceKilometers));
      return sorted.take(limit).toList();
    } catch (_) {
      return fallbackAirports.take(limit).toList();
    }
  }

  List<NearbyAirport> _airportsFromFallbackCatalog(
    LatLng coordinate, {
    required double radiusKilometers,
  }) {
    final airports = <NearbyAirport>[];

    for (final airport in _fallbackAirportCatalog) {
      final airportCoordinate = LatLng(airport.latitude, airport.longitude);
      final distanceKilometers =
          distanceKilometersBetween(coordinate, airportCoordinate);

      if (distanceKilometers > radiusKilometers) continue;

      airports.add(
        NearbyAirport(
          id: airport.iataCode,
          name: airport.name,
          iataCode: airport.iataCode,
          icaoCode: airport.icaoCode,
          coordinate: airportCoordinate,
          distanceKilometers: distanceKilometers,
        ),
      );
    }

    airports.sort((a, b) => a.distanceKilometers.compareTo(b.distanceKilometers));
    return airports;
  }

  Uri _overpassURL(LatLng coordinate, {required double radiusKilometers}) {
    final radiusMeters = (radiusKilometers * 1000).toInt();
    final query = '''
[out:json][timeout:25];
(
  node["aeroway"="aerodrome"](around:$radiusMeters,${coordinate.latitude},${coordinate.longitude});
  way["aeroway"="aerodrome"](around:$radiusMeters,${coordinate.latitude},${coordinate.longitude});
);
out center tags;
''';

    return Uri.parse('https://overpass-api.de/api/interpreter')
        .replace(queryParameters: {'data': query});
  }
}
