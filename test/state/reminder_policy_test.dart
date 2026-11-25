import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/state/reminder_policy.dart';

void main() {
  const policy = ReminderPolicy();

  group('first fire time: 24 h later, clamped into 10:00–20:00 local', () {
    for (final (now, expected) in [
      (DateTime(2026, 11, 25, 14, 37), DateTime(2026, 11, 26, 14, 37)), // inside the window: same time tomorrow
      (DateTime(2026, 11, 25, 10, 0), DateTime(2026, 11, 26, 10, 0)), // the edges are inside
      (DateTime(2026, 11, 25, 20, 0), DateTime(2026, 11, 26, 20, 0)),
      (DateTime(2026, 11, 25, 20, 1), DateTime(2026, 11, 26, 20, 0)), // evening → 20:00
      (DateTime(2026, 11, 25, 23, 30), DateTime(2026, 11, 26, 20, 0)),
      (DateTime(2026, 11, 25, 1, 0), DateTime(2026, 11, 26, 10, 0)), // night → 10:00 the next day
      (DateTime(2026, 11, 25, 9, 59), DateTime(2026, 11, 26, 10, 0)),
      (DateTime(2026, 12, 31, 22, 0), DateTime(2027, 1, 1, 20, 0)), // year rollover
    ]) {
      test('$now → $expected', () => expect(policy.firstFireTime(now), expected));
    }

    test('always the next calendar day, between 14 h and 34 h ahead', () {
      for (var m = 0; m < 24 * 60; m += 7) {
        final now = DateTime(2026, 11, 25).add(Duration(minutes: m));
        final at = policy.firstFireTime(now);
        expect(at.day, 26, reason: '$now');
        expect(at.hour, inInclusiveRange(10, 20), reason: '$now');
        expect(at.difference(now).inHours, inInclusiveRange(14, 34), reason: '$now');
      }
    });
  });

  group('plan', () {
    List<PlannedReminder> plan({
      DateTime? now,
      bool enabled = true,
      bool permitted = true,
      int gamesPlayed = 1,
      int streak = 0,
      bool clearedToday = false,
    }) =>
        policy.plan(
          now: now ?? DateTime(2026, 11, 25, 18, 15),
          enabled: enabled,
          permitted: permitted,
          gamesPlayed: gamesPlayed,
          streak: streak,
          clearedToday: clearedToday,
        );

    test('nag limit: at most 3 in a row, one per day at the same time', () {
      final p = plan();
      expect(p.map((r) => r.day), [1, 2, 3]);
      expect(p.map((r) => r.at), [
        DateTime(2026, 11, 26, 18, 15),
        DateTime(2026, 11, 27, 18, 15),
        DateTime(2026, 11, 28, 18, 15),
      ]);
      expect(const ReminderPolicy(maxUnanswered: 1).plan(
        now: DateTime(2026, 11, 25, 18, 15),
        enabled: true,
        permitted: true,
        gamesPlayed: 1,
        streak: 0,
        clearedToday: false,
      ), hasLength(1));
    });

    test('nothing when the setting is off, the OS says no, or no board was played yet', () {
      expect(plan(enabled: false), isEmpty);
      expect(plan(permitted: false), isEmpty);
      expect(plan(gamesPlayed: 0), isEmpty);
    });

    test('copy: the streak line after today\'s daily was cleared on a 2+ day streak', () {
      final p = plan(streak: 3, clearedToday: true);
      expect(p.map((r) => r.message), [ReminderMessage.streak, ReminderMessage.comeback, ReminderMessage.comeback]);
      expect(p.first.streak, 3);
    });

    test('copy: the daily line without a streak worth naming or before today\'s clear', () {
      expect(plan(streak: 1, clearedToday: true).first.message, ReminderMessage.daily);
      expect(plan(streak: 5, clearedToday: false).first.message, ReminderMessage.daily);
      expect(plan().first.message, ReminderMessage.daily);
    });

    test('payload round-trips', () {
      final r = plan(streak: 4, clearedToday: true).first;
      expect(r.payload, 'reminder:1:streak');
      final parsed = ReminderPayload.parse(r.payload)!;
      expect((parsed.day, parsed.message), (1, ReminderMessage.streak));
      expect(ReminderPayload.parse('other:1:daily'), isNull);
      expect(ReminderPayload.parse('reminder:x:daily'), isNull);
      expect(ReminderPayload.parse('reminder:1:nope'), isNull);
      expect(ReminderPayload.parse(null), isNull);
    });
  });

  group('prompt policy', () {
    const p = ReminderPromptPolicy();
    bool offer({bool supported = true, bool decided = false, bool enabled = true, bool permitted = false, int clears = 1}) =>
        p.shouldOffer(supported: supported, alreadyDecided: decided, enabled: enabled, permitted: permitted, boardsCleared: clears);

    test('after the 1st or 2nd clear only', () {
      expect(offer(clears: 0), isFalse);
      expect(offer(clears: 1), isTrue);
      expect(offer(clears: 2), isTrue);
      expect(offer(clears: 3), isFalse);
    });

    test('never once decided, when off, when already allowed, or unsupported', () {
      expect(offer(decided: true), isFalse);
      expect(offer(enabled: false), isFalse);
      expect(offer(permitted: true), isFalse);
      expect(offer(supported: false), isFalse);
    });
  });
}
