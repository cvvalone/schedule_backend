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

/// Middleware для CORS
Middleware cors() {
  return (handler) {
    return (context) async {
      if (context.request.method == HttpMethod.options) {
        return Response(
          statusCode: 204,
          headers: {
            'Access-Control-Allow-Origin': '*', // або вкажи свій домен
            'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Authorization',
          },
        );
      }

      final response = await handler(context);
      return response.copyWith(headers: {
        ...response.headers,
        'Access-Control-Allow-Origin': '*', // або свій домен
        'Access-Control-Allow-Methods': 'GET, POST, PUT, DELETE, OPTIONS',
        'Access-Control-Allow-Headers': 'Content-Type, Authorization',
      });
    };
  };
}

Handler middleware(Handler handler) {
  final poolMiddleware = (Handler handler) {
    return (RequestContext context) async {
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
  };

  // Спочатку CORS, потім пул підключень
  return cors()(poolMiddleware(handler));
}