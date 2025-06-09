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
      return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }
}

// --- GET (Один запис) ---
Future<Response> _getById(PostgreSQLConnection connection, String id) async {
  try {
    const query = '''
      SELECT 
        sg.id, g.id AS group_id, g.title AS group_title, 
        u.id AS user_id, u.firstName, u.lastName, u.midName
      FROM StudentGroup sg
      JOIN Groups g ON sg.groupId = g.id
      JOIN Users u ON sg.userId = u.id
      WHERE sg.id = @id 
    ''';
    final result = await connection.query(query, substitutionValues: {'id': id});

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'StudentGroup entry not found'});
    }

    final rowMap = result.first.toColumnMap();
    return Response.json(body: {
      'id': rowMap['id'],
      'group': {'id': rowMap['group_id'], 'title': rowMap['group_title']},
      'student': {'id': rowMap['user_id'], 'firstName': rowMap['firstname'], 'lastName': rowMap['lastname'], 'midName': rowMap['midname']}
    });
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- PUT (Оновлення) ---
Future<Response> _update(RequestContext context, PostgreSQLConnection connection, String id) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;
    if (data.isEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Request body cannot be empty.'});
    }

    // 1. Перевірка існування запису
    final existingResult = await connection.query('SELECT userId, groupId FROM StudentGroup WHERE id = @id', substitutionValues: {'id': id});
    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'StudentGroup entry not found'});
    }
    
    final existing = existingResult.first.toColumnMap();
    final newUserId = data['userId'] ?? existing['userid'];
    final newGroupId = data['groupId'] ?? existing['groupid'];
    
    // 2. Валідація нових значень (якщо вони надані)
    if (data.containsKey('groupId')) {
        final groupExists = await connection.query('SELECT 1 FROM Groups WHERE id = @id', substitutionValues: {'id': newGroupId});
        if (groupExists.isEmpty) return Response.json(statusCode: 404, body: {'error': 'New group not found'});
    }
    
    if (data.containsKey('userId')) {
        final userResult = await connection.query('SELECT type FROM Users WHERE id = @id', substitutionValues: {'id': newUserId});
        if (userResult.isEmpty) {
          return Response.json(statusCode: 404, body: {'error': 'New user not found'});
        }
        if (userResult.first.toColumnMap()['type'] != 'STUDENT') {
          return Response.json(statusCode: 400, body: {'error': 'The new user is not a student.'});
        }

        // Перевірка, чи новий студент вже не в іншій групі (і це не цей самий запис)
        final conflict = await connection.query('SELECT 1 FROM StudentGroup WHERE userId = @userId AND id != @id', substitutionValues: {'userId': newUserId, 'id': id});
        if (conflict.isNotEmpty) {
          return Response.json(statusCode: 409, body: {'error': 'Conflict: This student is already assigned to another group.'});
        }
    }

    // 3. Виконання оновлення
    await connection.execute('UPDATE StudentGroup SET userId = @userId, groupId = @groupId WHERE id = @id',
        substitutionValues: {'id': id, 'userId': newUserId, 'groupId': newGroupId});

    return Response.json(body: {'message': 'StudentGroup entry updated successfully'});
  } on FormatException catch (e) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Bad Request: Invalid JSON format or empty request body. Details: ${e.message}'},
    );
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') return Response.json(statusCode: 409, body: {'error': 'Conflict: This assignment violates a unique constraint.'});
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'An unexpected error occurred: ${e.toString()}'});
  }
}

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    final affectedRows = await connection.execute('DELETE FROM StudentGroup WHERE id = @id', substitutionValues: {'id': id});
    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'StudentGroup entry not found'});
    }
    return Response.json(body: {'message': 'StudentGroup entry deleted successfully'});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}