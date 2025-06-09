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
      'SELECT id, title, shortTitle, description FROM Subjects ORDER BY title',
    );

    final subjects = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'title': rowMap['title'],
        'shortTitle': rowMap['shorttitle'],
        'description': rowMap['description'],
      };
    }).toList();

    return Response.json(body: subjects);
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
    final title = data['title'] as String?;
    final shortTitle = data['shortTitle'] as String?;
    if (title == null || title.isEmpty || shortTitle == null || shortTitle.isEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing or empty required fields: title, shortTitle'},
      );
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO Subjects (id, title, shortTitle, description)
      VALUES (@id, @title, @shortTitle, @description)
      ''',
      substitutionValues: {
        'id': newId,
        'title': title,
        'shortTitle': shortTitle,
        'description': data['description'],
      },
    );

    // 3. Успішна відповідь
    return Response.json(
      statusCode: 201,
      body: {'message': 'Subject created successfully', 'id': newId},
    );
  } on PostgreSQLException catch (e) {
    // Обробка помилки дублікату
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Subject with this title already exists.'},
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