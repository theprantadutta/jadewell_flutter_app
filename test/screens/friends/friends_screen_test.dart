import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/data/api/api_result.dart';
import 'package:jadewell_flutter_app/data/repositories/social_repository.dart';
import 'package:jadewell_flutter_app/state/session_controller.dart';
import 'package:jadewell_flutter_app/state/social_providers.dart';
import 'package:jadewell_flutter_app/ui/screens/friends/friends_screen.dart';
import 'package:material_ui/material_ui.dart' show ValueKey;

import '../settings/harness.dart';

const _mira = PlayerSummary(userId: 'u2', displayName: 'Mira K.', username: 'mira_k');
const _kofi = PlayerSummary(userId: 'u3', displayName: 'Kofi A.');

void main() {
  Future<FakeSocialRepository> pump(WidgetTester tester, FakeSocialRepository repo) async {
    await pumpScreen(
      tester,
      const FriendsScreen(),
      size: const Size(390, 1400),
      overrides: [
        sessionProvider.overrideWith(() => FakeSession(const BackendSession(identity: guestIdentity, user: testUser))),
        socialRepositoryProvider.overrideWithValue(repo),
      ],
    );
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('shows your code, requests and friends', (tester) async {
    await pump(
      tester,
      FakeSocialRepository(
        friendList: [const Friend(player: _mira)],
        incoming: [const FriendRequest(id: 'r1', player: _kofi)],
      ),
    );
    expect(find.text('JW-7K3P9Q'), findsOneWidget);
    expect(find.text('REQUESTS'), findsOneWidget);
    expect(find.text('Kofi A.'), findsOneWidget);
    expect(find.text('FRIENDS · 1'), findsOneWidget);
    expect(find.text('Mira K.'), findsOneWidget);
    expect(find.text('@mira_k'), findsOneWidget);
  });

  testWidgets('accepting a request moves them to friends', (tester) async {
    final repo = await pump(tester, FakeSocialRepository(incoming: [const FriendRequest(id: 'r1', player: _kofi)]));
    await tester.tap(find.text('Accept'));
    await tester.pumpAndSettle();
    expect(repo.friendList.single.userId, 'u3');
    expect(find.text('REQUESTS'), findsNothing);
    expect(find.text('FRIENDS · 1'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('the code field normalises input and sends the canonical code', (tester) async {
    final repo = await pump(tester, FakeSocialRepository());
    await tester.enterText(find.byKey(const ValueKey('friends-code-field')).last, 'jw-oil23q');
    await tester.pump();
    expect(find.text('JW-01123Q'), findsOneWidget);
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(repo.sent, ['JW-01123Q']);
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('invalid, own and unknown codes show friendly errors', (tester) async {
    await pump(tester, FakeSocialRepository());
    final field = find.byKey(const ValueKey('friends-code-field')).last;

    await tester.enterText(field, '7K3');
    await tester.tap(find.text('Send request'));
    await tester.pump();
    expect(find.text('Codes look like JW-7K3P9Q.'), findsOneWidget);

    await tester.enterText(field, '7k3p9q');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.text("That's your own code."), findsOneWidget);

    await tester.enterText(field, 'nnnnnn');
    await tester.tap(find.text('Send request'));
    await tester.pumpAndSettle();
    expect(find.text('No player has that code.'), findsOneWidget);
  });

  testWidgets('missing endpoint shows a retry card, never crashes', (tester) async {
    final repo = await pump(tester, FakeSocialRepository(failWith: ApiFailure.validation, failStatus: 404));
    expect(find.text('Friends are on their way'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
    // Your code still works offline.
    expect(find.text('JW-7K3P9Q'), findsOneWidget);

    repo.failWith = null;
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Friends are on their way'), findsNothing);
    expect(find.text('FRIENDS · 0'), findsOneWidget);
  });

  testWidgets('offline shows the offline card', (tester) async {
    await pump(tester, FakeSocialRepository(failWith: ApiFailure.offlineOrTransport));
    expect(find.text("You're offline"), findsOneWidget);
  });

  testWidgets('removing a friend asks first', (tester) async {
    final repo = await pump(tester, FakeSocialRepository(friendList: [const Friend(player: _mira)]));
    await tester.tap(find.bySemanticsLabel('Remove Mira K.'));
    await tester.pumpAndSettle();
    expect(find.text('Remove Mira K.?'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(repo.friendList, isEmpty);
    expect(find.text('FRIENDS · 0'), findsOneWidget);
  });

  test('formatter keeps the JW- prefix and caps the length', () {
    const f = FriendCodeInputFormatter();
    TextEditingValue type(String old, String next) =>
        f.formatEditUpdate(TextEditingValue(text: old), TextEditingValue(text: next));
    expect(type('', '7').text, 'JW-7');
    expect(type('JW-7', 'JW-7k').text, 'JW-7K');
    expect(type('JW-7K3P9Q', 'JW-7K3P9QX').text, 'JW-7K3P9Q');
    expect(type('JW-7', 'JW-').text, '', reason: 'deleting into the prefix clears it');
    expect(type('', 'https://jadewell.pranta.dev/f/JW-7K3P9Q').text, 'JW-7K3P9Q', reason: 'pasted link');
  });
}
