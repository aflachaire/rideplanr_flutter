import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../design/app_theme.dart';

enum SignalCategory {
  flights('Flights'),
  trains('Trains'),
  events('Events'),
  weather('Weather'),
  traffic('Traffic'),
  lifestyle('Lifestyle');

  const SignalCategory(this.label);

  final String label;

  static SignalCategory? fromLabel(String label) {
    for (final value in SignalCategory.values) {
      if (value.label == label) return value;
    }
    return null;
  }

  IconData get icon {
    switch (this) {
      case SignalCategory.flights:
        return Icons.flight_land;
      case SignalCategory.trains:
        return Icons.tram;
      case SignalCategory.events:
        return Icons.queue_music;
      case SignalCategory.weather:
        return Icons.wb_cloudy;
      case SignalCategory.traffic:
        return Icons.directions_car;
      case SignalCategory.lifestyle:
        return Icons.wb_twilight;
    }
  }

  Color get tint {
    switch (this) {
      case SignalCategory.flights:
        return AppTheme.cyan;
      case SignalCategory.trains:
        return AppTheme.blue;
      case SignalCategory.events:
        return AppTheme.coral;
      case SignalCategory.weather:
        return AppTheme.mint;
      case SignalCategory.traffic:
        return AppTheme.coral;
      case SignalCategory.lifestyle:
        return AppTheme.mint;
    }
  }
}

class DriverSignal {
  DriverSignal({
    required this.title,
    required this.category,
    required this.summary,
    required this.startsInMinutes,
    required this.impactScore,
  });

  final String title;
  final SignalCategory category;
  final String summary;
  final int startsInMinutes;
  final int impactScore;

  String get id => 'signal-$title';
}

class HourlyPotential {
  const HourlyPotential({required this.hour, required this.score});

  final int hour;
  final int score;
}

class WeatherBadge {
  const WeatherBadge({required this.symbolName, required this.description});

  final String symbolName;
  final String description;

  static const WeatherBadge placeholder =
      WeatherBadge(symbolName: 'cloud.sun.fill', description: 'Forecast');

  /// Maps the iOS SF Symbol names kept in the model to Material icons.
  IconData get icon => weatherSymbolIcon(symbolName);
}

IconData weatherSymbolIcon(String symbolName) {
  switch (symbolName) {
    case 'sun.max.fill':
      return Icons.wb_sunny;
    case 'moon.stars.fill':
    case 'cloud.moon.fill':
      return Icons.nights_stay;
    case 'cloud.sun.fill':
      return Icons.wb_cloudy;
    case 'cloud.fill':
      return Icons.cloud;
    case 'cloud.fog.fill':
      return Icons.foggy;
    case 'cloud.drizzle.fill':
      return Icons.grain;
    case 'cloud.rain.fill':
      return Icons.water_drop;
    case 'cloud.snow.fill':
      return Icons.ac_unit;
    case 'cloud.bolt.rain.fill':
      return Icons.thunderstorm;
    default:
      return Icons.wb_cloudy;
  }
}

class WeatherForecastSlot {
  const WeatherForecastSlot({
    required this.startHour,
    required this.endHour,
    required this.symbolName,
    required this.description,
  });

  final int startHour;
  final int endHour;
  final String symbolName;
  final String description;

  IconData get icon => weatherSymbolIcon(symbolName);

  static const List<WeatherForecastSlot> placeholder = [
    WeatherForecastSlot(startHour: 0, endHour: 2, symbolName: 'cloud.sun.fill', description: 'Forecast'),
    WeatherForecastSlot(startHour: 2, endHour: 4, symbolName: 'cloud.fill', description: 'Forecast'),
    WeatherForecastSlot(startHour: 4, endHour: 6, symbolName: 'cloud.rain.fill', description: 'Forecast'),
    WeatherForecastSlot(startHour: 6, endHour: 8, symbolName: 'sun.max.fill', description: 'Forecast'),
    WeatherForecastSlot(startHour: 8, endHour: 10, symbolName: 'cloud.sun.fill', description: 'Forecast'),
    WeatherForecastSlot(startHour: 10, endHour: 12, symbolName: 'cloud.fill', description: 'Forecast'),
  ];
}

class DriverZone {
  DriverZone({
    required this.name,
    required this.anchor,
    required this.score,
    required this.etaMinutes,
    required this.demandLabel,
    required this.rationale,
    required this.recommendedWindow,
  });

  final String name;
  final Offset anchor;
  final int score;
  final int etaMinutes;
  final String demandLabel;
  final String rationale;
  final String recommendedWindow;
}

class Opportunity {
  const Opportunity({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.zoneName,
    required this.latitude,
    required this.longitude,
    required this.startsInMinutes,
    required this.distanceKilometers,
    required this.driveTimeMinutes,
    required this.potentialCustomers,
    required this.score,
    required this.categories,
    required this.recommendation,
    required this.detail,
  });

  final String id;
  final String title;
  final String subtitle;
  final String zoneName;
  final double latitude;
  final double longitude;
  final int startsInMinutes;
  final double distanceKilometers;
  final int driveTimeMinutes;
  final int potentialCustomers;
  final int score;
  final List<SignalCategory> categories;
  final String recommendation;
  final String detail;

  LatLng get coordinate => LatLng(latitude, longitude);

  Opportunity copyWith({int? startsInMinutes}) {
    return Opportunity(
      id: id,
      title: title,
      subtitle: subtitle,
      zoneName: zoneName,
      latitude: latitude,
      longitude: longitude,
      startsInMinutes: startsInMinutes ?? this.startsInMinutes,
      distanceKilometers: distanceKilometers,
      driveTimeMinutes: driveTimeMinutes,
      potentialCustomers: potentialCustomers,
      score: score,
      categories: categories,
      recommendation: recommendation,
      detail: detail,
    );
  }

  // MARK: Navigation URLs

  Uri get appleMapsURL =>
      Uri.parse('http://maps.apple.com/?daddr=$latitude,$longitude&dirflg=d');

  Uri get googleMapsAppURL => Uri.parse(
      'comgooglemaps://?daddr=$latitude,$longitude&directionsmode=driving');

  Uri get googleMapsWebURL => Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$latitude,$longitude&travelmode=driving');

  Uri get wazeAppURL =>
      Uri.parse('waze://?ll=$latitude,$longitude&navigate=yes');

  Uri get wazeWebURL =>
      Uri.parse('https://www.waze.com/ul?ll=$latitude,$longitude&navigate=yes');

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'subtitle': subtitle,
        'zoneName': zoneName,
        'latitude': latitude,
        'longitude': longitude,
        'startsInMinutes': startsInMinutes,
        'distanceKilometers': distanceKilometers,
        'driveTimeMinutes': driveTimeMinutes,
        'potentialCustomers': potentialCustomers,
        'score': score,
        'categories': categories.map((c) => c.label).toList(),
        'recommendation': recommendation,
        'detail': detail,
      };

  factory Opportunity.fromJson(Map<String, dynamic> json) => Opportunity(
        id: json['id'] as String,
        title: json['title'] as String,
        subtitle: json['subtitle'] as String,
        zoneName: json['zoneName'] as String,
        latitude: (json['latitude'] as num).toDouble(),
        longitude: (json['longitude'] as num).toDouble(),
        startsInMinutes: json['startsInMinutes'] as int,
        distanceKilometers: (json['distanceKilometers'] as num).toDouble(),
        driveTimeMinutes: json['driveTimeMinutes'] as int,
        potentialCustomers: json['potentialCustomers'] as int,
        score: json['score'] as int,
        categories: (json['categories'] as List)
            .map((label) => SignalCategory.fromLabel(label as String))
            .whereType<SignalCategory>()
            .toList(),
        recommendation: json['recommendation'] as String,
        detail: json['detail'] as String,
      );

  @override
  bool operator ==(Object other) => other is Opportunity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// Port of the iOS `Int` extension for time-remaining labels.
extension DriverIntelTime on int {
  bool get isDriverIntelImmediateTime => this <= 0;

  String get driverIntelTimeRemainingText {
    if (isDriverIntelImmediateTime) {
      return 'Now';
    }

    if (this >= 60) {
      final hours = this ~/ 60;
      final minutes = this % 60;

      if (minutes == 0) {
        return 'In ${hours}h';
      }

      return 'In ${hours}h${minutes.toString().padLeft(2, '0')}';
    }

    return 'In $this min';
  }
}

enum OpportunityFilter {
  all('All'),
  urgent('Urgent'),
  airports('Airports'),
  stations('Stations'),
  events('Events');

  const OpportunityFilter(this.label);

  final String label;
}

enum DisplayMode {
  premium('Premium'),
  compact('Compact');

  const DisplayMode(this.label);

  final String label;
}

enum TimeDisplayFormat {
  twelveHour('12h'),
  twentyFourHour('24h');

  const TimeDisplayFormat(this.label);

  final String label;

  String compactTimeString(DateTime date) {
    switch (this) {
      case TimeDisplayFormat.twelveHour:
        final hour12 = date.hour % 12 == 0 ? 12 : date.hour % 12;
        final suffix = date.hour < 12 ? 'am' : 'pm';
        if (date.minute == 0) {
          return '$hour12$suffix';
        }
        return '$hour12:${date.minute.toString().padLeft(2, '0')}$suffix';
      case TimeDisplayFormat.twentyFourHour:
        if (date.minute == 0) {
          return '${date.hour.toString().padLeft(2, '0')}h';
        }
        return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
  }

  // MARK: Hour formatting helpers (used by chart and weather cards)

  String formatHourWindow({required int startHour, required int endHour}) {
    switch (this) {
      case TimeDisplayFormat.twelveHour:
        final startNormalizedHour = startHour % 24;
        final endNormalizedHour = endHour % 24;
        final startText = _format12HourNumber(startHour);
        final endText = _format12HourNumber(endHour);
        final startSuffix = startNormalizedHour < 12 ? 'am' : 'pm';
        final endSuffix = endNormalizedHour < 12 ? 'am' : 'pm';

        if (startSuffix == endSuffix) {
          return '$startText-$endText$endSuffix';
        }

        return '$startText$startSuffix-$endText$endSuffix';
      case TimeDisplayFormat.twentyFourHour:
        return '${startHour.toString().padLeft(2, '0')}h-${endHour.toString().padLeft(2, '0')}h';
    }
  }

  String formatHourLabel(int hour) {
    switch (this) {
      case TimeDisplayFormat.twelveHour:
        final suffix = hour % 24 < 12 ? 'am' : 'pm';
        return '${_format12HourNumber(hour)}$suffix';
      case TimeDisplayFormat.twentyFourHour:
        return '${hour.toString().padLeft(2, '0')}h';
    }
  }

  static int _format12HourNumber(int hour) {
    final normalizedHour = hour % 24;
    return normalizedHour % 12 == 0 ? 12 : normalizedHour % 12;
  }
}

enum DistanceDisplayUnit {
  kilometers('km'),
  miles('mi');

  const DistanceDisplayUnit(this.label);

  final String label;
}

enum AppearanceMode {
  light('Light'),
  dark('Dark'),
  system('System');

  const AppearanceMode(this.label);

  final String label;

  ThemeMode get themeMode {
    switch (this) {
      case AppearanceMode.light:
        return ThemeMode.light;
      case AppearanceMode.dark:
        return ThemeMode.dark;
      case AppearanceMode.system:
        return ThemeMode.system;
    }
  }
}

enum RideType {
  standard('Standard'),
  xlVan('XL / van'),
  premium('Premium');

  const RideType(this.label);

  final String label;

  IconData get icon {
    switch (this) {
      case RideType.standard:
        return Icons.directions_car;
      case RideType.xlVan:
        return Icons.directions_bus;
      case RideType.premium:
        return Icons.local_taxi;
    }
  }
}

class UserSettings {
  UserSettings({
    required this.notificationsEnabled,
    required this.newsletterSubscribed,
    required this.leadTimeMinutes,
    required this.prefersAirportRuns,
    required this.prefersEventRuns,
    required this.displayMode,
    required this.timeDisplayFormat,
    required this.distanceDisplayUnit,
    required this.rideType,
    required this.appearanceMode,
  });

  bool notificationsEnabled;
  bool newsletterSubscribed;
  double leadTimeMinutes;
  bool prefersAirportRuns;
  bool prefersEventRuns;
  DisplayMode displayMode;
  TimeDisplayFormat timeDisplayFormat;
  DistanceDisplayUnit distanceDisplayUnit;
  RideType rideType;
  AppearanceMode appearanceMode;

  UserSettings copy() => UserSettings(
        notificationsEnabled: notificationsEnabled,
        newsletterSubscribed: newsletterSubscribed,
        leadTimeMinutes: leadTimeMinutes,
        prefersAirportRuns: prefersAirportRuns,
        prefersEventRuns: prefersEventRuns,
        displayMode: displayMode,
        timeDisplayFormat: timeDisplayFormat,
        distanceDisplayUnit: distanceDisplayUnit,
        rideType: rideType,
        appearanceMode: appearanceMode,
      );

  static UserSettings load(SharedPreferences defaults) {
    T enumFromLabel<T>(List<T> values, String? label, T fallback,
        String Function(T) labelOf) {
      if (label == null) return fallback;
      for (final value in values) {
        if (labelOf(value) == label) return value;
      }
      return fallback;
    }

    return UserSettings(
      notificationsEnabled:
          defaults.getBool('driverintel.notificationsEnabled') ?? true,
      newsletterSubscribed:
          defaults.getBool('driverintel.newsletterSubscribed') ?? false,
      leadTimeMinutes: defaults.getDouble('driverintel.leadTimeMinutes') ?? 30,
      prefersAirportRuns:
          defaults.getBool('driverintel.prefersAirportRuns') ?? true,
      prefersEventRuns:
          defaults.getBool('driverintel.prefersEventRuns') ?? true,
      displayMode: enumFromLabel(
        DisplayMode.values,
        defaults.getString('driverintel.displayMode'),
        DisplayMode.premium,
        (v) => v.label,
      ),
      timeDisplayFormat: enumFromLabel(
        TimeDisplayFormat.values,
        defaults.getString('driverintel.timeDisplayFormat'),
        TimeDisplayFormat.twelveHour,
        (v) => v.label,
      ),
      distanceDisplayUnit: enumFromLabel(
        DistanceDisplayUnit.values,
        defaults.getString('driverintel.distanceDisplayUnit'),
        DistanceDisplayUnit.kilometers,
        (v) => v.label,
      ),
      rideType: enumFromLabel(
        RideType.values,
        defaults.getString('driverintel.rideType'),
        RideType.standard,
        (v) => v.label,
      ),
      appearanceMode: enumFromLabel(
        AppearanceMode.values,
        defaults.getString('driverintel.appearanceMode'),
        AppearanceMode.dark,
        (v) => v.label,
      ),
    );
  }

  Future<void> persist(SharedPreferences defaults) async {
    await defaults.setBool(
        'driverintel.notificationsEnabled', notificationsEnabled);
    await defaults.setBool(
        'driverintel.newsletterSubscribed', newsletterSubscribed);
    await defaults.setDouble('driverintel.leadTimeMinutes', leadTimeMinutes);
    await defaults.setBool(
        'driverintel.prefersAirportRuns', prefersAirportRuns);
    await defaults.setBool('driverintel.prefersEventRuns', prefersEventRuns);
    await defaults.setString('driverintel.displayMode', displayMode.label);
    await defaults.setString(
        'driverintel.timeDisplayFormat', timeDisplayFormat.label);
    await defaults.setString(
        'driverintel.distanceDisplayUnit', distanceDisplayUnit.label);
    await defaults.setString('driverintel.rideType', rideType.label);
    await defaults.setString(
        'driverintel.appearanceMode', appearanceMode.label);
  }
}
