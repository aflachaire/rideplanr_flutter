import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

// MARK: - Shared arrival-window types

class ArrivalWindow {
  ArrivalWindow({required this.start, required this.end, required this.arrivals});

  final DateTime start;
  final DateTime end;
  final List<DateTime> arrivals;
}

class BoundingBox {
  const BoundingBox({
    required this.minLatitude,
    required this.minLongitude,
    required this.maxLatitude,
    required this.maxLongitude,
  });

  final double minLatitude;
  final double minLongitude;
  final double maxLatitude;
  final double maxLongitude;
}

const Distance _distance = Distance();

/// Great-circle distance between two coordinates, in kilometers.
double distanceKilometersBetween(LatLng a, LatLng b) =>
    _distance.as(LengthUnit.Meter, a, b) / 1000;

/// Groups a flat list of arrival dates into 1-hour calendar buckets.
List<ArrivalWindow> groupedArrivalWindows(List<DateTime> arrivals) {
  if (arrivals.isEmpty) return [];

  final grouped = <DateTime, List<DateTime>>{};

  for (final arrival in arrivals) {
    final local = arrival.toLocal();
    final bucketStart = DateTime(local.year, local.month, local.day, local.hour);
    grouped.putIfAbsent(bucketStart, () => []).add(arrival);
  }

  final sortedKeys = grouped.keys.toList()..sort();
  return sortedKeys.map((bucketStart) {
    final bucketArrivals = grouped[bucketStart]!..sort();
    return ArrivalWindow(
      start: bucketStart,
      end: bucketStart.add(const Duration(hours: 1)),
      arrivals: bucketArrivals,
    );
  }).toList();
}

/// Returns a compact "yyyyMMddHH" identifier for a 1-hour bucket starting at [date].
String windowID(DateTime date) {
  final local = date.toLocal();
  final mm = local.month.toString().padLeft(2, '0');
  final dd = local.day.toString().padLeft(2, '0');
  final hh = local.hour.toString().padLeft(2, '0');
  return '${local.year}$mm$dd$hh';
}

/// Returns the approximate lat/lon bounding box for a circle of
/// [radiusKilometers] around [coordinate].
BoundingBox boundingBoxAround(LatLng coordinate, double radiusKilometers) {
  final latitudeDelta = radiusKilometers / 111;
  final longitudeDelta = radiusKilometers /
      math.max(1, 111 * math.cos(coordinate.latitude * math.pi / 180));
  return BoundingBox(
    minLatitude: coordinate.latitude - latitudeDelta,
    minLongitude: coordinate.longitude - longitudeDelta,
    maxLatitude: coordinate.latitude + latitudeDelta,
    maxLongitude: coordinate.longitude + longitudeDelta,
  );
}

/// Parses ISO-8601 timestamps (with or without fractional seconds) and the
/// AeroDataBox "yyyy-MM-dd HH:mm'Z'" UTC variant.
DateTime? parseFlexibleDate(String value) {
  final direct = DateTime.tryParse(value);
  if (direct != null) return direct;

  // AeroDataBox non-standard UTC format: "2026-06-12 18:20Z"
  final match =
      RegExp(r'^(\d{4})-(\d{2})-(\d{2}) (\d{2}):(\d{2})Z$').firstMatch(value);
  if (match != null) {
    return DateTime.utc(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
      int.parse(match.group(4)!),
      int.parse(match.group(5)!),
    );
  }

  return null;
}
