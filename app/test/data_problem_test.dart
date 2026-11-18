import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/data_problem.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/links.dart';

void main() {
  testWidgets('the data problem screen offers Try again and Report', (
    tester,
  ) async {
    var retried = 0;
    final opened = <Uri>[];
    final before = openExternalLink;
    openExternalLink = (uri) async => opened.add(uri);
    addTearDown(() => openExternalLink = before);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => DataProblem(
          detail: 'database: disk I/O error',
          reportAddress: 'feedback@example.org',
          onRetry: () => retried++,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Piuma couldn’t open its data'), findsOneWidget);
    // Inherits a text style: no debug underline.
    final title = tester.widget<Text>(
      find.text('Piuma couldn’t open its data'),
    );
    final style = DefaultTextStyle.of(tester.element(find.byWidget(title)))
        .style;
    expect(style.decoration, isNot(TextDecoration.underline));
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
    await tester.tap(find.text('Report this problem'));
    expect(opened.single.scheme, 'mailto');
    expect(opened.single.path, 'feedback@example.org');
    expect(opened.single.query, contains('disk%20I%2FO%20error'));
  });

  testWidgets('on the phone it fits, with both buttons', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var retried = 0;
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            DataProblem(detail: 'x', onRetry: () => retried++),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Try again'));
    expect(retried, 1);
    expect(find.text('Report this problem'), findsOneWidget);
  });

  testWidgets('data from a newer Piuma asks for an update', (tester) async {
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) => DataProblem(detail: 'x', newer: true, onRetry: () {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('newer version of Piuma'), findsOneWidget);
  });
}
