## 1.0.0

- Converted project structure from Flutter plugin to a standard Dart package.
- Added `CancelInfo.cancelledAt` computed getter (`startedAt + elapsed`).
- Added `AsyncRequestManager.hasRunningOperations` convenience getter.
- Fixed `dispose()` to set `_disposed = true` before calling `cancelAll()`, closing a race window where `execute()` could slip in during async teardown. Added idempotency guard so a second `dispose()` call is a no-op.

## 0.3.0

### Breaking changes
- Renamed `ExecutionStrategy.singleExecution` → `ExecutionStrategy.join`.
- Renamed `ExecutionStrategy.cancelAll` (the enum value) → `ExecutionStrategy.cancelPrevious`.
- Renamed `ExecutionStrategy.allowParallel` → `ExecutionStrategy.parallel`.
- Renamed `CancelInfo.runningDuration` → `CancelInfo.elapsed`.
- Removed `contains(key)` (use `isRunning(key)` instead — identical behaviour).
- `AsyncRequestManager` is now generic: `AsyncRequestManager<K extends Object>`. Existing code using `AsyncRequestManager()` continues to work as `AsyncRequestManager<Object>()`.

### New features
- `AsyncRequestManager.shared` — a built-in `AsyncRequestManager<Object>` singleton for app-wide convenience.
- `execute()` doc comment now documents the runtime cast risk when joining a key with a mismatched result type `T`.
- `execute()` doc comment now documents that `timeout` only abandons the waiting — the underlying async work continues unless the caller cancels it explicitly.

## 0.2.0

### Breaking changes
- Renamed `FunctionCallManager` → `AsyncRequestManager`.
- Renamed `RequestType` → `ExecutionStrategy`.
- Renamed `RequestType.forceCall` → `ExecutionStrategy.allowParallel`.
- Renamed `cancelEverything()` → `cancelAll()`.
- `key` parameter is now `Object` — enums, `Type`, or any object can be used instead of raw strings.
- `onCancel` now receives `CancelInfo` (key + start time + running duration) instead of just the key string.
- Removed singleton — create instances with `AsyncRequestManager()`.

### New features
- `cancel(Object key)` — cancel in-flight operations for a single key.
- `dispose()` — cancel all operations and prevent future `execute` calls; subsequent calls throw `StateError`.
- `isRunning(Object key)`, `runningCount(Object key)` — query active operations per key.
- `totalRunning` — total count of in-flight operations across all keys.
- `activeKeys` — the set of keys that currently have in-flight operations.
- `timeout` parameter on `execute()` — fails with `TimeoutException` if the operation exceeds the given duration.
- Synchronous exceptions thrown by `function` are now wrapped as `Future` errors via `Future.sync`, ensuring consistent error handling.

## 0.1.0

- Initial release.
