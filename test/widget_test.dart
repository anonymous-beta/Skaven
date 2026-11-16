
import 'package:flutter_test/flutter_test.dart';
import 'package:skaven/main.dart';

void main() {
  testWidgets('SKAVEN dashboard renders', (tester) async {
    await tester.pumpWidget(const SkavenApp());

    expect(find.text('SKAVEN'), findsOneWidget);
    expect(find.text('TARGET RECONNAISSANCE'), findsOneWidget);
    expect(find.text('START SCAN'), findsOneWidget);
    expect(find.text('RECON ENGINE ONLINE'), findsOneWidget);
  });
}
