
import 'package:flutter_test/flutter_test.dart';
import 'package:skaven/main.dart';

void main() {
  testWidgets('SKAVEN dashboard renders', (tester) async {
    await tester.pumpWidget(const SkavenApp());

    expect(find.text('SKAVEN'), findsOneWidget);
    expect(find.text('TARGET RECONNAISSANCE'), findsOneWidget);
    expect(find.text('START SCAN'), findsOneWidget);
    expect(find.text('RECONNAISSANCE OVERVIEW'), findsOneWidget);
    expect(find.text('INTELLIGENCE MODULES'), findsOneWidget);
  });

  testWidgets('SKAVEN navigation renders', (tester) async {
    await tester.pumpWidget(const SkavenApp());

    expect(find.text('Scanner'), findsOneWidget);
    expect(find.text('Findings'), findsOneWidget);
    expect(find.text('Intel'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
  });
}
