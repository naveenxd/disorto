import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:distorto/screens/home_screen.dart';

void main() {
  testWidgets('home screen shows the primary wallpaper action', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: HomeScreen()));
    await tester.pumpAndSettle();

    expect(find.text('distorto'), findsOneWidget);
    expect(find.text('Select Wallpaper'), findsOneWidget);
  });
}
