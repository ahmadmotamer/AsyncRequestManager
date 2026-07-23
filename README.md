# async_request_manager

A lightweight Dart utility for coordinating concurrent asynchronous operations.

Avoid duplicate API calls, cancel outdated requests, or run operations in parallel with a simple, type-safe API.

---

## Features

- 🚀 Three execution strategies:
    - **Join** – deduplicate concurrent requests.
    - **Cancel Previous** – discard outdated requests.
    - **Parallel** – allow multiple concurrent operations.
- 🔒 Generic key type for compile-time safety.
- ⏱ Optional timeout for every request.
- ❌ Per-key and global cancellation.
- 📊 Query running operations and active keys.
- 🧹 Disposable manager for proper lifecycle management.
- 🌍 Built-in shared singleton for app-wide usage.

---

## Why use this package?

Flutter applications frequently trigger the same asynchronous operation multiple times before the first one finishes.

Examples include:

- Multiple widgets requesting the same API simultaneously.
- Users tapping a button repeatedly.
- Search-as-you-type interactions.
- Duplicate form submissions.

Without coordination, this can lead to:

- Duplicate network requests
- Race conditions
- Wasted resources
- Stale data replacing newer results

`AsyncRequestManager` lets you decide exactly how concurrent requests should behave.

---

## Installation

```yaml
dependencies:
  async_request_manager: ^1.0.0
```

Import the package:

```dart
import 'package:async_request_manager/async_manager.dart';
```

---

# Quick Start

Define your request keys:

```dart
enum ApiKey {
  login,
  profile,
  contacts,
}
```

Create a manager:

```dart
final manager = AsyncRequestManager<ApiKey>();
```

Or use the shared instance:

```dart
final manager = AsyncRequestManager.shared;
```

---

# Execution Strategies

| Strategy | Existing request | New request |
|----------|------------------|-------------|
| **join** *(default)* | Keep running | Receives the same Future |
| **cancelPrevious** | Cancel | Starts a new request |
| **parallel** | Keep running | Starts another request |

---

# Examples

## Join (Deduplicate Requests)

If an operation with the same key is already running, additional callers receive the **same Future**.

The underlying function executes only once.

```dart
final first = manager.join(
  key: ApiKey.profile,
  function: fetchProfile,
);

final second = manager.join(
  key: ApiKey.profile,
  function: fetchProfile,
);

final profile = await Future.wait([first, second]);
```

Perfect for:

- Authentication
- Loading user profiles
- Configuration requests
- Cached API calls

> **Note**
>
> All callers joining the same key must use the same result type.
> Using different generic types for the same in-flight key will cause a runtime cast error.
>
> Use separate keys for operations returning different result types.

---

## Cancel Previous

Cancels any in-flight operation before starting a new one.

Ideal when only the latest result matters.

```dart
manager.cancelPrevious(
  key: 'search',
  function: () => searchApi('a'),
);

final results = await manager.cancelPrevious(
  key: 'search',
  function: () => searchApi('ab'),
);
```

Typical use cases:

- Search bars
- Auto-complete
- Live filtering
- Continuous user input

---

## Parallel

Always starts a new operation.

```dart
final pages = await Future.wait([
  manager.parallel(
    key: ApiKey.contacts,
    function: () => fetchPage(1),
  ),
  manager.parallel(
    key: ApiKey.contacts,
    function: () => fetchPage(2),
  ),
]);
```

Useful for:

- File downloads
- Pagination
- Independent API requests
- Background work

---

## Using execute()

The convenience methods are wrappers around `execute()`.

Use it when the execution strategy is chosen dynamically.

```dart
await manager.execute(
  key: ApiKey.login,
  strategy: ExecutionStrategy.join,
  timeout: const Duration(seconds: 5),
  function: loginUser,
);
```

---

# Timeouts

Every request can specify an optional timeout.

```dart
await manager.join(
  key: ApiKey.login,
  timeout: const Duration(seconds: 5),
  function: loginUser,
);
```

If the timeout expires, a `TimeoutException` is thrown.

> **Important**
>
> Timing out **does not cancel the underlying asynchronous work**.
>
> For example, an HTTP request continues running unless your implementation supports cancellation.

---

# Cancellation

Cancel all operations for a specific key:

```dart
await manager.cancel(ApiKey.contacts);
```

Cancel every running operation:

```dart
await manager.cancelAll();
```

Dispose the manager:

```dart
await manager.dispose();
```

After calling `dispose()`, any future `execute()` call throws a `StateError`.

---

# Observe Cancellations

```dart
manager.onCancel = (info) {
  print(
    'Cancelled ${info.key} '
    'after ${info.elapsed.inMilliseconds}ms',
  );
};
```

---

# Status

Check whether operations are currently running.

```dart
manager.isRunning(ApiKey.profile);

manager.runningCount(ApiKey.profile);

manager.totalRunning;

manager.activeKeys;
```

---

# FAQ

### Is this a debounce package?

No.

Debouncing delays execution.

`AsyncRequestManager` coordinates operations that are already running.

The two approaches solve different problems and can be used together.

---

### Does cancelling stop the underlying HTTP request?

No.

`CancelableOperation` only stops awaiting the result.

The underlying asynchronous work continues unless your implementation supports cancellation.

---

### Why use enum keys?

Enums provide compile-time safety and help avoid typos.

```dart
enum ApiKey {
  login,
  profile,
  contacts,
}
```

Using enums is recommended, although any object can be used as a key.

---

# License

MIT