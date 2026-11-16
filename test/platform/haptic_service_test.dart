import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jadewell_flutter_app/platform/haptics/haptic_service_impl.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late List<String> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform,
        (call) async {
      if (call.method == 'HapticFeedback.vibrate') calls.add(call.arguments as String);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('semantic methods map to HapticFeedback types', () async {
    final h = HapticServiceImpl()
      ..light()
      ..medium()
      ..heavy()
      ..selection()
      ..success();
    await Future<void>.delayed(Duration.zero);
    expect(calls, [
      'HapticFeedbackType.lightImpact',
      'HapticFeedbackType.mediumImpact',
      'HapticFeedbackType.heavyImpact',
      'HapticFeedbackType.selectionClick',
      'HapticFeedbackType.mediumImpact', // success on Android (test platform)
    ]);
    expect(h.enabled, isTrue);
  });

  testWidgets('selectionError is two light ticks 60 ms apart', (tester) async {
    HapticServiceImpl().selectionError();
    await tester.pump();
    expect(calls, ['HapticFeedbackType.lightImpact']);
    await tester.pump(const Duration(milliseconds: 59));
    expect(calls, hasLength(1));
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, ['HapticFeedbackType.lightImpact', 'HapticFeedbackType.lightImpact']);
  });

  testWidgets('disabled: nothing fires, and a pending second tick is cancelled', (tester) async {
    final h = HapticServiceImpl()..selectionError();
    await tester.pump();
    h.setEnabled(false);
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, hasLength(1));

    h
      ..light()
      ..medium()
      ..heavy()
      ..selection()
      ..selectionError()
      ..success();
    await tester.pump(const Duration(milliseconds: 100));
    expect(calls, hasLength(1));

    h
      ..setEnabled(true)
      ..light();
    await tester.pump();
    expect(calls, hasLength(2));
  });
}
