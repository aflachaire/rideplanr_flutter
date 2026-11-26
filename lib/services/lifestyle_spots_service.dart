import 'dart:convert';

import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import 'service_utilities.dart';

class LifestyleServiceError implements Exception {
  LifestyleServiceError(this.message);

  final String message;

  @override
  String toString() => message;
}

enum _QueryMode { office, nightlife, restaurant, hotel }

class _Point {
  const _Point({required this.coordinate, this.isSecondaryKind = false});

  final LatLng coordinate;

  /// Office mode: commercial-area point. Nightlife mode: food anchor.
  final bool isSecondaryKind;
}

class _Cluster {
  _Cluster(_Point seed)
      : coordinate = seed.coordinate,
        primaryCount = seed.isSecondaryKind ? 0 : 1,
        secondaryCount = seed.isSecondaryKind ? 1 : 0;

  LatLng coordinate;
  int primaryCount;
  int secondaryCount;
  double distanceKilometers = 0;

  int get totalPointCount => primaryCount + secondaryCount;

  void append(_Point point) {
    final nextCount = totalPointCount + 1;
    coordinate = LatLng(
      ((coordinate.latitude * totalPointCount) + point.coordinate.latitude) /
          nextCount,
      ((coordinate.longitude * totalPointCount) + point.coordinate.longitude) /
          nextCount,
    );
    if (point.isSecondaryKind) {
      secondaryCount += 1;
    } else {
      primaryCount += 1;
    }
  }
}

/// Port of the iOS `LifestyleSpotsService`.
///
/// The iOS version mixes Overpass data with Apple `MKLocalSearch` results;
/// Flutter has no MapKit local search, so every venue category is resolved
/// through equivalent Overpass queries instead.
class LifestyleSpotsService {
  LifestyleSpotsService({http.Client? client})
      : _client = client ?? http.Client();

  final http.Client _client;

  static const Duration _overpassRequestTimeout = Duration(seconds: 3);
  static const Duration _geocodingTimeout = Duration(seconds: 2);

  Future<List<Opportunity>> fetchOfficeOpportunities({
    required LatLng coordinate,
    double radiusKilometers = 20,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime windowStart,
    DateTime? windowEnd,
  }) async {
    final resolvedWindowEnd =
        windowEnd ?? windowStart.add(const Duration(hours: 12));

    final results = await Future.wait([
      _fetchOfficeLunchAreas(
        coordinate: coordinate,
        radiusKilometers: radiusKilometers,
        timeDisplayFormat: timeDisplayFormat,
        visibleWindowStart: windowStart,
        visibleWindowEnd: resolvedWindowEnd,
      ).catchError((_) => <Opportunity>[]),
      _fetchOfficeAreas(
        coordinate: coordinate,
        radiusKilometers: radiusKilometers,
        timeDisplayFormat: timeDisplayFormat,
        visibleWindowStart: windowStart,
        visibleWindowEnd: resolvedWindowEnd,
      ).catchError((_) => <Opportunity>[]),
      _fetchNightlifeAreas(
        coordinate: coordinate,
        radiusKilometers: radiusKilometers > 10 ? 10 : radiusKilometers,
        timeDisplayFormat: timeDisplayFormat,
        visibleWindowStart: windowStart,
        visibleWindowEnd: resolvedWindowEnd,
      ).catchError((_) => <Opportunity>[]),
      _fetchRestaurantAreas(
        coordinate: coordinate,
        radiusKilometers: radiusKilometers > 12 ? 12 : radiusKilometers,
        timeDisplayFormat: timeDisplayFormat,
        visibleWindowStart: windowStart,
        visibleWindowEnd: resolvedWindowEnd,
      ).catchError((_) => <Opportunity>[]),
      _fetchHotelAreas(
        coordinate: coordinate,
        radiusKilometers: radiusKilometers > 10 ? 10 : radiusKilometers,
        timeDisplayFormat: timeDisplayFormat,
        visibleWindowStart: windowStart,
        visibleWindowEnd: resolvedWindowEnd,
      ).catchError((_) => <Opportunity>[]),
    ]);

    final combined = results.expand((list) => list).toList()
      ..sort((lhs, rhs) {
        if (lhs.startsInMinutes == rhs.startsInMinutes) {
          if (lhs.score == rhs.score) {
            return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
          }
          return rhs.score.compareTo(lhs.score);
        }

        return lhs.startsInMinutes.compareTo(rhs.startsInMinutes);
      });

    return combined;
  }

  Future<List<Opportunity>> _fetchOfficeAreas({
    required LatLng coordinate,
    required double radiusKilometers,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime visibleWindowStart,
    required DateTime visibleWindowEnd,
  }) async {
    final officePoints = await _fetchPoints(
      coordinate,
      radiusKilometers: radiusKilometers,
      mode: _QueryMode.office,
    );
    if (officePoints.isEmpty) return [];

    final eveningWindow = _dailyWindow(startHour: 17, endHour: 19);

    final clusters = _clustered(
      officePoints,
      around: coordinate,
      clusterRadiusMeters: 1500,
      filter: (c) =>
          c.primaryCount >= 4 || (c.primaryCount >= 3 && c.secondaryCount >= 1),
    );

    final opportunities = <Opportunity>[];

    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      final startsInMinutes = _minutesUntil(eveningWindow.start);
      if (!_isWindowVisible(eveningWindow.start, visibleWindowStart, visibleWindowEnd)) {
        continue;
      }
      final startText = timeDisplayFormat.compactTimeString(eveningWindow.start);
      final endText = timeDisplayFormat.compactTimeString(eveningWindow.end);
      final distanceKilometers = cluster.distanceKilometers;
      final driveTimeMinutes =
          (distanceKilometers / 28 * 60).round().clamp(6, 1 << 31).toInt();
      final potentialCustomers =
          (cluster.primaryCount ~/ 2 + cluster.secondaryCount + 3).clamp(6, 18).toInt();
      final proximityBoost =
          (20 - distanceKilometers.round()).clamp(0, 1 << 31).toInt();
      final densityBoost = (cluster.primaryCount > 16 ? 16 : cluster.primaryCount) * 3 +
          (cluster.secondaryCount * 4);
      final score = (48 + densityBoost + proximityBoost).clamp(0, 92).toInt();
      final clusterName =
          await _districtName(cluster.coordinate, fallback: 'Business district');

      opportunities.add(
        Opportunity(
          id: 'live-lifestyle-office-$index-${_coordinateKey(cluster.coordinate)}',
          title: clusterName,
          subtitle: 'Business district busy from $startText to $endText',
          zoneName: clusterName,
          latitude: cluster.coordinate.latitude,
          longitude: cluster.coordinate.longitude,
          startsInMinutes: startsInMinutes,
          distanceKilometers: distanceKilometers,
          driveTimeMinutes: driveTimeMinutes,
          potentialCustomers: potentialCustomers,
          score: score,
          categories: const [SignalCategory.lifestyle],
          recommendation:
              'Position near $clusterName before office commuters start leaving.',
          detail:
              '${cluster.primaryCount} mapped office points and ${cluster.secondaryCount} commercial-use areas were detected in this district. This spot is inferred from real business density and targets the $startText to $endText evening release window.',
        ),
      );
    }

    return opportunities;
  }

  Future<List<Opportunity>> _fetchOfficeLunchAreas({
    required LatLng coordinate,
    required double radiusKilometers,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime visibleWindowStart,
    required DateTime visibleWindowEnd,
  }) async {
    final officePoints = await _fetchPoints(
      coordinate,
      radiusKilometers: radiusKilometers,
      mode: _QueryMode.office,
    );
    if (officePoints.isEmpty) return [];

    final lunchWindow = _dailyWindow(startHour: 12, endHour: 14);

    final clusters = _clustered(
      officePoints,
      around: coordinate,
      clusterRadiusMeters: 1500,
      filter: (c) =>
          c.primaryCount >= 4 || (c.primaryCount >= 3 && c.secondaryCount >= 1),
    );

    final opportunities = <Opportunity>[];

    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      final startsInMinutes = _minutesUntil(lunchWindow.start);
      if (!_isWindowVisible(lunchWindow.start, visibleWindowStart, visibleWindowEnd)) {
        continue;
      }
      final startText = timeDisplayFormat.compactTimeString(lunchWindow.start);
      final endText = timeDisplayFormat.compactTimeString(lunchWindow.end);
      final distanceKilometers = cluster.distanceKilometers;
      final driveTimeMinutes =
          (distanceKilometers / 26 * 60).round().clamp(5, 1 << 31).toInt();
      final potentialCustomers =
          (cluster.primaryCount ~/ 3 + cluster.secondaryCount + 1).clamp(4, 12).toInt();
      final proximityBoost =
          (16 - distanceKilometers.round()).clamp(0, 1 << 31).toInt();
      final densityBoost = (cluster.primaryCount > 12 ? 12 : cluster.primaryCount) * 2 +
          (cluster.secondaryCount * 3);
      final score = (42 + densityBoost + proximityBoost).clamp(0, 82).toInt();
      final clusterName =
          await _districtName(cluster.coordinate, fallback: 'Business district');

      opportunities.add(
        Opportunity(
          id: 'live-lifestyle-lunch-$index-${_coordinateKey(cluster.coordinate)}',
          title: clusterName,
          subtitle: 'Office lunch area busy from $startText to $endText',
          zoneName: clusterName,
          latitude: cluster.coordinate.latitude,
          longitude: cluster.coordinate.longitude,
          startsInMinutes: startsInMinutes,
          distanceKilometers: distanceKilometers,
          driveTimeMinutes: driveTimeMinutes,
          potentialCustomers: potentialCustomers,
          score: score,
          categories: const [SignalCategory.lifestyle],
          recommendation:
              'Position near $clusterName before the office lunch rush starts.',
          detail:
              '${cluster.primaryCount} mapped office points and ${cluster.secondaryCount} commercial-use areas were detected in this district. This spot targets the lighter $startText to $endText lunch wave.',
        ),
      );
    }

    return opportunities;
  }

  Future<List<Opportunity>> _fetchNightlifeAreas({
    required LatLng coordinate,
    required double radiusKilometers,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime visibleWindowStart,
    required DateTime visibleWindowEnd,
  }) async {
    final nightlifePoints = await _fetchPoints(
      coordinate,
      radiusKilometers: radiusKilometers,
      mode: _QueryMode.nightlife,
    );
    if (nightlifePoints.isEmpty) return [];

    final nightlifeWindow = _dailyWindow(startHour: 1, endHour: 3);

    final clusters = _clustered(
      nightlifePoints,
      around: coordinate,
      clusterRadiusMeters: 1500,
      filter: (c) =>
          c.primaryCount >= 3 || (c.primaryCount + c.secondaryCount) >= 5,
    );

    final opportunities = <Opportunity>[];

    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      final startsInMinutes = _minutesUntil(nightlifeWindow.start);
      if (!_isWindowVisible(
          nightlifeWindow.start, visibleWindowStart, visibleWindowEnd)) {
        continue;
      }

      final startText = timeDisplayFormat.compactTimeString(nightlifeWindow.start);
      final endText = timeDisplayFormat.compactTimeString(nightlifeWindow.end);
      final distanceKilometers = cluster.distanceKilometers;
      final driveTimeMinutes =
          (distanceKilometers / 26 * 60).round().clamp(6, 1 << 31).toInt();
      final potentialCustomers =
          (cluster.primaryCount + cluster.secondaryCount ~/ 2 + 4).clamp(7, 18).toInt();
      final proximityBoost =
          (18 - distanceKilometers.round()).clamp(0, 1 << 31).toInt();
      final densityBoost = (cluster.primaryCount > 14 ? 14 : cluster.primaryCount) * 4 +
          (cluster.secondaryCount * 2);
      final score = (52 + densityBoost + proximityBoost).clamp(0, 94).toInt();
      final clusterName =
          await _districtName(cluster.coordinate, fallback: 'Nightlife area');

      opportunities.add(
        Opportunity(
          id: 'live-lifestyle-night-$index-${_coordinateKey(cluster.coordinate)}',
          title: clusterName,
          subtitle: 'Nightlife area busy from $startText to $endText',
          zoneName: clusterName,
          latitude: cluster.coordinate.latitude,
          longitude: cluster.coordinate.longitude,
          startsInMinutes: startsInMinutes,
          distanceKilometers: distanceKilometers,
          driveTimeMinutes: driveTimeMinutes,
          potentialCustomers: potentialCustomers,
          score: score,
          categories: const [SignalCategory.lifestyle],
          recommendation:
              'Position near $clusterName before bar exits start releasing riders.',
          detail:
              '${cluster.primaryCount} mapped bars, pubs, and nightclubs were detected in this area, with nightlife demand expected from $startText to $endText.',
        ),
      );
    }

    return opportunities;
  }

  Future<List<Opportunity>> _fetchRestaurantAreas({
    required LatLng coordinate,
    required double radiusKilometers,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime visibleWindowStart,
    required DateTime visibleWindowEnd,
  }) async {
    final restaurantPoints = await _fetchPoints(
      coordinate,
      radiusKilometers: radiusKilometers,
      mode: _QueryMode.restaurant,
    );
    if (restaurantPoints.isEmpty) return [];

    final dinnerWindow = _dailyWindow(startHour: 20, endHour: 22);

    final clusters = _clustered(
      restaurantPoints,
      around: coordinate,
      clusterRadiusMeters: 1000,
      filter: (c) => c.primaryCount >= 5,
    );

    final opportunities = <Opportunity>[];

    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      final startsInMinutes = _minutesUntil(dinnerWindow.start);
      if (!_isWindowVisible(dinnerWindow.start, visibleWindowStart, visibleWindowEnd)) {
        continue;
      }

      final startText = timeDisplayFormat.compactTimeString(dinnerWindow.start);
      final endText = timeDisplayFormat.compactTimeString(dinnerWindow.end);
      final distanceKilometers = cluster.distanceKilometers;
      final driveTimeMinutes =
          (distanceKilometers / 24 * 60).round().clamp(6, 1 << 31).toInt();
      final potentialCustomers = (cluster.primaryCount + 3).clamp(8, 18).toInt();
      final proximityBoost =
          (18 - distanceKilometers.round()).clamp(0, 1 << 31).toInt();
      final densityBoost =
          (cluster.primaryCount > 16 ? 16 : cluster.primaryCount) * 3;
      final score = (50 + densityBoost + proximityBoost).clamp(0, 90).toInt();
      final clusterName =
          await _districtName(cluster.coordinate, fallback: 'Restaurant area');

      opportunities.add(
        Opportunity(
          id: 'live-lifestyle-dining-$index-${_coordinateKey(cluster.coordinate)}',
          title: clusterName,
          subtitle: 'Restaurant area busy from $startText to $endText',
          zoneName: clusterName,
          latitude: cluster.coordinate.latitude,
          longitude: cluster.coordinate.longitude,
          startsInMinutes: startsInMinutes,
          distanceKilometers: distanceKilometers,
          driveTimeMinutes: driveTimeMinutes,
          potentialCustomers: potentialCustomers,
          score: score,
          categories: const [SignalCategory.lifestyle],
          recommendation:
              'Position near $clusterName before dinner traffic starts releasing rides.',
          detail:
              '${cluster.primaryCount} mapped restaurants were found within roughly 1 km of this area. This dining hotspot targets the $startText to $endText dinner window.',
        ),
      );
    }

    return opportunities;
  }

  Future<List<Opportunity>> _fetchHotelAreas({
    required LatLng coordinate,
    required double radiusKilometers,
    required TimeDisplayFormat timeDisplayFormat,
    required DateTime visibleWindowStart,
    required DateTime visibleWindowEnd,
  }) async {
    final hotelPoints = await _fetchPoints(
      coordinate,
      radiusKilometers: radiusKilometers,
      mode: _QueryMode.hotel,
    );
    if (hotelPoints.isEmpty) return [];

    final checkoutWindow = _dailyWindow(startHour: 10, endHour: 12);

    final clusters = _clustered(
      hotelPoints,
      around: coordinate,
      clusterRadiusMeters: 1000,
      filter: (c) => c.primaryCount >= 3,
    );

    final opportunities = <Opportunity>[];

    for (var index = 0; index < clusters.length; index++) {
      final cluster = clusters[index];
      final startsInMinutes = _minutesUntil(checkoutWindow.start);
      if (!_isWindowVisible(
          checkoutWindow.start, visibleWindowStart, visibleWindowEnd)) {
        continue;
      }

      final startText = timeDisplayFormat.compactTimeString(checkoutWindow.start);
      final endText = timeDisplayFormat.compactTimeString(checkoutWindow.end);
      final distanceKilometers = cluster.distanceKilometers;
      final driveTimeMinutes =
          (distanceKilometers / 24 * 60).round().clamp(6, 1 << 31).toInt();
      final potentialCustomers = (cluster.primaryCount * 2 + 2).clamp(7, 18).toInt();
      final proximityBoost =
          (16 - distanceKilometers.round()).clamp(0, 1 << 31).toInt();
      final densityBoost =
          (cluster.primaryCount > 12 ? 12 : cluster.primaryCount) * 4;
      final score = (48 + densityBoost + proximityBoost).clamp(0, 90).toInt();
      final clusterName =
          await _districtName(cluster.coordinate, fallback: 'Hotel area');

      opportunities.add(
        Opportunity(
          id: 'live-lifestyle-hotel-$index-${_coordinateKey(cluster.coordinate)}',
          title: clusterName,
          subtitle: 'Hotel area busy from $startText to $endText',
          zoneName: clusterName,
          latitude: cluster.coordinate.latitude,
          longitude: cluster.coordinate.longitude,
          startsInMinutes: startsInMinutes,
          distanceKilometers: distanceKilometers,
          driveTimeMinutes: driveTimeMinutes,
          potentialCustomers: potentialCustomers,
          score: score,
          categories: const [SignalCategory.lifestyle],
          recommendation:
              'Position near $clusterName before hotel checkout traffic starts releasing rides.',
          detail:
              '${cluster.primaryCount} mapped hotels were found within roughly 1 km of this area. This hotel checkout hotspot targets the $startText to $endText checkout window.',
        ),
      );
    }

    return opportunities;
  }

  // MARK: Overpass fetching

  Future<List<_Point>> _fetchPoints(
    LatLng coordinate, {
    required double radiusKilometers,
    required _QueryMode mode,
  }) async {
    final url = _overpassURL(coordinate,
        radiusKilometers: radiusKilometers, mode: mode);

    final response =
        await _client.get(url).timeout(_overpassRequestTimeout);
    if (response.statusCode < 200 || response.statusCode > 299) {
      throw LifestyleServiceError(
          'Lifestyle source returned ${response.statusCode}.');
    }

    final payload = jsonDecode(response.body) as Map<String, dynamic>;
    final elements = (payload['elements'] as List?) ?? const [];
    final points = <_Point>[];
    final seenKeys = <String>{};

    for (final raw in elements) {
      final element = (raw as Map).cast<String, dynamic>();
      final tags = (element['tags'] as Map?)?.cast<String, dynamic>();
      final center = (element['center'] as Map?)?.cast<String, dynamic>();
      final latitude =
          (element['lat'] as num?)?.toDouble() ?? (center?['lat'] as num?)?.toDouble();
      final longitude =
          (element['lon'] as num?)?.toDouble() ?? (center?['lon'] as num?)?.toDouble();
      if (tags == null || latitude == null || longitude == null) continue;

      final point = _pointFromTags(
        tags,
        coordinate: LatLng(latitude, longitude),
        mode: mode,
      );
      if (point == null) continue;

      final key =
          '${latitude.toStringAsFixed(3)}|${longitude.toStringAsFixed(3)}|${point.isSecondaryKind}';
      if (seenKeys.add(key)) {
        points.add(point);
      }
    }

    return points;
  }

  _Point? _pointFromTags(
    Map<String, dynamic> tags, {
    required LatLng coordinate,
    required _QueryMode mode,
  }) {
    String? tag(String key) => (tags[key] as String?)?.trim();

    switch (mode) {
      case _QueryMode.office:
        final officeTag = tag('office');
        final landuseTag = tag('landuse');
        final amenityTag = tag('amenity');

        final isOfficePoint = officeTag != null;
        final isCommercialArea = landuseTag == 'commercial' ||
            landuseTag == 'retail' ||
            amenityTag == 'business_centre';

        if (!isOfficePoint && !isCommercialArea) return null;

        return _Point(coordinate: coordinate, isSecondaryKind: isCommercialArea);
      case _QueryMode.nightlife:
        final amenity = tag('amenity');
        final leisure = tag('leisure');

        final isNightlifeVenue =
            amenity == 'bar' || amenity == 'pub' || amenity == 'nightclub';
        final isFoodAnchor = amenity == 'restaurant' ||
            amenity == 'cafe' ||
            leisure == 'beer_garden';

        if (!isNightlifeVenue && !isFoodAnchor) return null;

        return _Point(coordinate: coordinate, isSecondaryKind: isFoodAnchor);
      case _QueryMode.restaurant:
        if (tag('amenity') != 'restaurant') return null;
        return _Point(coordinate: coordinate);
      case _QueryMode.hotel:
        final tourism = tag('tourism');
        if (tourism != 'hotel' && tourism != 'motel') return null;
        return _Point(coordinate: coordinate);
    }
  }

  Uri _overpassURL(
    LatLng coordinate, {
    required double radiusKilometers,
    required _QueryMode mode,
  }) {
    final bbox = boundingBoxAround(coordinate, radiusKilometers);
    final String body;

    switch (mode) {
      case _QueryMode.office:
        body = '''
(
  node["office"];
  way["office"];
  relation["office"];
  way["landuse"="commercial"];
  relation["landuse"="commercial"];
  way["landuse"="retail"];
  relation["landuse"="retail"];
  node["amenity"="business_centre"];
  way["amenity"="business_centre"];
  relation["amenity"="business_centre"];
);
''';
      case _QueryMode.nightlife:
        body = '''
(
  node["amenity"="bar"];
  way["amenity"="bar"];
  relation["amenity"="bar"];
  node["amenity"="pub"];
  way["amenity"="pub"];
  relation["amenity"="pub"];
  node["amenity"="nightclub"];
  way["amenity"="nightclub"];
  relation["amenity"="nightclub"];
  node["leisure"="beer_garden"];
  way["leisure"="beer_garden"];
  relation["leisure"="beer_garden"];
);
''';
      case _QueryMode.restaurant:
        body = '''
(
  node["amenity"="restaurant"];
  way["amenity"="restaurant"];
);
''';
      case _QueryMode.hotel:
        body = '''
(
  node["tourism"="hotel"];
  way["tourism"="hotel"];
  node["tourism"="motel"];
  way["tourism"="motel"];
);
''';
    }

    final query = '''
[out:json][timeout:20][bbox:${bbox.minLatitude},${bbox.minLongitude},${bbox.maxLatitude},${bbox.maxLongitude}];
$body
out center tags;
''';

    return Uri.parse('https://overpass-api.de/api/interpreter')
        .replace(queryParameters: {'data': query});
  }

  // MARK: Clustering

  List<_Cluster> _clustered(
    List<_Point> points, {
    required LatLng around,
    required double clusterRadiusMeters,
    required bool Function(_Cluster) filter,
  }) {
    final clusters = <_Cluster>[];

    for (final point in points) {
      _Cluster? target;
      for (final cluster in clusters) {
        final meters =
            distanceKilometersBetween(cluster.coordinate, point.coordinate) *
                1000;
        if (meters <= clusterRadiusMeters) {
          target = cluster;
          break;
        }
      }

      if (target != null) {
        target.append(point);
      } else {
        clusters.add(_Cluster(point));
      }
    }

    final filtered = clusters.where(filter).toList();
    for (final cluster in filtered) {
      cluster.distanceKilometers =
          distanceKilometersBetween(around, cluster.coordinate);
    }

    filtered.sort((lhs, rhs) {
      if (lhs.primaryCount == rhs.primaryCount) {
        return lhs.distanceKilometers.compareTo(rhs.distanceKilometers);
      }
      return rhs.primaryCount.compareTo(lhs.primaryCount);
    });

    return filtered;
  }

  // MARK: District naming

  Future<String> _districtName(LatLng coordinate, {required String fallback}) async {
    try {
      final placemarks = await geocoding
          .placemarkFromCoordinates(coordinate.latitude, coordinate.longitude)
          .timeout(_geocodingTimeout);

      if (placemarks.isNotEmpty) {
        final placemark = placemarks.first;
        final candidates = [
          placemark.subLocality,
          _sanitizedPlacemarkName(placemark.name, locality: placemark.locality),
        ];

        for (final candidate in candidates) {
          final label = _normalizedDistrictLabel(candidate);
          if (label != null) return label;
        }
      }
    } catch (_) {
      // Geocoding failures or timeouts fall through to the generic label.
    }

    return fallback;
  }

  String? _normalizedDistrictLabel(String? label) {
    final trimmed = label?.trim();
    if (trimmed == null || trimmed.isEmpty) return null;

    const genericWords = ['france', 'united kingdom', 'australia'];
    if (genericWords.contains(trimmed.toLowerCase())) return null;

    return trimmed;
  }

  String? _sanitizedPlacemarkName(String? name, {String? locality}) {
    final cleanedName = _normalizedDistrictLabel(name);
    if (cleanedName == null) return null;

    final cleanedLocality = _normalizedDistrictLabel(locality);
    if (cleanedLocality != null &&
        cleanedName.toLowerCase() == cleanedLocality.toLowerCase()) {
      return null;
    }

    if (RegExp(r'\d').hasMatch(cleanedName)) return null;

    return cleanedName;
  }

  // MARK: Daily release windows (device-local timezone)

  ({DateTime start, DateTime end}) _dailyWindow({
    required int startHour,
    required int endHour,
  }) {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    var start = startOfDay.add(Duration(hours: startHour));
    var end = startOfDay.add(Duration(hours: endHour));

    if (now.isAfter(end)) {
      start = start.add(const Duration(days: 1));
      end = end.add(const Duration(days: 1));
    }

    return (start: start, end: end);
  }

  bool _isWindowVisible(
    DateTime startDate,
    DateTime visibleWindowStart,
    DateTime visibleWindowEnd,
  ) =>
      !startDate.isBefore(visibleWindowStart) &&
      !startDate.isAfter(visibleWindowEnd);

  int _minutesUntil(DateTime date) =>
      (date.difference(DateTime.now()).inSeconds ~/ 60).clamp(0, 1 << 31).toInt();

  String _coordinateKey(LatLng coordinate) =>
      '${coordinate.latitude.toStringAsFixed(3)}-${coordinate.longitude.toStringAsFixed(3)}';
}
