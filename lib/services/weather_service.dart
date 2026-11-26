import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';

class WeatherResult {
  const WeatherResult({required this.badge, required this.forecast});

  final WeatherBadge badge;
  final List<WeatherForecastSlot> forecast;
}

class WeatherService {
  WeatherService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  Future<WeatherResult> fetchWeather(LatLng? coordinate) async {
    if (coordinate == null) {
      return fetchLondonWeather();
    }

    final latitude = coordinate.latitude.toStringAsFixed(4);
    final longitude = coordinate.longitude.toStringAsFixed(4);
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=$latitude&longitude=$longitude&current=weather_code,is_day&hourly=weather_code,is_day&forecast_hours=12&timezone=auto');

    try {
      final response = await _client.get(url);
      return _parseResponse(response.body);
    } catch (_) {
      return fetchLondonWeather();
    }
  }

  Future<WeatherResult> fetchLondonWeather() async {
    final url = Uri.parse(
        'https://api.open-meteo.com/v1/forecast?latitude=51.5072&longitude=-0.1276&current=weather_code,is_day&hourly=weather_code,is_day&forecast_hours=12&timezone=Europe%2FLondon');

    try {
      final response = await _client.get(url);
      return _parseResponse(response.body);
    } catch (_) {
      return const WeatherResult(
        badge: WeatherBadge.placeholder,
        forecast: WeatherForecastSlot.placeholder,
      );
    }
  }

  WeatherResult _parseResponse(String body) {
    final payload = jsonDecode(body) as Map<String, dynamic>;
    final current = payload['current'] as Map<String, dynamic>;
    final hourly = payload['hourly'] as Map<String, dynamic>;

    final badge = _badge(
      current['weather_code'] as int,
      isDay: current['is_day'] == 1,
    );
    final forecast = _buildForecastSlots(hourly);
    return WeatherResult(badge: badge, forecast: forecast);
  }

  List<WeatherForecastSlot> _buildForecastSlots(Map<String, dynamic> hourly) {
    final times = (hourly['time'] as List?)?.cast<String>() ?? const [];
    final weatherCodes = (hourly['weather_code'] as List?)?.cast<int>() ?? const [];
    final isDayFlags = (hourly['is_day'] as List?)?.cast<int>() ?? const [];

    if (weatherCodes.isEmpty || isDayFlags.isEmpty) {
      return WeatherForecastSlot.placeholder;
    }

    final slots = <WeatherForecastSlot>[];
    final maxIndex = weatherCodes.length < isDayFlags.length
        ? weatherCodes.length
        : isDayFlags.length;
    final limit = maxIndex < 12 ? maxIndex : 12;

    for (var index = 0; index < limit; index += 2) {
      final nextIndex = (index + 1) < maxIndex ? index + 1 : maxIndex - 1;
      final startHour = _extractHour(times.length > index ? times[index] : '');
      final endHour = (startHour + 2) % 24;
      final dominantCode = weatherCodes[index];
      final isDay = isDayFlags[index] == 1;
      final badge = _badge(dominantCode, isDay: isDay);

      slots.add(
        WeatherForecastSlot(
          startHour: startHour,
          endHour: endHour,
          symbolName: badge.symbolName,
          description: badge.description,
        ),
      );

      if (nextIndex == index) break;
    }

    return slots;
  }

  int _extractHour(String timestamp) {
    if (timestamp.length < 5) return 0;
    final suffix = timestamp.substring(timestamp.length - 5);
    return int.tryParse(suffix.substring(0, 2)) ?? 0;
  }

  WeatherBadge _badge(int weatherCode, {required bool isDay}) {
    switch (weatherCode) {
      case 0:
        return WeatherBadge(
          symbolName: isDay ? 'sun.max.fill' : 'moon.stars.fill',
          description: isDay ? 'Clear' : 'Clear night',
        );
      case 1:
      case 2:
        return WeatherBadge(
          symbolName: isDay ? 'cloud.sun.fill' : 'cloud.moon.fill',
          description: 'Partly cloudy',
        );
      case 3:
        return const WeatherBadge(symbolName: 'cloud.fill', description: 'Overcast');
      case 45:
      case 48:
        return const WeatherBadge(symbolName: 'cloud.fog.fill', description: 'Fog');
      case 51:
      case 53:
      case 55:
      case 56:
      case 57:
        return const WeatherBadge(symbolName: 'cloud.drizzle.fill', description: 'Drizzle');
      case 61:
      case 63:
      case 65:
      case 66:
      case 67:
      case 80:
      case 81:
      case 82:
        return const WeatherBadge(symbolName: 'cloud.rain.fill', description: 'Rain');
      case 71:
      case 73:
      case 75:
      case 77:
      case 85:
      case 86:
        return const WeatherBadge(symbolName: 'cloud.snow.fill', description: 'Snow');
      case 95:
      case 96:
      case 99:
        return const WeatherBadge(symbolName: 'cloud.bolt.rain.fill', description: 'Thunderstorm');
      default:
        return WeatherBadge.placeholder;
    }
  }
}
