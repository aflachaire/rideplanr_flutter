import 'package:flutter/foundation.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// Port of the iOS `LocationService`. Uses the device's real GPS location.
/// The Miami constant below is only a fallback shown until the first real fix
/// resolves (and the test-location override, off for release).
class LocationService extends ChangeNotifier {
  static const LatLng _forcedTestLocation = LatLng(25.7617, -80.1918);
  static const String _forcedTestCityName = 'Miami';
  static const String _forcedTestCountryCode = 'US';
  // Release: use real device location. Set to true only to pin a test city.
  static const bool _usesForcedTestLocation = false;

  LocationPermission authorizationStatus = LocationPermission.denied;
  LatLng? currentLocation;
  // Neutral label shown until the first real GPS fix resolves the city.
  String cityName = _usesForcedTestLocation ? _forcedTestCityName : 'Locating…';
  String countryCode = _forcedTestCountryCode;

  LocationService() {
    _syncAuthorizationState();
  }

  LatLng? get currentCoordinate {
    if (_usesForcedTestLocation) {
      return _forcedTestLocation;
    }

    return currentLocation ?? _forcedTestLocation;
  }

  String get refreshToken {
    final coordinate = _usesForcedTestLocation
        ? _forcedTestLocation
        : (currentLocation ?? _forcedTestLocation);
    final latitude = coordinate.latitude.toStringAsFixed(3);
    final longitude = coordinate.longitude.toStringAsFixed(3);
    return '$latitude,$longitude';
  }

  String get statusSummary {
    if (_usesForcedTestLocation) {
      return _forcedTestCityName;
    }

    switch (authorizationStatus) {
      case LocationPermission.always:
      case LocationPermission.whileInUse:
        return cityName == 'Current location'
            ? 'Location access enabled'
            : cityName;
      case LocationPermission.denied:
        return 'Location access not requested yet';
      case LocationPermission.deniedForever:
        return 'Location access denied';
      case LocationPermission.unableToDetermine:
        return 'Location status unavailable';
    }
  }

  Future<void> requestAuthorizationIfNeeded() async {
    try {
      authorizationStatus = await Geolocator.checkPermission();

      if (authorizationStatus == LocationPermission.denied) {
        authorizationStatus = await Geolocator.requestPermission();
      }

      if (authorizationStatus == LocationPermission.always ||
          authorizationStatus == LocationPermission.whileInUse) {
        await _startTracking();
      }
    } catch (_) {
      // Keep last known state; transient location failures are expected.
    }

    _syncAuthorizationState();
  }

  Future<void> refreshLocation() async {
    try {
      authorizationStatus = await Geolocator.checkPermission();

      switch (authorizationStatus) {
        case LocationPermission.denied:
          authorizationStatus = await Geolocator.requestPermission();
        case LocationPermission.always:
        case LocationPermission.whileInUse:
          await _startTracking();
        case LocationPermission.deniedForever:
          await Geolocator.openAppSettings();
        case LocationPermission.unableToDetermine:
          break;
      }
    } catch (_) {
      // Keep the last known state.
    }

    notifyListeners();
  }

  void _syncAuthorizationState() {
    if (_usesForcedTestLocation) {
      cityName = _forcedTestCityName;
      countryCode = _forcedTestCountryCode;
      currentLocation = _forcedTestLocation;
      notifyListeners();
      return;
    }

    // Real-location mode: only seed the fallback coordinate until the first
    // real GPS fix resolves — never overwrite a location already obtained
    // (otherwise it would clobber the fix from _startTracking).
    currentLocation ??= _forcedTestLocation;
    notifyListeners();
  }

  Future<void> _startTracking() async {
    if (_usesForcedTestLocation) return;

    try {
      final position = await Geolocator.getCurrentPosition();
      currentLocation = LatLng(position.latitude, position.longitude);
      await _reverseGeocode(currentLocation!);
      notifyListeners();
    } catch (_) {
      // Transient failures are expected.
    }
  }

  Future<void> _reverseGeocode(LatLng location) async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(
        location.latitude,
        location.longitude,
      );
      final placemark = placemarks.isEmpty ? null : placemarks.first;
      final locality = _nonEmpty(placemark?.locality) ??
          _nonEmpty(placemark?.subLocality) ??
          _nonEmpty(placemark?.administrativeArea);
      cityName = locality ?? 'Current location';
      countryCode = _nonEmpty(placemark?.isoCountryCode) ?? countryCode;
    } catch (_) {
      cityName = 'Current location';
    }
  }

  String? _nonEmpty(String? value) {
    if (value == null) return null;
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}
