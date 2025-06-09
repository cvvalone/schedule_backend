import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';

Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getAll(connection);
    case HttpMethod.post:
      return _create(context, connection);
    default:
      return Response.json(
        statusCode: 405,
        body: {'error': 'Method Not Allowed'},
      );
  }
}

// --- GET (Список) ---
Future<Response> _getAll(PostgreSQLConnection connection) async {
  try {
    // JOIN для отримання назви факультету
    final result = await connection.query('''
      SELECT 
        g.id, g.title, g.yearStart, g.yearFinish, 
        d.id as department_id, d.name as department_name 
      FROM Groups g
      JOIN Departments d ON g.departmentId = d.id
      ORDER BY g.title
    ''');

    final groups = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'title': rowMap['title'],
        'yearStart': rowMap['yearstart'],
        'yearFinish': rowMap['yearfinish'],
        'department': {
          'id': rowMap['department_id'],
          'name': rowMap['department_name'],
        }
      };
    }).toList();

    return Response.json(body: groups);
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}

// --- POST (Створення) ---
Future<Response> _create(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    // 1. Валідація
    final requiredFields = ['title', 'departmentId', 'yearStart', 'yearFinish'];
    final missingFields = requiredFields.where((field) => data[field] == null).toList();
    if (missingFields.isNotEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required fields: ${missingFields.join(', ')}'},
      );
    }
    
    // Перевірка існування факультету
    final deptResult = await connection.query(
      'SELECT 1 FROM Departments WHERE id = @id',
      substitutionValues: {'id': data['departmentId']},
    );
    if (deptResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Department not found'});
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO Groups (id, title, departmentId, yearStart, yearFinish)
      VALUES (@id, @title, @departmentId, @yearStart, @yearFinish)
      ''',
      substitutionValues: {
        'id': newId,
        'title': data['title'],
        'departmentId': data['departmentId'],
        'yearStart': data['yearStart'],
        'yearFinish': data['yearFinish'],
      },
    );

    // 3. Успішна відповідь
    return Response.json(
      statusCode: 201,
      body: {'message': 'Group created successfully', 'id': newId},
    );
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Group with this title might already exist.'},
      );
    }
    return Response.json(
      statusCode: 500,
      body: {'error': 'Database error: ${e.message}'},
    );
  } catch (e) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Bad Request: ${e.toString()}'},
    );
  }
}