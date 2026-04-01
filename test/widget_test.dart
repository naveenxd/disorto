import 'package:flutter_test/flutter_test.dart';

import 'package:distorto/main.dart';

void main() {
  testWidgets('app shows the home wordmark on normal launch', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const DistortoApp());
    await tester.pumpAndSettle();

    expect(find.text('distorto'), findsOneWidget);
    expect(find.text('OS-style wallpaper effects\nfor every phone.'), findsOneWidget);
    expect(find.text('Select Wallpaper'), findsOneWidget);
  });
}
