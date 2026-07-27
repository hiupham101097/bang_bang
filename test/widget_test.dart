import 'package:bangbang/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the Bang Bang home screen', (tester) async {
    await tester.pumpWidget(const BangBangApp());
    expect(find.text('BANG BANG'), findsOneWidget);
    expect(find.text('BẮT ĐẦU'), findsOneWidget);
    expect(find.text('NHIỆM VỤ'), findsOneWidget);
    expect(find.text('HƯỚNG DẪN'), findsOneWidget);
  });
}
