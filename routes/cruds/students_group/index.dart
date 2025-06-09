import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';

Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      final groupId = context.request.url.queryParameters['groupId'];
      return (groupId != null)
          ? _getStudentsByGroup(context, connection, groupId)
          : _getAllStudentGroupEntries(context, connection);
    case HttpMethod.post:
      return _create(context, connection);
    default:
      return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }
}

// --- GET (Всі записи StudentGroup) ---
Future<Response> _getAllStudentGroupEntries(RequestContext context, PostgreSQLConnection connection) async {
  try {
    final result = await connection.query('''
      SELECT 
        sg.id, u.id AS user_id, u.firstName, u.lastName, u.midName,
        g.id AS group_id, g.title AS group_title
      FROM StudentGroup sg
      JOIN Users u ON sg.userId = u.id
      JOIN Groups g ON sg.groupId = g.id
      ORDER BY g.title, u.lastName, u.firstName
    ''');

    final entries = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'student': {'id': rowMap['user_id'], 'firstName': rowMap['firstname'], 'lastName': rowMap['lastname'], 'midName': rowMap['midname']},
        'group': {'id': rowMap['group_id'], 'title': rowMap['group_title']}
      };
    }).toList();

    return Response.json(body: entries);
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- GET (Студенти конкретної групи) ---
Future<Response> _getStudentsByGroup(RequestContext context, PostgreSQLConnection connection, String groupId) async {
  try {
    final groupResult = await connection.query('SELECT title FROM Groups WHERE id = @id', substitutionValues: {'id': groupId});
    if (groupResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Group not found'});
    }
    final groupTitle = groupResult.first.toColumnMap()['title'] as String;

    final studentsResult = await connection.query('''
      SELECT u.id, u.firstName, u.lastName, u.midName, sg.id AS student_group_id 
      FROM Users u
      JOIN StudentGroup sg ON u.id = sg.userId
      WHERE sg.groupId = @groupId
      ORDER BY u.lastName, u.firstName
    ''', substitutionValues: {'groupId': groupId});

    final students = studentsResult.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'], 'studentGroupId': rowMap['student_group_id'],
        'firstName': rowMap['firstname'], 'lastName': rowMap['lastname'], 'midName': rowMap['midname']
      };
    }).toList();

    return Response.json(body: {'groupId': groupId, 'groupTitle': groupTitle, 'students': students});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- POST (Створення) ---
Future<Response> _create(RequestContext context, PostgreSQLConnection connection) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    // 1. Валідація
    final userId = data['userId'] as String?;
    final groupId = data['groupId'] as String?;
    if (userId == null || groupId == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required fields: userId, groupId'});
    }

    final userResult = await connection.query('SELECT type FROM Users WHERE id = @id', substitutionValues: {'id': userId});
    if (userResult.isEmpty || userResult.first.toColumnMap()['type'] != 'STUDENT') {
      return Response.json(statusCode: 404, body: {'error': 'User not found or is not a student'});
    }

    final groupResult = await connection.query('SELECT 1 FROM Groups WHERE id = @id', substitutionValues: {'id': groupId});
    if (groupResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Group not found'});
    }

    final existingAssignment = await connection.query('SELECT 1 FROM StudentGroup WHERE userId = @userId', substitutionValues: {'userId': userId});
    if (existingAssignment.isNotEmpty) {
      return Response.json(statusCode: 409, body: {'error': 'This student is already assigned to a group.'});
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query('INSERT INTO StudentGroup (id, userId, groupId) VALUES (@id, @userId, @groupId)',
        substitutionValues: {'id': newId, 'userId': userId, 'groupId': groupId});

    // 3. Успішна відповідь
    return Response.json(statusCode: 201, body: {'message': 'Student assigned to group successfully', 'id': newId});
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') {
      return Response.json(statusCode: 409, body: {'error': 'This assignment violates a unique constraint.'});
    }
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}