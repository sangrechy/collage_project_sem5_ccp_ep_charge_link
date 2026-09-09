import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:application_v3/main.dart';

void main() {
  testWidgets('ChargeLinkApp smoke test in mock mode', (WidgetTester tester) async {
    await tester.pumpWidget(const ChargeLinkApp(useMock: true));
    await tester.pump(const Duration(seconds: 2));

    // Verify app bar title and bottom navigation exist
    expect(find.text('CHARGE LINK'), findsWidgets);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Device'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    // Unmount app to cancel all timers and cleanly dispose
    await tester.pumpWidget(const SizedBox());
  });
}
