import 'package:flutter/material.dart';

import '../design/app_theme.dart';

class OnboardingPage {
  const OnboardingPage({
    required this.eyebrow,
    required this.title,
    required this.detail,
    required this.icon,
    required this.accentColor,
    required this.highlights,
  });

  final String eyebrow;
  final String title;
  final String detail;
  final IconData icon;
  final Color accentColor;
  final List<String> highlights;
}

class OnboardingViewModel extends ChangeNotifier {
  int _currentIndex = 0;

  int get currentIndex => _currentIndex;

  set currentIndex(int value) {
    if (_currentIndex == value) return;
    _currentIndex = value;
    notifyListeners();
  }

  final List<OnboardingPage> pages = const [
    OnboardingPage(
      eyebrow: 'Live signals',
      title: 'See where demand is building before other drivers do.',
      detail:
          'RidePlanr brings flights, trains, events, weather, and lifestyle hotspots into one simple view so you can position earlier, not react later.',
      icon: Icons.wifi_tethering,
      accentColor: AppTheme.cyan,
      highlights: ['Flights', 'Trains', 'Events', 'Weather'],
    ),
    OnboardingPage(
      eyebrow: 'Better moves',
      title: 'Know your best nearby move for the next few hours.',
      detail:
          'We rank nearby spots by timing, distance, and potential so you can focus on the strongest move instead of scanning the whole city yourself.',
      icon: Icons.navigation,
      accentColor: AppTheme.gold,
      highlights: [
        'Best nearby move',
        'Busiest window',
        'Time to destination',
        'Map view',
      ],
    ),
    OnboardingPage(
      eyebrow: 'Stay ahead',
      title: 'Save spots, get reminders, and move at the right time.',
      detail:
          'Use reminders and planning tools to leave early, arrive on time, and make smarter positioning decisions through the day.',
      icon: Icons.notifications_active,
      accentColor: AppTheme.mint,
      highlights: ['Reminders', 'Planning', 'Live map', 'Next move'],
    ),
  ];

  bool get isLastPage => _currentIndex == pages.length - 1;

  void advance() {
    if (isLastPage) return;
    _currentIndex += 1;
    notifyListeners();
  }
}
