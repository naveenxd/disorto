import 'package:flutter/material.dart';

/// Placeholder — will be fully implemented in the next step.
class EditorScreen extends StatelessWidget {
  /// Path to the image file that will be processed.
  final String imagePath;

  const EditorScreen({super.key, required this.imagePath});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text('Editor: $imagePath'),
      ),
    );
  }
}
