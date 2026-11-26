import 'package:flutter_test/flutter_test.dart';

import 'package:driver_intel_flutter/models/app_models.dart';
import 'package:driver_intel_flutter/services/service_utilities.dart';

void main() {
  group('DriverIntelTime', () {
    test('formats immediate times as Now', () {
      expect(0.driverIntelTimeRemainingText, 'Now');
      expect((-5).driverIntelTimeRemainingText, 'Now');
      expect(0.isDriverIntelImmediateTime, isTrue);
    });

    test('formats sub-hour times in minutes', () {
      expect(45.driverIntelTimeRemainingText, 'In 45 min');
    });

    test('formats hour times', () {
      expect(60.driverIntelTimeRemainingText, 'In 1h');
      expect(90.driverIntelTimeRemainingText, 'In 1h30');
      expect(125.driverIntelTimeRemainingText, 'In 2h05');
    });
  });

  group('TimeDisplayFormat', () {
    test('12h compact time strings', () {
      expect(
        TimeDisplayFormat.twelveHour.compactTimeString(DateTime(2026, 6, 12, 18)),
        '6pm',
      );
      expect(
        TimeDisplayFormat.twelveHour
            .compactTimeString(DateTime(2026, 6, 12, 18, 5)),
        '6:05pm',
      );
      expect(
        TimeDisplayFormat.twelveHour.compactTimeString(DateTime(2026, 6, 12, 0)),
        '12am',
      );
    });

    test('24h compact time strings', () {
      expect(
        TimeDisplayFormat.twentyFourHour
            .compactTimeString(DateTime(2026, 6, 12, 18)),
        '18h',
      );
      expect(
        TimeDisplayFormat.twentyFourHour
            .compactTimeString(DateTime(2026, 6, 12, 18, 5)),
        '18:05',
      );
    });

    test('hour windows', () {
      expect(
        TimeDisplayFormat.twelveHour.formatHourWindow(startHour: 17, endHour: 19),
        '5-7pm',
      );
      expect(
        TimeDisplayFormat.twelveHour.formatHourWindow(startHour: 11, endHour: 13),
        '11am-1pm',
      );
      expect(
        TimeDisplayFormat.twentyFourHour
            .formatHourWindow(startHour: 17, endHour: 19),
        '17h-19h',
      );
    });
  });

  group('groupedArrivalWindows', () {
    test('groups arrivals into 1-hour buckets', () {
      final base = DateTime(2026, 6, 12, 18);
      final windows = groupedArrivalWindows([
        base.add(const Duration(minutes: 5)),
        base.add(const Duration(minutes: 40)),
        base.add(const Duration(minutes: 70)),
      ]);

      expect(windows.length, 2);
      expect(windows.first.arrivals.length, 2);
      expect(windows.last.arrivals.length, 1);
      expect(windows.first.end.difference(windows.first.start),
          const Duration(hours: 1));
    });

    test('returns empty for no arrivals', () {
      expect(groupedArrivalWindows([]), isEmpty);
    });
  });

  group('Opportunity JSON round-trip', () {
    test('encodes and decodes', () {
      const opportunity = Opportunity(
        id: 'test-1',
        title: 'Test',
        subtitle: 'Subtitle',
        zoneName: 'Zone',
        latitude: 25.7,
        longitude: -80.1,
        startsInMinutes: 30,
        distanceKilometers: 2.5,
        driveTimeMinutes: 10,
        potentialCustomers: 9,
        score: 80,
        categories: [SignalCategory.trains],
        recommendation: 'Go',
        detail: 'Detail',
      );

      final decoded = Opportunity.fromJson(opportunity.toJson());
      expect(decoded.id, opportunity.id);
      expect(decoded.categories, [SignalCategory.trains]);
      expect(decoded.latitude, 25.7);
    });
  });

  group('parseFlexibleDate', () {
    test('parses ISO-8601', () {
      expect(parseFlexibleDate('2026-06-12T18:20:00Z'), isNotNull);
      expect(parseFlexibleDate('2026-06-12T18:20:00.123Z'), isNotNull);
    });

    test('parses AeroDataBox UTC format', () {
      final date = parseFlexibleDate('2026-06-12 18:20Z');
      expect(date, DateTime.utc(2026, 6, 12, 18, 20));
    });
  });
}
