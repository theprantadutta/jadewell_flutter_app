import 'package:material_ui/material_ui.dart';

/// Game board (screens 03-09).
class GameScreen extends StatelessWidget {
  const GameScreen({super.key, required this.layoutId, this.daily = false});

  final String layoutId;

  /// Today's daily board (seed from the daily, ranked first clear).
  final bool daily;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: Text('GameScreen $layoutId')));
}
