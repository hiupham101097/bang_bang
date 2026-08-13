import 'package:bangbang/data/online_room_repository.dart';
import 'package:bangbang/main.dart';
import 'package:bangbang/ui/bang_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('home redesign visual reference', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: bangTheme(),
        home: const HomeScreen(
          repository: UnavailableOnlineRoomRepository('visual QA'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('CHƠI ONLINE'), findsOneWidget);
    expect(find.text('LUẬT CHƠI'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byType(HomeScreen),
      matchesGoldenFile('goldens/home_redesign.png'),
    );
  });
}
