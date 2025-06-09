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
      'SELECT id, title, shortTitle, description FROM Subjects WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Subject not found'});
    }

    final rowMap = result.first.toColumnMap();
    return Response.json(body: {
      'id': rowMap['id'],
      'title': rowMap['title'],
      'shortTitle': rowMap['shorttitle'],
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
      'SELECT title, shortTitle, description FROM Subjects WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Subject not found'});
    }
    final existing = existingResult.first.toColumnMap();

    // 2. Виконання оновлення
    await connection.query(
      '''
      UPDATE Subjects
      SET title = @title, shortTitle = @shortTitle, description = @description
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'title': data['title'] ?? existing['title'],
        'shortTitle': data['shortTitle'] ?? existing['shorttitle'],
        'description': data['description'] ?? existing['description'],
      },
    );

    return Response.json(body: {'message': 'Subject updated successfully'});
  } on PostgreSQLException catch (e) {
    // Обробка помилки дублікату
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Subject with this title already exists.'},
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
      'DELETE FROM Subjects WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'Subject not found'});
    }

    return Response.json(body: {'message': 'Subject deleted successfully'});
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}