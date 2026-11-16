import 'package:material_ui/material_ui.dart';

/// Board cleared (screen 10).
class ClearedScreen extends StatelessWidget {
  const ClearedScreen({super.key, required this.layoutId});

  final String layoutId;

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: const Text('ClearedScreen')));
}
