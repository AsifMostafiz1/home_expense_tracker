import 'package:flutter_test/flutter_test.dart';

import 'package:demo_project/presentation/settings/model/app_config_model.dart';
import 'package:demo_project/services/daily_reminder_service.dart';

/// The reminder's two pieces of arithmetic and the sentence it ends up
/// saying. Everything else in the service talks to Firestore or the OS; these
/// are the parts that can be wrong on their own.
void main() {
  group('the hour the reminder is armed for', () {
    test('is today when the hour is still ahead', () {
      final DateTime next = DailyReminderService.nextOccurrence(
        18,
        0,
        from: DateTime(2026, 8, 25, 9, 30),
      );
      expect(next, DateTime(2026, 8, 25, 18, 0));
    });

    test('is tomorrow once the hour has passed', () {
      final DateTime next = DailyReminderService.nextOccurrence(
        18,
        0,
        from: DateTime(2026, 8, 25, 20, 15),
      );
      expect(next, DateTime(2026, 8, 26, 18, 0));
    });

    /// The moment itself counts as gone: arming for it would mean a delay of
    /// zero, and a reminder that fires the instant an admin saves.
    test('is tomorrow when the clock reads exactly the hour', () {
      final DateTime next = DailyReminderService.nextOccurrence(
        18,
        0,
        from: DateTime(2026, 8, 25, 18, 0),
      );
      expect(next, DateTime(2026, 8, 26, 18, 0));
    });

    test('rolls the month and the year over', () {
      expect(
        DailyReminderService.nextOccurrence(6, 30,
            from: DateTime(2026, 12, 31, 23, 50)),
        DateTime(2027, 1, 1, 6, 30),
      );
    });
  });

  group('a wake-up that is not on time', () {
    test('is shown when it lands on the hour', () {
      expect(
        DailyReminderService.isOnTime('18:00', at: DateTime(2026, 8, 25, 18, 0)),
        isTrue,
      );
    });

    test('is shown when the OS is a little late', () {
      expect(
        DailyReminderService.isOnTime('18:00',
            at: DateTime(2026, 8, 25, 19, 30)),
        isTrue,
      );
    });

    /// Past this the evening has moved on, and "today's meals" is no longer
    /// news worth waking somebody for.
    test('is dropped when the OS is hours late', () {
      expect(
        DailyReminderService.isOnTime('18:00',
            at: DateTime(2026, 8, 25, 23, 30)),
        isFalse,
      );
    });

    test('is dropped when it arrives long before the hour', () {
      expect(
        DailyReminderService.isOnTime('18:00', at: DateTime(2026, 8, 25, 9, 0)),
        isFalse,
      );
    });
  });

  group('what the reminder says', () {
    const DailyMealSummary summary = DailyMealSummary(
      eating: [MealShare('Karim', 1), MealShare('Rahim', 2)],
      skipping: ['Jasim'],
    );

    test('counts the meals rather than the people', () {
      // Two people, three meals — the number a cook needs is the second one.
      expect(summary.total, 3);
      expect(summary.describe(bengali: false), startsWith('3 meals today'));
    });

    test('names everyone who is eating, with their share', () {
      final String body = summary.describe(bengali: false);
      expect(body, contains('Karim 1'));
      expect(body, contains('Rahim 2'));
    });

    /// The half of the message that is easy to leave out and the most useful:
    /// somebody who forgot to put their meal in wants to know before dinner
    /// is cooked without them.
    test('says who has no meal down', () {
      expect(summary.describe(bengali: false), contains('No meal: Jasim.'));
      // Only the wording around them is translated — the names are whatever
      // the members typed when they signed up.
      expect(summary.describe(bengali: true), contains('মিল নেই: Jasim।'));
      expect(summary.describe(bengali: true), startsWith('আজ 3টি মিল'));
    });

    test('leaves out the second half when nobody is missing', () {
      const DailyMealSummary everyone = DailyMealSummary(
        eating: [MealShare('Karim', 1)],
        skipping: [],
      );
      expect(everyone.describe(bengali: false), isNot(contains('No meal')));
      expect(everyone.describe(bengali: false), '1 meal today — Karim 1.');
    });

    test('says so plainly when the house is not eating in', () {
      const DailyMealSummary none =
          DailyMealSummary(eating: [], skipping: ['Karim', 'Rahim']);
      expect(none.total, 0);
      expect(none.describe(bengali: false), 'No one has a meal today.');
      expect(none.describe(bengali: true), 'আজ কারও মিল নেই।');
    });
  });

  group('the hour as it is stored', () {
    test('reads a plain HH:mm', () {
      expect(AppConfigModel.hourOf('18:30'), 18);
      expect(AppConfigModel.minuteOf('18:30'), 30);
    });

    /// A malformed value must not take the reminder down for the whole house
    /// — the job that reads this runs with nobody around to correct it.
    test('falls back rather than throwing on nonsense', () {
      for (final String bad in ['', '25:00', '18:61', 'six o clock', '18']) {
        expect(AppConfigModel.normalizeTime(bad),
            AppConfigModel.defaultReminderTime,
            reason: '"$bad" should have fallen back');
      }
      expect(AppConfigModel.normalizeTime(null),
          AppConfigModel.defaultReminderTime);
    });

    test('pads a single-digit hour back out', () {
      expect(AppConfigModel.normalizeTime('6:5'), '06:05');
    });
  });
}
