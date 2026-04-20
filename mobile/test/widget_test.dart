import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:focusflow_mobile/app.dart';

void main() {
  testWidgets('FocusFlowApp builds', (WidgetTester tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: FocusFlowApp(),
      ),
    );
    await tester.pump();
    expect(find.byType(FocusFlowApp), findsOneWidget);
  });
}
