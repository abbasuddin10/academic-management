import 'package:academy_management/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('MyApp renders the provided initial screen', (tester) async {
    await tester.pumpWidget(
      const MyApp(
        initialScreen: Scaffold(body: Center(child: Text('initial screen'))),
      ),
    );

    expect(find.text('initial screen'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
