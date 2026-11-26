import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../models/app_models.dart';
import '../services/mock_data_service.dart';
import '../services/weather_service.dart';

class HomeViewModel extends ChangeNotifier {
  HomeViewModel({
    required MockDataService service,
    required WeatherService weatherService,
  })  : _service = service,
        _weatherService = weatherService {
    dashboard = _service.dashboard();
  }

  final MockDataService _service;
  final WeatherService _weatherService;

  late MockDashboard dashboard;
  WeatherBadge weatherBadge = WeatherBadge.placeholder;
  List<WeatherForecastSlot> weatherForecast = WeatherForecastSlot.placeholder;

  ({int startHour, int endHour})? get peakWindow {
    final values = dashboard.hourlyPotential;
    if (values.length < 2) return null;

    ({int startHour, int endHour})? bestPair;
    var bestScore = -1 << 62;

    for (var index = 0; index < values.length - 1; index++) {
      final combinedScore = values[index].score + values[index + 1].score;
      if (combinedScore > bestScore) {
        bestScore = combinedScore;
        bestPair = (
          startHour: values[index].hour,
          endHour: (values[index + 1].hour + 1) % 24,
        );
      }
    }

    return bestPair;
  }

  void refresh() {
    dashboard = _service.dashboard();
    notifyListeners();
  }

  Future<void> refreshAll(LatLng? coordinate) async {
    refresh();
    final weather = await _weatherService.fetchWeather(coordinate);
    weatherBadge = weather.badge;
    weatherForecast = weather.forecast;
    notifyListeners();
  }
}
