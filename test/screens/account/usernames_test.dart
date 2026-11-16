import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/ui/screens/account/account_screen.dart';

void main() {
  test('username rule mirrors the backend', () {
    for (final ok in ['Mei', 'tile_whisper_99', 'A2345678901234567890']) {
      expect(Usernames.isValid(ok), isTrue, reason: ok);
    }
    for (final bad in ['ab', '1abc', '_abc', 'has space', 'A23456789012345678901', 'émile']) {
      expect(Usernames.isValid(bad), isFalse, reason: bad);
    }
  });
}
