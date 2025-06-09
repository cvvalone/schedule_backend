import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

Future<Response> onRequest(RequestContext context, String id) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getById(connection, id);
    case HttpMethod.put:
      return _update(context, connection, id);
    case HttpMethod.delete:
      return _delete(connection, id);
    default:
      return Response.json(
        statusCode: 405,
        body: {'error': 'Method Not Allowed'},
      );
  }
}

// --- GET (Один запис) ---
Future<Response> _getById(PostgreSQLConnection connection, String id) async {
  try {
    final result = await connection.query(
      'SELECT id, institutionName, logo, policyUrl FROM AppConfig WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(
        statusCode: 404,
        body: {'error': 'AppConfig not found'},
      );
    }

    final rowMap = result.first.toColumnMap();
    return Response.json(body: {
      'id': rowMap['id'],
      'institutionName': rowMap['institutionname'],
      'logo': rowMap['logo'],
      'policyUrl': rowMap['policyurl'],
    });
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}

// --- PUT (Оновлення) ---
Future<Response> _update(
  RequestContext context,
  PostgreSQLConnection connection,
  String id,
) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    if (data.isEmpty) {
        return Response.json(statusCode: 400, body: {'error': 'Request body cannot be empty.'});
    }

    // 1. Перевірка існування запису
    final existingResult = await connection.query(
      'SELECT institutionName, logo, policyUrl FROM AppConfig WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'AppConfig not found'});
    }
    final existing = existingResult.first.toColumnMap();

    // 2. Виконання оновлення (з урахуванням часткового оновлення)
    await connection.query(
      '''
      UPDATE AppConfig
      SET institutionName = @institutionName, logo = @logo, policyUrl = @policyUrl
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'institutionName': data['institutionName'] ?? existing['institutionname'],
        'logo': data['logo'] ?? existing['logo'],
        'policyUrl': data['policyUrl'] ?? existing['policyurl'],
      },
    );

    return Response.json(body: {'message': 'AppConfig updated successfully'});
  } on PostgreSQLException catch (e) {
    // Обробка помилки дублікату
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409,
        body: {'error': 'AppConfig with this institutionName already exists.'},
      );
    }
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    // execute() повертає кількість змінених рядків
    final affectedRows = await connection.execute(
      'DELETE FROM AppConfig WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (affectedRows == 0) {
      return Response.json(
        statusCode: 404,
        body: {'error': 'AppConfig not found'},
      );
    }

    return Response.json(body: {'message': 'AppConfig deleted successfully'});
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}