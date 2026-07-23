import 'package:async/async.dart';

/// Information delivered to [AsyncRequestManager.onCancel] when an operation
/// is cancelled.
class CancelInfo {
  /// The key of the cancelled operation.
  final Object key;

  /// When the operation was started.
  final DateTime startedAt;

  /// How long the operation had been running before it was cancelled.
  final Duration elapsed;

  const CancelInfo({
    required this.key,
    required this.startedAt,
    required this.elapsed,
  });

  /// The approximate time at which this operation was cancelled.
  ///
  /// Equivalent to `startedAt.add(elapsed)`.
  DateTime get cancelledAt => startedAt.add(elapsed);

  @override
  String toString() =>
      'CancelInfo(key: $key, startedAt: $startedAt, elapsed: $elapsed)';
}

/// Determines how [AsyncRequestManager.execute] behaves when an operation
/// with the same key is already in flight.
enum ExecutionStrategy {
  /// Joins the in-flight operation and returns its result. The underlying
  /// function is never called a second time.
  ///
  /// This is the default. Both the original and the joining caller receive
  /// the same [Future] and therefore the same result (or error). Useful for
  /// deduplicating concurrent requests, e.g. multiple widgets triggering the
  /// same API call at once.
  join,

  /// Cancels all in-flight operations for the key, then starts a new one.
  ///
  /// Typical use-case: search-as-you-type, where each new keystroke should
  /// abandon the previous in-flight search.
  cancelPrevious,

  /// Starts a new operation regardless of what is already running for the
  /// same key. Multiple operations may run concurrently under one key.
  parallel,
}

/// Manages concurrent async operations keyed by values of type [K].
///
/// Use a typed instance for compile-time key safety:
/// ```dart
/// enum ApiKey { login, profile, contacts }
///
/// final manager = AsyncRequestManager<ApiKey>();
/// await manager.join(key: ApiKey.login, function: loginUser);
/// ```
///
/// Use [AsyncRequestManager.shared] when a single app-wide instance is enough.
class AsyncRequestManager<K extends Object> {
  /// A built-in shared singleton with key type [Object].
  ///
  /// Convenient when a single app-wide manager is sufficient. For stricter
  /// key typing, create a dedicated `AsyncRequestManager<YourKeyEnum>()`.
  static final AsyncRequestManager<Object> shared = AsyncRequestManager();

  AsyncRequestManager();

  /// Called whenever an operation is cancelled.
  void Function(CancelInfo info)? onCancel;

  bool _disposed = false;

  /// Whether [dispose] has been called on this manager.
  bool get isDisposed => _disposed;

  final Map<K, List<CancelableOperation<Object?>>> _requests = {};

  // ── Execution ─────────────────────────────────────────────────────────────

  /// Runs [function] under [key] using [strategy].
  ///
  /// **`join` (default):** If an operation for [key] is already in flight, the
  /// new caller joins it — both receive the same result and the function is
  /// not called a second time. Callers cannot distinguish whether the result
  /// came from their own invocation or a previous one.
  ///
  /// **Type constraint:** While an operation is in-flight, all callers joining
  /// the same key must use the same result type `T`. Mismatching types
  /// (e.g. first `execute<String>` then `execute<User>` with the same key
  /// before the first completes) produces a runtime cast error. Use separate
  /// keys for operations with different result types.
  ///
  /// **`cancelPrevious`:** Cancels any in-flight operations for [key] before
  /// starting a new one.
  ///
  /// **`parallel`:** Starts a new operation regardless of what is already
  /// running; multiple operations may run concurrently under the same key.
  ///
  /// **Timeout:** If [timeout] is provided, the operation fails with
  /// [TimeoutException] when the deadline is exceeded. Note that the
  /// *underlying* async work (e.g. an HTTP request) is **not** cancelled —
  /// only the waiting is abandoned. To also abort the work, use a cancellation
  /// token or similar mechanism inside [function].
  ///
  /// Throws [StateError] if [dispose] has already been called.
  Future<T> execute<T>({
    required Future<T> Function() function,
    ExecutionStrategy strategy = ExecutionStrategy.join,
    required K key,
    Duration? timeout,
  }) {
    if (_disposed) throw StateError('AsyncRequestManager has been disposed.');
    switch (strategy) {
      case ExecutionStrategy.join:
        return _handleJoin(function, key, timeout);
      case ExecutionStrategy.cancelPrevious:
        return _handleCancelPrevious(function, key, timeout);
      case ExecutionStrategy.parallel:
        return _startOperation(function, key, timeout);
    }
  }

  Future<T> _handleJoin<T>(
    Future<T> Function() function,
    K key,
    Duration? timeout,
  ) {
    if (_requests[key]?.isNotEmpty == true) {
      return _requests[key]!.first.value.then((v) => v as T);
    }
    return _startOperation(function, key, timeout);
  }

  // Non-async: cancel and register happen in the same synchronous slice,
  // preventing a race where a concurrent call sees _requests as empty.
  Future<T> _handleCancelPrevious<T>(
    Future<T> Function() function,
    K key,
    Duration? timeout,
  ) {
    final stale = _requests.remove(key);
    for (final op in stale ?? const <CancelableOperation<Object?>>[]) {
      op.cancel();
    }
    return _startOperation(function, key, timeout);
  }

  Future<T> _startOperation<T>(
    Future<T> Function() function,
    K key,
    Duration? timeout,
  ) {
    final startedAt = DateTime.now();

    // Future.sync converts synchronous throws into failed Futures so all
    // error paths are handled consistently by the caller.
    Future<T> future = Future.sync(function);
    if (timeout != null) future = future.timeout(timeout);

    final operation = CancelableOperation<T>.fromFuture(
      future,
      onCancel: () => onCancel?.call(
        CancelInfo(
          key: key,
          startedAt: startedAt,
          elapsed: DateTime.now().difference(startedAt),
        ),
      ),
    );

    _requests.putIfAbsent(key, () => []).add(operation);

    // then(onValue, onError) instead of whenComplete so that operation errors
    // don't leak into an unlistened Future chain and become unhandled.
    operation.value.then<void>(
      (_) => _cleanupEntry(key, operation),
      onError: (_) => _cleanupEntry(key, operation),
    );

    return operation.value;
  }

  void _cleanupEntry(K key, CancelableOperation<Object?> operation) {
    final ops = _requests[key];
    ops?.remove(operation);
    if (ops?.isEmpty ?? false) _requests.remove(key);
  }

  // ── Convenience methods ───────────────────────────────────────────────────

  /// Joins any in-flight operation for [key] and returns its result, or starts
  /// a new one if nothing is running. If multiple callers join the same
  /// operation, they all receive the exact same [Future] result — this is
  /// deduplication, not queuing.
  ///
  /// Shorthand for `execute(strategy: ExecutionStrategy.join, ...)`.
  /// See [execute] for the type-safety constraint that applies when joining.
  Future<T> join<T>({
    required K key,
    required Future<T> Function() function,
    Duration? timeout,
  }) =>
      execute(
        key: key,
        function: function,
        strategy: ExecutionStrategy.join,
        timeout: timeout,
      );

  /// Cancels any in-flight operations for [key] and starts a new one.
  ///
  /// Shorthand for `execute(strategy: ExecutionStrategy.cancelPrevious, ...)`.
  Future<T> cancelPrevious<T>({
    required K key,
    required Future<T> Function() function,
    Duration? timeout,
  }) =>
      execute(
        key: key,
        function: function,
        strategy: ExecutionStrategy.cancelPrevious,
        timeout: timeout,
      );

  /// Starts a new operation for [key] regardless of what is already running.
  ///
  /// Shorthand for `execute(strategy: ExecutionStrategy.parallel, ...)`.
  Future<T> parallel<T>({
    required K key,
    required Future<T> Function() function,
    Duration? timeout,
  }) =>
      execute(
        key: key,
        function: function,
        strategy: ExecutionStrategy.parallel,
        timeout: timeout,
      );

  // ── Status ────────────────────────────────────────────────────────────────

  /// Whether at least one operation is currently running for [key].
  bool isRunning(K key) => _requests[key]?.isNotEmpty == true;

  /// The number of concurrent operations currently running for [key].
  int runningCount(K key) => _requests[key]?.length ?? 0;

  /// The total number of operations currently running across all keys.
  int get totalRunning =>
      _requests.values.fold(0, (sum, list) => sum + list.length);

  /// Whether at least one operation is currently running across any key.
  bool get hasRunningOperations => _requests.isNotEmpty;

  /// The set of keys that currently have at least one in-flight operation.
  Set<K> get activeKeys => Set.unmodifiable(_requests.keys);

  // ── Cancellation & lifecycle ───────────────────────────────────────────────

  /// Cancels all in-flight operations for [key].
  Future<void> cancel(K key) {
    final ops = _requests.remove(key);
    if (ops == null) return Future.value();
    return Future.wait(ops.map((op) => op.cancel()));
  }

  /// Cancels every in-flight operation across all keys.
  Future<void> cancelAll() {
    final cancellations = [
      for (final ops in _requests.values)
        for (final op in ops) op.cancel(),
    ];
    _requests.clear();
    return Future.wait(cancellations);
  }

  /// Cancels all in-flight operations and prevents any future [execute] calls.
  ///
  /// After calling [dispose], [execute] throws [StateError].
  /// Calling [dispose] a second time is a no-op.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await cancelAll();
  }
}
