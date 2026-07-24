import 'dart:async';

import 'package:async_request_manager/async_request_manager.dart';
import 'package:flutter/material.dart';

void main() => runApp(const App());

class App extends StatelessWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AsyncRequestManager Demo',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        useMaterial3: true,
      ),
      home: const DemoPage(),
    );
  }
}

// ── Demo page ────────────────────────────────────────────────────────────────

class DemoPage extends StatefulWidget {
  const DemoPage({super.key});

  @override
  State<DemoPage> createState() => _DemoPageState();
}

class _DemoPageState extends State<DemoPage> {
  final _manager = AsyncRequestManager<String>();
  final _log = <_LogEntry>[];

  @override
  void initState() {
    super.initState();
    _manager.onCancel = (info) {
      _log_(
        'Cancelled "${info.key}" after ${info.elapsed.inMilliseconds} ms',
        kind: _Status.cancel,
      );
    };
  }

  @override
  void dispose() {
    _manager.onCancel =
        null; // prevent callbacks reaching setState after unmount
    _manager.dispose();
    super.dispose();
  }

  // ── Logging ────────────────────────────────────────────────────────────────

  void _log_(String msg, {_Status kind = _Status.info}) {
    if (!mounted) return;
    setState(() {
      _log.insert(0, _LogEntry(msg, kind));
      if (_log.length > 100) _log.removeLast();
    });
  }

  void _divider(String label) => _log_(label, kind: _Status.divider);

  // ── Simulated async work ───────────────────────────────────────────────────

  Future<String> _fakeApi(String name, {int ms = 1500}) async {
    await Future.delayed(Duration(milliseconds: ms));
    return 'Response from "$name"';
  }

  // ── Demos ──────────────────────────────────────────────────────────────────

  Future<void> _demoJoin() async {
    _divider('── join() ──');
    _log_('Firing two join() calls for key "fetch-user"…');

    final f1 = _manager.join(
      key: 'fetch-user',
      function: () => _fakeApi('fetch-user API'),
    );
    final f2 = _manager.join(
      key: 'fetch-user',
      function: () => _fakeApi('fetch-user API — SECOND (never called)'),
    );
    _log_('Both waiting. running=${_manager.runningCount("fetch-user")}');

    final results = await Future.wait([f1, f2]);
    _log_('f1 → ${results[0]}', kind: _Status.success);
    _log_('f2 → ${results[1]} (identical — ran once)', kind: _Status.success);
  }

  Future<void> _demoCancelPrevious() async {
    _divider('── cancelPrevious() ──');
    _log_('First request started (5 s)…');

    // Don't await — we want it in-flight when the second arrives.
    _manager.cancelPrevious(
      key: 'search',
      function: () => _fakeApi('first-search', ms: 5000),
    );

    await Future.delayed(const Duration(milliseconds: 400));
    _log_('Second request cancels first…');

    final result = await _manager.cancelPrevious(
      key: 'search',
      function: () => _fakeApi('second-search', ms: 800),
    );
    _log_('Result → $result', kind: _Status.success);
  }

  Future<void> _demoParallel() async {
    _divider('── parallel() ──');
    _log_('Launching 3 parallel operations under key "pages"…');

    final futures = [
      _manager.parallel(
          key: 'pages', function: () => _fakeApi('page-1', ms: 900)),
      _manager.parallel(
          key: 'pages', function: () => _fakeApi('page-2', ms: 600)),
      _manager.parallel(
          key: 'pages', function: () => _fakeApi('page-3', ms: 1100)),
    ];
    _log_('Concurrent count: ${_manager.runningCount("pages")}');

    final results = await Future.wait(futures);
    for (final r in results) {
      _log_('↳ $r', kind: _Status.success);
    }
  }

  Future<void> _demoTimeout() async {
    _divider('── timeout ──');
    _log_('Starting request (3 s) with 600 ms timeout…');
    try {
      await _manager.join(
        key: 'slow-req',
        function: () => _fakeApi('slow-api', ms: 3000),
        timeout: const Duration(milliseconds: 600),
      );
    } on TimeoutException {
      _log_('TimeoutException caught — manager still usable.',
          kind: _Status.warn);
    }
  }

  Future<void> _demoCancelAll() async {
    _divider('── cancelAll() ──');
    // Start a few long-running tasks.
    for (var i = 1; i <= 3; i++) {
      final taskName = 'bg-task-$i'; // capture value before closure
      _manager.parallel(
        key: taskName,
        function: () => _fakeApi(taskName, ms: 10000),
      );
    }
    _log_('Started 3 background tasks (totalRunning=${_manager.totalRunning})');
    await Future.delayed(const Duration(milliseconds: 300));
    await _manager.cancelAll();
    _log_('cancelAll() done. totalRunning=${_manager.totalRunning}',
        kind: _Status.warn);
  }

  // ── Status ─────────────────────────────────────────────────────────────────

  Widget _statusBar() {
    final running = _manager.totalRunning;
    final keys = _manager.activeKeys;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      color: running > 0
          ? Colors.green.withValues(alpha: 0.1)
          : Colors.grey.withValues(alpha: 0.07),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            running > 0 ? Icons.sync : Icons.check_circle_outline,
            size: 18,
            color: running > 0 ? Colors.green : Colors.grey,
          ),
          const SizedBox(width: 8),
          Text(
            running > 0
                ? '$running running  •  keys: ${keys.join(", ")}'
                : 'Idle',
            style: TextStyle(
              fontSize: 13,
              color: running > 0 ? Colors.green.shade800 : Colors.grey,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('AsyncRequestManager Demo'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          IconButton(
            tooltip: 'Clear log',
            icon: const Icon(Icons.delete),
            onPressed: () => setState(() => _log.clear()),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _statusBar(),
          const Divider(height: 1),
          _ActionGrid(
            onJoin: _demoJoin,
            onCancelPrevious: _demoCancelPrevious,
            onParallel: _demoParallel,
            onTimeout: _demoTimeout,
            onCancelAll: _demoCancelAll,
          ),
          const Divider(height: 1),
          Expanded(child: _LogView(entries: _log)),
        ],
      ),
    );
  }
}

// ── Action grid ───────────────────────────────────────────────────────────────

class _ActionGrid extends StatelessWidget {
  const _ActionGrid({
    required this.onJoin,
    required this.onCancelPrevious,
    required this.onParallel,
    required this.onTimeout,
    required this.onCancelAll,
  });

  final VoidCallback onJoin;
  final VoidCallback onCancelPrevious;
  final VoidCallback onParallel;
  final VoidCallback onTimeout;
  final VoidCallback onCancelAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _DemoButton(
            label: 'Join',
            icon: Icons.merge_type,
            tooltip: 'Two callers share one in-flight Future',
            color: Colors.indigo,
            onPressed: onJoin,
          ),
          _DemoButton(
            label: 'Cancel Previous',
            icon: Icons.skip_next,
            tooltip: 'New call cancels any in-flight op for the same key',
            color: Colors.orange,
            onPressed: onCancelPrevious,
          ),
          _DemoButton(
            label: 'Parallel',
            icon: Icons.call_split,
            tooltip: 'Multiple ops run concurrently under one key',
            color: Colors.teal,
            onPressed: onParallel,
          ),
          _DemoButton(
            label: 'Timeout',
            icon: Icons.timer_off_outlined,
            tooltip: 'Request fails with TimeoutException after deadline',
            color: Colors.purple,
            onPressed: onTimeout,
          ),
          _DemoButton(
            label: 'Cancel All',
            icon: Icons.stop_circle_outlined,
            tooltip: 'Immediately cancel every in-flight operation',
            color: Colors.red,
            onPressed: onCancelAll,
          ),
        ],
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  const _DemoButton({
    required this.label,
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
  });

  final String label;
  final IconData icon;
  final String tooltip;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          foregroundColor: color,
          side: BorderSide(color: color.withValues(alpha: 0.4)),
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      ),
    );
  }
}

// ── Log view ──────────────────────────────────────────────────────────────────

enum _Status { info, success, warn, cancel, divider }

class _LogEntry {
  _LogEntry(this.message, this.kind);

  final String message;
  final _Status kind;
  final DateTime timestamp = DateTime.now();

  String get timeLabel {
    final t = timestamp;
    return '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}';
  }
}

class _LogView extends StatelessWidget {
  const _LogView({required this.entries});

  final List<_LogEntry> entries;

  Color _color(_Status status, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    if (status == _Status.success) {
      return Colors.green.shade700;
    } else if (status == _Status.warn) {
      return Colors.green.shade800;
    } else if (status == _Status.cancel) {
      return Colors.green.shade700;
    } else if (status == _Status.divider) {
      return cs.primary;
    } else {
      return cs.onSurface;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return const Center(
        child: Text(
          'Tap a button above to run a demo.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: entries.length,
      itemBuilder: (ctx, i) {
        final e = entries[i];
        final isDivider = e.kind == _Status.divider;
        return Padding(
          padding: EdgeInsets.only(
            top: isDivider ? 12 : 2,
            bottom: isDivider ? 4 : 2,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!isDivider)
                Text(
                  e.timeLabel,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                    fontFamily: 'monospace',
                  ),
                ),
              if (!isDivider) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  e.message,
                  style: TextStyle(
                    fontSize: isDivider ? 12 : 13,
                    fontFamily: 'monospace',
                    color: _color(e.kind, ctx),
                    fontWeight: isDivider ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
