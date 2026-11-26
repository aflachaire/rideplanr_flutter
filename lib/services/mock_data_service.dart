import '../models/app_models.dart';

class MockDashboard {
  MockDashboard({
    required this.globalScore,
    required this.headline,
    required this.recommendation,
    required this.hourlyPotential,
    required this.signals,
    required this.opportunities,
    required this.zones,
  });

  final int globalScore;
  final String headline;
  final String recommendation;
  final List<HourlyPotential> hourlyPotential;
  final List<DriverSignal> signals;
  final List<Opportunity> opportunities;
  final List<DriverZone> zones;
}

class MockDataService {
  MockDashboard dashboard() {
    final signals = upcomingSignals();
    final opportunities = allOpportunities();
    final zones = strategicZones();
    final averageImpact = signals.isEmpty
        ? 0
        : signals.map((s) => s.impactScore).reduce((a, b) => a + b) ~/
            signals.length;

    return MockDashboard(
      globalScore: (averageImpact + 18).clamp(0, 98).toInt(),
      headline: 'Good city flow over the next 45 minutes',
      recommendation: 'Stay available for the next strong release window',
      hourlyPotential: hourlyPotential(),
      signals: signals,
      opportunities: opportunities,
      zones: zones,
    );
  }

  List<HourlyPotential> hourlyPotential() {
    final currentHour = DateTime.now().hour;

    return List.generate(12, (offset) {
      final hour = (currentHour + offset) % 24;
      return HourlyPotential(hour: hour, score: _scoreForHour(hour));
    });
  }

  int _scoreForHour(int hour) {
    const hourlyScores = <int, int>{
      0: 28, 1: 22, 2: 18, 3: 16, 4: 20, 5: 27,
      6: 34, 7: 45, 8: 56, 9: 61, 10: 58, 11: 49,
      12: 39, 13: 45, 14: 53, 15: 60, 16: 68, 17: 78,
      18: 90, 19: 84, 20: 63, 21: 55, 22: 39, 23: 32,
    };
    return hourlyScores[hour] ?? 40;
  }

  List<DriverSignal> upcomingSignals() {
    return [
      DriverSignal(
        title: 'Heavy CDG arrivals',
        category: SignalCategory.flights,
        summary: '7 long-haul flights land between 6:20pm and 7:10pm.',
        startsInMinutes: 25,
        impactScore: 88,
      ),
      DriverSignal(
        title: 'Arena concert exit',
        category: SignalCategory.events,
        summary: 'Set ending soon with strong rider dispersion toward west Paris.',
        startsInMinutes: 40,
        impactScore: 84,
      ),
      DriverSignal(
        title: 'Heavy traffic at Porte Maillot',
        category: SignalCategory.traffic,
        summary: 'Approach times are up by 12 min, avoid the north-west corridor.',
        startsInMinutes: 10,
        impactScore: 61,
      ),
      DriverSignal(
        title: 'Gare de Lyon TGV peak',
        category: SignalCategory.trains,
        summary: '3 near-simultaneous arrivals, strong short premium ride potential.',
        startsInMinutes: 18,
        impactScore: 79,
      ),
      DriverSignal(
        title: 'Shower then easing',
        category: SignalCategory.weather,
        summary: 'Rain eases around 7pm, but demand should stay elevated.',
        startsInMinutes: 32,
        impactScore: 70,
      ),
    ];
  }

  List<Opportunity> allOpportunities() {
    return [];
  }

  List<DriverZone> strategicZones() {
    return [];
  }
}
