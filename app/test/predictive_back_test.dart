import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:piuma_mail/design/theme.dart';
import 'package:piuma_mail/inbox/inbox_screen.dart';
import 'package:piuma_mail/inbox/message_list.dart';
import 'package:piuma_mail/inbox/reader.dart';
import 'package:piuma_mail/mail/demo_source.dart';
import 'package:piuma_mail/main.dart';
import 'package:piuma_mail/widgets/predictive_back.dart';
import 'package:piuma_mail/widgets/route.dart';

final _now = DateTime(2026, 10, 15, 10, 30);

/// Android's back gesture, as the system sends it.
Future<void> _gesture(WidgetTester tester, String method, [double? p]) async {
  final message = const StandardMethodCodec().encodeMethodCall(
    MethodCall(method, <String, dynamic>{
      if (p != null) ...{
        'touchOffset': <double>[5, 300],
        'progress': p,
        'swipeEdge': 0,
      },
    }),
  );
  await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/backgesture',
    message,
    (_) {},
  );
  await tester.pump();
}

Future<void> _start(WidgetTester tester) =>
    _gesture(tester, 'startBackGesture', 0);
Future<void> _move(WidgetTester tester, double p) =>
    _gesture(tester, 'updateBackGestureProgress', p);
Future<void> _commit(WidgetTester tester) =>
    _gesture(tester, 'commitBackGesture');
Future<void> _cancel(WidgetTester tester) =>
    _gesture(tester, 'cancelBackGesture');

double _scaleOf(WidgetTester tester, Finder child) {
  return tester
      .widgetList<Transform>(
        find.ancestor(of: child, matching: find.byType(Transform)),
      )
      .map((t) => t.transform.entry(0, 0))
      .reduce((a, b) => a < b ? a : b);
}

Widget _layers(List<String> names, VoidCallback onBack) => Theme(
  data: buildPiumaTheme(Brightness.light),
  child: Directionality(
    textDirection: TextDirection.ltr,
    child: PhoneLayers(
      layers: [
        for (final n in names) KeyedSubtree(key: ValueKey(n), child: Text(n)),
      ],
      onBack: onBack,
    ),
  ),
);

void main() {
  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets('the top layer follows the gesture and shows the one below', (
    tester,
  ) async {
    var backs = 0;
    await tester.pumpWidget(_layers(['list', 'reader'], () => backs++));
    expect(find.text('list'), findsNothing);

    await _start(tester);
    await _move(tester, 0.5);
    expect(find.text('list'), findsOneWidget);
    expect(_scaleOf(tester, find.text('reader')), closeTo(0.92, 0.001));

    await _cancel(tester);
    expect(find.text('list'), findsNothing);
    expect(_scaleOf(tester, find.text('reader')), 1);
    expect(backs, 0);

    await _start(tester);
    await _move(tester, 0.6);
    await _commit(tester);
    await tester.pumpAndSettle();
    expect(backs, 1);
    // Back did nothing here: the page comes back whole.
    expect(find.text('list'), findsNothing);
    expect(_scaleOf(tester, find.text('reader')), 1);
  }, variant: android);

  testWidgets('one layer leaves the gesture to the system', (tester) async {
    await tester.pumpWidget(_layers(['list'], () {}));
    await _start(tester);
    await _move(tester, 0.5);
    expect(_scaleOf(tester, find.text('list')), 1);
  }, variant: android);

  testWidgets('with reduce motion nothing follows the finger', (tester) async {
    await tester.pumpWidget(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: _layers(['list', 'reader'], () {}),
      ),
    );
    await _start(tester);
    await _move(tester, 0.5);
    expect(find.text('list'), findsNothing);
    expect(_scaleOf(tester, find.text('reader')), 1);
  }, variant: android);

  testWidgets('the gesture closes a message on the phone, the list waits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final source = DemoMailSource(now: _now);
    await tester.pumpWidget(
      PiumaApp(
        home: (_, _) =>
            InboxScreen(source: source, onAddAccount: () {}, now: () => _now),
      ),
    );
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byType(InboxRowTile),
        matching: find.text('Dinner on Friday?'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsOneWidget);
    expect(find.byType(MessageList), findsNothing);

    await _start(tester);
    await _move(tester, 0.4);
    // The list shows around the message as it was left.
    expect(find.byType(MessageList), findsOneWidget);
    await _commit(tester);
    await tester.pumpAndSettle();
    expect(find.byType(Reader), findsNothing);
    expect(find.byType(MessageList), findsOneWidget);
  }, variant: android);

  testWidgets('a full screen follows the gesture back to the one below', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      WidgetsApp(
        color: const Color(0xFF000000),
        builder: (context, _) => Navigator(
          key: navigator,
          onGenerateRoute: (_) => PiumaRoute<void>(
            instant: false,
            builder: (_) => const Text('home'),
          ),
        ),
      ),
    );
    navigator.currentState!.push(
      PiumaRoute<void>(instant: false, builder: (_) => const Text('settings')),
    );
    await tester.pumpAndSettle();
    expect(find.text('home'), findsNothing);

    await _start(tester);
    await _move(tester, 0.5);
    expect(find.text('home'), findsOneWidget);
    expect(_scaleOf(tester, find.text('settings')), closeTo(0.92, 0.001));

    await _commit(tester);
    await tester.pumpAndSettle();
    expect(find.text('settings'), findsNothing);
    expect(find.text('home'), findsOneWidget);
  }, variant: android);
}
