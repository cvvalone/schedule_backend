
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
      '''
      SELECT 
          n.id, n.title, n.description, n.created_at,
          g.id AS group_id, g.title AS group_title,
          u.id AS author_id, u.firstName AS author_firstname, u.lastName AS author_lastname
      FROM Notifications n
      LEFT JOIN Groups g ON n.group_id = g.id
      LEFT JOIN Users u ON n.user_id = u.id
      WHERE n.id = @id
      ''',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Notification not found'});
    }

    final rowMap = result.first.toColumnMap();
    return Response.json(body: {
      'id': rowMap['id'],
      'title': rowMap['title'],
      'description': rowMap['description'],
      'createdAt': (rowMap['created_at'] as DateTime).toIso8601String(),
      'group': rowMap['group_id'] == null ? null : {'id': rowMap['group_id'], 'title': rowMap['group_title']},
      'author': rowMap['author_id'] == null
          ? null
          : {'id': rowMap['author_id'], 'firstName': rowMap['author_firstname'], 'lastName': rowMap['author_lastname']},
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
      'SELECT title, description, group_id, user_id FROM Notifications WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Notification not found'});
    }
    final existing = existingResult.first.toColumnMap();
    
    if (data.containsKey('group_id') && data['group_id'] != null) {
      final groupExists = await connection.query('SELECT 1 FROM Groups WHERE id = @id', substitutionValues: {'id': data['group_id']});
      if (groupExists.isEmpty) {
        return Response.json(statusCode: 404, body: {'error': 'Group with id ${data['group_id']} not found'});
      }
    }
    if (data.containsKey('user_id') && data['user_id'] != null) {
      final userExists = await connection.query('SELECT 1 FROM Users WHERE id = @id', substitutionValues: {'id': data['user_id']});
      if (userExists.isEmpty) {
        return Response.json(statusCode: 404, body: {'error': 'User with id ${data['user_id']} not found'});
      }
    }

    // 2. Виконання оновлення
    await connection.query(
      '''
      UPDATE Notifications
      SET title = @title, description = @description,
          group_id = @group_id, user_id = @user_id
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'title': data['title'] ?? existing['title'],
        'description': data['description'] ?? existing['description'],
        'group_id': data['group_id'] ?? existing['group_id'],
        'user_id': data['user_id'] ?? existing['user_id'],
      },
    );

    return Response.json(body: {'message': 'Notification updated successfully'});
  } on PostgreSQLException catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    final affectedRows = await connection.execute(
      'DELETE FROM Notifications WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'Notification not found'});
    }

    return Response.json(body: {'message': 'Notification deleted successfully'});
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}