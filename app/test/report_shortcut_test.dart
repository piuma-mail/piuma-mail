import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/feedback/report_sheet.dart';

void main() {
  testWidgets('report shortcut opens above another route', (tester) async {
    final source = DemoMailSource();
    await tester.pumpWidget(
      PiumaApp(
        reportSource: source,
        home: (_, _) => Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      const Scaffold(body: TextField(autofocus: true)),
                ),
              ),
              child: const Text('Settings'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyR);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.byType(ReportSheet), findsOneWidget);
    expect(find.text('Attach'), findsOneWidget);
  });
}
