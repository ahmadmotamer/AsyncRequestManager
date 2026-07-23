import 'dart:async';

import 'package:async_request_manager/async_request_manager.dart';
import 'package:test/test.dart';

enum _Key { alpha, beta }

void main() {
  // ── ExecutionStrategy.join ────────────────────────────────────────────────

  group('join strategy', () {
    test('duplicate call joins in-flight operation; function runs once',
        () async {
      final manager = AsyncRequestManager<_Key>();
      var callCount = 0;

      Future<String> slowFn() async {
        callCount++;
        await Future.delayed(const Duration(milliseconds: 50));
        return 'result';
      }

      final f1 = manager.execute<String>(
        function: slowFn,
        key: _Key.alpha,
        strategy: ExecutionStrategy.join,
      );
      final f2 = manager.execute<String>(
        function: slowFn,
        key: _Key.alpha,
        strategy: ExecutionStrategy.join,
      );

      expect(await f1, 'result');
      expect(await f2, 'result');
      expect(callCount, 1);
    });

    test('sequential calls each execute independently', () async {
      final manager = AsyncRequestManager<_Key>();
      var callCount = 0;

      await manager.execute<void>(
        function: () async => callCount++,
        key: _Key.alpha,
      );
      await manager.execute<void>(
        function: () async => callCount++,
        key: _Key.alpha,
      );

      expect(callCount, 2);
    });
  });

  // ── ExecutionStrategy.cancelPrevious ──────────────────────────────────────

  group('cancelPrevious strategy', () {
    test('cancels in-flight operation before starting the new one', () async {
      final manager = AsyncRequestManager<_Key>();
      final cancelled = <Object>[];
      manager.onCancel = (info) => cancelled.add(info.key);

      manager.execute<String>(
        function: () async {
          await Future.delayed(const Duration(seconds: 10));
          return 'first';
        },
        key: _Key.alpha,
        strategy: ExecutionStrategy.cancelPrevious,
      );

      final result = await manager.execute<String>(
        function: () async => 'second',
        key: _Key.alpha,
        strategy: ExecutionStrategy.cancelPrevious,
      );

      expect(result, 'second');
      expect(cancelled, contains(_Key.alpha));
    });
  });

  // ── ExecutionStrategy.parallel ────────────────────────────────────────────

  group('parallel strategy', () {
    test('runs multiple operations concurrently under the same key', () async {
      final manager = AsyncRequestManager<_Key>();
      var peak = 0;
      var active = 0;

      Future<String> trackingFn(String id) async {
        active++;
        if (active > peak) peak = active;
        await Future.delayed(const Duration(milliseconds: 50));
        active--;
        return id;
      }

      final results = await Future.wait([
        manager.execute<String>(
          function: () => trackingFn('a'),
          key: _Key.alpha,
          strategy: ExecutionStrategy.parallel,
        ),
        manager.execute<String>(
          function: () => trackingFn('b'),
          key: _Key.alpha,
          strategy: ExecutionStrategy.parallel,
        ),
      ]);

      expect(results, containsAll(['a', 'b']));
      expect(peak, 2);
    });
  });

  // ── cancel(key) ───────────────────────────────────────────────────────────

  group('cancel(key)', () {
    test('cancels only the operations for the given key', () async {
      final manager = AsyncRequestManager<_Key>();
      final cancelled = <Object>[];
      manager.onCancel = (info) => cancelled.add(info.key);

      manager.execute<void>(
        function: () async => Future.delayed(const Duration(seconds: 10)),
        key: _Key.alpha,
        strategy: ExecutionStrategy.parallel,
      );
      manager.execute<void>(
        function: () async => Future.delayed(const Duration(seconds: 10)),
        key: _Key.beta,
        strategy: ExecutionStrategy.parallel,
      );

      await manager.cancel(_Key.alpha);

      expect(cancelled, contains(_Key.alpha));
      expect(cancelled, isNot(contains(_Key.beta)));
      expect(manager.isRunning(_Key.alpha), isFalse);
      expect(manager.isRunning(_Key.beta), isTrue);

      await manager.cancelAll();
    });
  });

  // ── cancelAll() ───────────────────────────────────────────────────────────

  group('cancelAll()', () {
    test('cancels every pending operation across all keys', () async {
      final manager = AsyncRequestManager<_Key>();
      final cancelled = <Object>[];
      manager.onCancel = (info) => cancelled.add(info.key);

      manager.execute<void>(
        function: () async => Future.delayed(const Duration(seconds: 10)),
        key: _Key.alpha,
        strategy: ExecutionStrategy.parallel,
      );
      manager.execute<void>(
        function: () async => Future.delayed(const Duration(seconds: 10)),
        key: _Key.beta,
        strategy: ExecutionStrategy.parallel,
      );

      await manager.cancelAll();

      expect(cancelled, containsAll([_Key.alpha, _Key.beta]));
      expect(manager.totalRunning, 0);
      expect(manager.activeKeys, isEmpty);
    });
  });

  // ── dispose() ─────────────────────────────────────────────────────────────

  group('dispose()', () {
    test('cancels all operations and marks manager as disposed', () async {
      final manager = AsyncRequestManager<_Key>();

      manager.execute<void>(
        function: () async => Future.delayed(const Duration(seconds: 10)),
        key: _Key.alpha,
        strategy: ExecutionStrategy.parallel,
      );

      await manager.dispose();

      expect(manager.isDisposed, isTrue);
      expect(manager.totalRunning, 0);
    });

    test('execute throws StateError after dispose', () async {
      final manager = AsyncRequestManager<_Key>();
      await manager.dispose();

      expect(
        () => manager.execute<void>(function: () async {}, key: _Key.alpha),
        throwsStateError,
      );
    });
  });

  // ── Status methods ────────────────────────────────────────────────────────

  group('status methods', () {
    test('isRunning / runningCount / totalRunning / activeKeys', () async {
      final manager = AsyncRequestManager<_Key>();

      final future = manager.execute<void>(
        key: _Key.alpha,
        function: () async => Future.delayed(const Duration(milliseconds: 50)),
        strategy: ExecutionStrategy.parallel,
      );

      expect(manager.isRunning(_Key.alpha), isTrue);
      expect(manager.runningCount(_Key.alpha), 1);
      expect(manager.totalRunning, 1);
      expect(manager.activeKeys, {_Key.alpha});

      await future;

      expect(manager.isRunning(_Key.alpha), isFalse);
      expect(manager.totalRunning, 0);
      expect(manager.activeKeys, isEmpty);
    });

    test('runningCount tracks parallel operations', () async {
      final manager = AsyncRequestManager<_Key>();

      final f1 = manager.execute<void>(
        key: _Key.alpha,
        function: () async => Future.delayed(const Duration(milliseconds: 50)),
        strategy: ExecutionStrategy.parallel,
      );
      final f2 = manager.execute<void>(
        key: _Key.alpha,
        function: () async => Future.delayed(const Duration(milliseconds: 50)),
        strategy: ExecutionStrategy.parallel,
      );

      expect(manager.runningCount(_Key.alpha), 2);
      expect(manager.totalRunning, 2);

      await Future.wait([f1, f2]);

      expect(manager.runningCount(_Key.alpha), 0);
    });
  });

  // ── CancelInfo ────────────────────────────────────────────────────────────

  group('CancelInfo', () {
    test('onCancel receives key, startedAt and elapsed', () async {
      final manager = AsyncRequestManager<_Key>();
      CancelInfo? info;
      manager.onCancel = (i) => info = i;

      manager.execute<void>(
        key: _Key.alpha,
        function: () async => Future.delayed(const Duration(seconds: 10)),
        strategy: ExecutionStrategy.cancelPrevious,
      );

      await manager.execute<void>(
        key: _Key.alpha,
        function: () async {},
        strategy: ExecutionStrategy.cancelPrevious,
      );

      expect(info, isNotNull);
      expect(info!.key, _Key.alpha);
      expect(info!.startedAt, isA<DateTime>());
      expect(info!.elapsed, isA<Duration>());
    });
  });

  // ── Timeout ───────────────────────────────────────────────────────────────

  group('timeout', () {
    test('throws TimeoutException when deadline is exceeded', () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.execute<void>(
          key: _Key.alpha,
          function: () async => Future.delayed(const Duration(seconds: 10)),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });

    test('manager is still usable after a timeout', () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.execute<void>(
          key: _Key.alpha,
          function: () async => Future.delayed(const Duration(seconds: 10)),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );

      final result = await manager.execute<int>(
        key: _Key.alpha,
        function: () async => 42,
      );
      expect(result, 42);
    });
  });

  // ── Synchronous exception handling ────────────────────────────────────────

  group('synchronous exception handling', () {
    test('sync throw from function is wrapped as a Future error', () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.execute<void>(
          key: _Key.alpha,
          function: () => throw StateError('sync error'),
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('manager is still usable after a sync throw', () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.execute<void>(
          key: _Key.alpha,
          function: () => throw StateError('sync error'),
        ),
        throwsA(isA<StateError>()),
      );

      expect(manager.isRunning(_Key.alpha), isFalse);
      final result = await manager.execute<int>(
        key: _Key.alpha,
        function: () async => 99,
      );
      expect(result, 99);
    });
  });

  // ── Asynchronous exception handling ───────────────────────────────────────

  group('asynchronous exception handling', () {
    test('async rejection propagates to caller', () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.execute<void>(
          key: _Key.alpha,
          function: () async {
            await Future.delayed(const Duration(milliseconds: 10));
            throw FormatException('async error');
          },
        ),
        throwsA(isA<FormatException>()),
      );
    });

    test('cleanup runs and manager is still usable after an async rejection',
        () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.execute<void>(
          key: _Key.alpha,
          function: () async {
            await Future.delayed(const Duration(milliseconds: 10));
            throw FormatException('async error');
          },
        ),
        throwsA(isA<FormatException>()),
      );

      expect(manager.isRunning(_Key.alpha), isFalse);
      expect(manager.totalRunning, 0);

      final result = await manager.execute<int>(
        key: _Key.alpha,
        function: () async => 7,
      );
      expect(result, 7);
    });
  });

  // ── Convenience methods ───────────────────────────────────────────────────

  group('convenience methods', () {
    test('join() deduplicates like execute with join strategy', () async {
      final manager = AsyncRequestManager<_Key>();
      var callCount = 0;

      final f1 = manager.join(
        key: _Key.alpha,
        function: () async {
          callCount++;
          await Future.delayed(const Duration(milliseconds: 50));
          return 'result';
        },
      );
      final f2 = manager.join(
        key: _Key.alpha,
        function: () async {
          callCount++;
          return 'never';
        },
      );

      expect(await f1, 'result');
      expect(await f2, 'result');
      expect(callCount, 1);
    });

    test('cancelPrevious() cancels in-flight like execute with cancelPrevious strategy',
        () async {
      final manager = AsyncRequestManager<_Key>();
      final cancelled = <Object>[];
      manager.onCancel = (info) => cancelled.add(info.key);

      manager.cancelPrevious(
        key: _Key.alpha,
        function: () async {
          await Future.delayed(const Duration(seconds: 10));
          return 'first';
        },
      );

      final result = await manager.cancelPrevious(
        key: _Key.alpha,
        function: () async => 'second',
      );

      expect(result, 'second');
      expect(cancelled, contains(_Key.alpha));
    });

    test('parallel() runs concurrently like execute with parallel strategy',
        () async {
      final manager = AsyncRequestManager<_Key>();
      var peak = 0;
      var active = 0;

      Future<String> trackingFn(String id) async {
        active++;
        if (active > peak) peak = active;
        await Future.delayed(const Duration(milliseconds: 50));
        active--;
        return id;
      }

      final results = await Future.wait([
        manager.parallel(key: _Key.alpha, function: () => trackingFn('a')),
        manager.parallel(key: _Key.alpha, function: () => trackingFn('b')),
      ]);

      expect(results, containsAll(['a', 'b']));
      expect(peak, 2);
    });

    test('convenience methods forward timeout', () async {
      final manager = AsyncRequestManager<_Key>();

      await expectLater(
        manager.join(
          key: _Key.alpha,
          function: () async => Future.delayed(const Duration(seconds: 10)),
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  // ── Generic key type ──────────────────────────────────────────────────────

  group('generic key type', () {
    test('typed manager enforces key type at compile time', () async {
      // AsyncRequestManager<_Key> only accepts _Key values — a String key
      // would be a compile error. We verify the typed path runs correctly.
      final manager = AsyncRequestManager<_Key>();
      final result = await manager.execute<String>(
        key: _Key.alpha,
        function: () async => 'typed',
      );
      expect(result, 'typed');
    });

    test('Object-typed manager accepts mixed key types', () async {
      // AsyncRequestManager<Object> accepts any key, including mixed types.
      final manager = AsyncRequestManager<Object>();

      final r1 = await manager.execute<String>(
        key: _Key.alpha,
        function: () async => 'from enum',
      );
      final r2 = await manager.execute<String>(
        key: 'alpha', // same spelling, different runtime type — separate slot
        function: () async => 'from string',
      );

      expect(r1, 'from enum');
      expect(r2, 'from string');
    });
  });

  // ── Shared singleton ──────────────────────────────────────────────────────

  group('AsyncRequestManager.shared', () {
    test('is a non-null, non-disposed Object-keyed singleton', () {
      expect(AsyncRequestManager.shared, isNotNull);
      expect(AsyncRequestManager.shared.isDisposed, isFalse);
    });

    test('same instance is returned on repeated access', () {
      expect(
        identical(AsyncRequestManager.shared, AsyncRequestManager.shared),
        isTrue,
      );
    });
  });
}
