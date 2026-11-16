import 'package:flutter/widgets.dart';

/// Provides the in-app "Reduce motion" setting to the widget tree.
///
/// Components resolve their effective flag with [JwReduceMotion.of]: an
/// explicit widget parameter wins, then this scope, then the OS flag
/// (`MediaQuery.disableAnimations`).
class JwReduceMotion extends InheritedWidget {
  const JwReduceMotion({super.key, required this.enabled, required super.child});

  final bool enabled;

  /// Whether motion should be reduced here. [override] (a widget's own
  /// `reduceMotion` parameter) wins when non-null.
  static bool of(BuildContext context, [bool? override]) {
    if (override != null) return override;
    final scope = context.dependOnInheritedWidgetOfExactType<JwReduceMotion>();
    if (scope != null && scope.enabled) return true;
    return MediaQuery.maybeDisableAnimationsOf(context) ?? false;
  }

  @override
  bool updateShouldNotify(JwReduceMotion oldWidget) => oldWidget.enabled != enabled;
}
