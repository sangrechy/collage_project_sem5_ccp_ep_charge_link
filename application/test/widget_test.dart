import 'package:flutter_test/flutter_test.dart';
import 'package:application/main.dart';

void main() {
  testWidgets('CHARGE LINK app loads', (WidgetTester tester) async {
    await tester.pumpWidget(const ChargeLinkApp());

    expect(find.text('CHARGE LINK'), findsOneWidget);
    expect(find.text('Smart Charge Box'), findsOneWidget);
  });
}