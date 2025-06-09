import 'dart:async';
import 'dart:collection';
import 'package:postgres/postgres.dart';

class ConnectionPool {
  final int maxConnections;
  final Duration acquireTimeout;

  final Queue<PostgreSQLConnection> _available = Queue();
  final List<PostgreSQLConnection> _all = [];

  final String host;
  final int port;
  final String database;
  final String username;
  final String password;

  bool _initialized = false;

  ConnectionPool({
    required this.maxConnections,
    this.acquireTimeout = const Duration(seconds: 5),
    required this.host,
    required this.port,
    required this.database,
    required this.username,
    required this.password,
  });

  Future<void> initialize() async {
    if (_initialized) return;

    // Закриваємо і очищуємо старі підключення (на всяк випадок)
    for (final conn in _all) {
      if (!conn.isClosed) {
        await conn.close();
      }
    }
    _all.clear();
    _available.clear();

    // Створюємо і відкриваємо нові підключення
    for (int i = 0; i < maxConnections; i++) {
      final conn = PostgreSQLConnection(
        host,
        port,
        database,
        username: username,
        password: password,
      );
      await conn.open();
      _all.add(conn);
      _available.add(conn);
    }

    _initialized = true;
  }

  Future<PostgreSQLConnection> acquire() async {
    final completer = Completer<PostgreSQLConnection>();

    // Таймаут очікування підключення
    Future<void>.delayed(acquireTimeout, () {
      if (!completer.isCompleted) {
        completer.completeError(
          TimeoutException('Timeout acquiring PostgreSQL connection.'),
        );
      }
    });

    () async {
      while (_available.isEmpty && !completer.isCompleted) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      if (!completer.isCompleted) {
        completer.complete(_available.removeFirst());
      }
    }();

    return completer.future;
  }

  void release(PostgreSQLConnection conn) {
    if (!_all.contains(conn)) {
      throw ArgumentError('Trying to release unknown connection.');
    }
    _available.add(conn);
  }

  Future<void> closeAll() async {
    for (final conn in _all) {
      if (!conn.isClosed) {
        await conn.close();
      }
    }
    _available.clear();
  }
}
