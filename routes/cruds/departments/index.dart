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
    final result = await connection.query(
      'SELECT id, name, description FROM Departments ORDER BY name',
    );

    final departments = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'name': rowMap['name'],
        'description': rowMap['description'],
      };
    }).toList();

    return Response.json(body: departments);
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
    final name = data['name'] as String?;
    if (name == null || name.isEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing or empty required field: name'},
      );
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO Departments (id, name, description)
      VALUES (@id, @name, @description)
      ''',
      substitutionValues: {
        'id': newId,
        'name': name,
        'description': data['description'],
      },
    );

    // 3. Успішна відповідь
    return Response.json(
      statusCode: 201,
      body: {'message': 'Department created successfully', 'id': newId},
    );
  } on PostgreSQLException catch (e) {
    // Обробка помилки дублікату
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409, // Conflict
        body: {'error': 'Department with this name already exists.'},
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