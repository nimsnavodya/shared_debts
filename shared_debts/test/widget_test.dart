import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_debts/app.dart';

void main() {
  testWidgets('Validation error when group name is empty', (tester) async {
    await tester.pumpWidget(const SharedDebtsApp());
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    // Tap Create with empty input
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    expect(find.text('Enter a group name'), findsOneWidget);
    expect(find.text('Create a group'), findsOneWidget);
  });

  testWidgets('Create a Shared group', (tester) async {
    await tester.pumpWidget(const SharedDebtsApp());
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Apartment Expenses');
    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Dialog should be closed
    expect(find.text('Create a group'), findsNothing);
    // Group should be visible on page
    expect(find.text('Apartment Expenses'), findsOneWidget);
    expect(find.text('Shared group · 1 member'), findsOneWidget);
  });

  testWidgets('Create a Trip group', (tester) async {
    await tester.pumpWidget(const SharedDebtsApp());
    await tester.tap(find.text('Create group'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField), 'Ella Trip');
    await tester.tap(find.text('Trip'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create'));
    await tester.pumpAndSettle();

    // Dialog should be closed
    expect(find.text('Create a group'), findsNothing);
    // Group should be visible on page
    expect(find.text('Ella Trip'), findsOneWidget);
    expect(find.text('Trip · 1 member'), findsOneWidget);
  });
}
