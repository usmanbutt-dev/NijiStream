import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nijistream/app.dart';

void main() {
  testWidgets('App renders NijiStream title', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(child: NijiStreamApp()),
    );

    // Verify the app title renders
    expect(find.text('Niji'), findsOneWidget);
    expect(find.text('Stream'), findsOneWidget);
  });
}
