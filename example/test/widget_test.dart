import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:async_request_manager_example/main.dart';

void main() {
  // Advance fake time by [duration] then drain one microtask batch.
  Future<void> advance(WidgetTester t, Duration duration) async {
    await t.pump(duration);
    await t.pump();
  }

  // Flush all remaining fake timers. The longest simulated delay is 10 s, so
  // 11 s is sufficient to drain every pending timer without real wall-clock cost.
  Future<void> drain(WidgetTester t) => t.pump(const Duration(seconds: 11));

  group('initial state', () {
    testWidgets('renders title and idle status', (tester) async {
      await tester.pumpWidget(const App());

      expect(find.text('AsyncRequestManager Demo'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Tap a button above to run a demo.'), findsOneWidget);
    });

    testWidgets('shows all five action buttons', (tester) async {
      await tester.pumpWidget(const App());

      for (final label in const [
        'Join',
        'Cancel Previous',
        'Parallel',
        'Timeout',
        'Cancel All',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '"$label" button missing');
      }
    });
  });

  group('clear log', () {
    testWidgets('empties the log and restores placeholder', (tester) async {
      await tester.pumpWidget(const App());

      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.text('Tap a button above to run a demo.'), findsNothing);

      await tester.tap(find.byTooltip('Clear log'));
      await tester.pump();
      expect(find.text('Tap a button above to run a demo.'), findsOneWidget);

      await drain(tester); // drain the in-flight 1500 ms join timer
    });
  });

  group('join strategy', () {
    testWidgets('immediately logs section header and running count', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Join'));
      await tester.pump();

      expect(find.textContaining('── join() ──'), findsOneWidget);
      expect(find.textContaining('key "fetch-user"'), findsOneWidget);
      // Only one real operation runs despite two callers.
      expect(find.textContaining('running=1'), findsOneWidget);

      await drain(tester); // drain the in-flight 1500 ms timer
    });

    testWidgets('both futures return the identical result', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Join'));
      await tester.pump();

      // 1500 ms default API delay — pump past it.
      await advance(tester, const Duration(milliseconds: 1600));

      expect(find.textContaining('f1 →'), findsOneWidget);
      expect(find.textContaining('f2 →'), findsOneWidget);
      expect(find.textContaining('ran once'), findsOneWidget);
      // No pending timers; 1600 ms pump consumed the 1500 ms delay.
    });

    testWidgets('status bar returns to Idle after completion', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Join'));
      await tester.pump();
      expect(find.text('Idle'), findsNothing);

      await advance(tester, const Duration(milliseconds: 1600));
      expect(find.text('Idle'), findsOneWidget);
      // No pending timers; 1600 ms pump consumed the 1500 ms delay.
    });
  });

  group('cancelPrevious strategy', () {
    testWidgets('logs first request start immediately', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Cancel Previous'));
      await tester.pump();

      expect(find.textContaining('cancelPrevious()'), findsOneWidget);
      expect(find.textContaining('First request started'), findsOneWidget);

      await drain(tester); // drain the in-flight 5000 ms underlying timer
    });

    testWidgets('cancels first request when second arrives', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Cancel Previous'));
      await tester.pump();

      // Advance past the 400 ms internal delay that triggers the second call.
      await advance(tester, const Duration(milliseconds: 500));

      expect(find.textContaining('Second request cancels first'), findsOneWidget);
      expect(find.textContaining('Cancelled'), findsWidgets);

      // Drain the 5000 ms underlying first-request timer and the 800 ms
      // second-request timer (both still pending; CancelableOperation does
      // not cancel the underlying Future).
      await drain(tester);
    });

    testWidgets('second request completes with its own result', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Cancel Previous'));
      await tester.pump();

      await advance(tester, const Duration(milliseconds: 500)); // past 400 ms wait
      await advance(tester, const Duration(milliseconds: 900)); // past 800 ms request

      expect(find.textContaining('second-search'), findsOneWidget);

      await drain(tester); // drain the remaining ~3600 ms of the first request's timer
    });
  });

  group('parallel strategy', () {
    testWidgets('reports concurrent count of 3', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Parallel'));
      await tester.pump();

      expect(find.textContaining('parallel()'), findsOneWidget);
      expect(find.textContaining('Concurrent count: 3'), findsOneWidget);

      await drain(tester); // drain the in-flight 900/600/1100 ms timers
    });

    testWidgets('all three results arrive after the slowest completes', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Parallel'));
      await tester.pump();

      // Slowest operation is page-3 at 1100 ms.
      await advance(tester, const Duration(milliseconds: 1200));

      expect(find.textContaining('page-1'), findsOneWidget);
      expect(find.textContaining('page-2'), findsOneWidget);
      expect(find.textContaining('page-3'), findsOneWidget);
      // No pending timers; 1200 ms pump consumed all three delays.
    });
  });

  group('timeout', () {
    testWidgets('TimeoutException is caught and logged after 600 ms', (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Timeout'));
      await tester.pump();

      expect(find.textContaining('600 ms timeout'), findsOneWidget);

      // Advance past the 600 ms timeout threshold.
      await advance(tester, const Duration(milliseconds: 700));

      expect(find.textContaining('TimeoutException caught'), findsOneWidget);

      // Drain the still-running 3 s underlying request (timeout only abandons
      // the wait; the underlying Future.delayed continues).
      await drain(tester);
    });
  });

  group('cancelAll', () {
    testWidgets('starts 3 tasks, cancels all, and reports totalRunning=0',
        (tester) async {
      await tester.pumpWidget(const App());
      await tester.tap(find.text('Cancel All'));
      await tester.pump();

      expect(find.textContaining('cancelAll()'), findsOneWidget);
      expect(find.textContaining('totalRunning=3'), findsOneWidget);

      // Advance past the 300 ms settle delay before cancelAll() is called.
      await advance(tester, const Duration(milliseconds: 400));

      expect(find.textContaining('Cancelled'), findsWidgets);
      expect(find.textContaining('cancelAll() done'), findsOneWidget);
      expect(find.textContaining('totalRunning=0'), findsOneWidget);

      // Drain the 3 × 10 s underlying timers (cancelled at the manager level
      // but the underlying Future.delayed timers are still pending).
      await drain(tester);
    });
  });
}
