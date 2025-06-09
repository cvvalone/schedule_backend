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
      'SELECT id, name, description FROM Departments WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Department not found'});
    }

    final rowMap = result.first.toColumnMap();
    return Response.json(body: {
      'id': rowMap['id'],
      'name': rowMap['name'],
      'description': rowMap['description'],
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
      'SELECT name, description FROM Departments WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Department not found'});
    }
    final existing = existingResult.first.toColumnMap();

    // 2. Виконання оновлення
    await connection.query(
      '''
      UPDATE Departments
      SET name = @name, description = @description
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'name': data['name'] ?? existing['name'],
        'description': data['description'] ?? existing['description'],
      },
    );

    return Response.json(body: {'message': 'Department updated successfully'});
  } on PostgreSQLException catch (e) {
    // Обробка помилки дублікату
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Department with this name already exists.'},
      );
    }
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Bad Request: ${e.toString()}'},
    );
  }
}

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    final affectedRows = await connection.execute(
      'DELETE FROM Departments WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'Department not found'});
    }

    return Response.json(body: {'message': 'Department deleted successfully'});
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}