import 'package:bangbang/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the Bang Bang home screen', (tester) async {
    await tester.pumpWidget(const BangBangApp());
    await tester.pump(const Duration(milliseconds: 2500));
    await tester.pumpAndSettle();
    expect(find.text('CHƠI ONLINE'), findsOneWidget);
    expect(find.text('LUẬT CHƠI'), findsOneWidget);
    expect(find.text('NHIỆM VỤ'), findsOneWidget);
  });
}
