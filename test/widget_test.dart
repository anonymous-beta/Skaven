
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:skaven/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('SKAVEN dashboard', () {
    testWidgets('SKAVEN dashboard renders', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      expect(find.text('SKAVEN'), findsOneWidget);
      expect(find.text('PUBLIC-SURFACE INTELLIGENCE'), findsOneWidget);
      expect(find.text('TARGET CONFIGURATION'), findsOneWidget);
      expect(find.text('START SCAN'), findsOneWidget);
      expect(find.text('SYSTEM STATUS'), findsOneWidget);
      expect(find.text('LATEST SCAN'), findsOneWidget);
    });

    testWidgets('Dashboard displays target input', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is TextField &&
              widget.decoration?.hintText == 'https://example.com',
        ),
        findsOneWidget,
      );
    });

    testWidgets('Dashboard displays scan controls', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      expect(find.text('START SCAN'), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
    });
  });

  group('SKAVEN navigation', () {
    testWidgets('SKAVEN navigation renders', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      expect(find.text('Dashboard'), findsOneWidget);
      expect(find.text('Findings'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
    });

    testWidgets('Navigation opens findings page', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Findings'));
      await tester.pumpAndSettle();

      expect(find.text('SCAN FINDINGS'), findsOneWidget);
      expect(find.text('No active report'), findsOneWidget);
    });

    testWidgets('Navigation opens history page', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      expect(find.text('SCAN HISTORY'), findsOneWidget);
      expect(find.text('No saved scans'), findsOneWidget);
    });

    testWidgets('Navigation returns to dashboard', (tester) async {
      await tester.pumpWidget(const SkavenApp());
      await tester.pumpAndSettle();

      await tester.tap(find.text('History'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Dashboard'));
      await tester.pumpAndSettle();

      expect(find.text('TARGET CONFIGURATION'), findsOneWidget);
      expect(find.text('START SCAN'), findsOneWidget);
    });
  });
}
