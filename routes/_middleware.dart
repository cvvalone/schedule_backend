import 'package:dart_frog/dart_frog.dart';
import '../lib/database/connection_pool.dart';
import 'package:postgres/postgres.dart';
import '../lib/database/env_loader.dart';

final pool = ConnectionPool(
  maxConnections: 50,
  host: DbConfig.host,
  port: DbConfig.port,
  database: DbConfig.database,
  username: DbConfig.user,
  password: DbConfig.password,
);

Handler middleware(Handler handler) {
  return (context) async {
    await pool.initialize();

    final connection = await pool.acquire();

    try {
      final scopedHandler = handler.use(
        provider<PostgreSQLConnection>((_) => connection),
      );
      return await scopedHandler.call(context);
    } finally {
      pool.release(connection);
    }
  };
}
