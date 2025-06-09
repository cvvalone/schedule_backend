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
      'SELECT id, institutionName, logo, policyUrl FROM AppConfig ORDER BY institutionName',
    );

    // Мапування результату в список JSON-об'єктів
    final configs = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'institutionName': rowMap['institutionname'],
        'logo': rowMap['logo'],
        'policyUrl': rowMap['policyurl'],
      };
    }).toList();

    return Response.json(body: configs);
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
    final requiredFields = ['institutionName', 'logo', 'policyUrl'];
    final missingFields = requiredFields
        .where((field) => data[field] == null || data[field].toString().isEmpty)
        .toList();

    if (missingFields.isNotEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required fields: ${missingFields.join(', ')}'},
      );
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO AppConfig (id, institutionName, logo, policyUrl)
      VALUES (@id, @institutionName, @logo, @policyUrl)
      ''',
      substitutionValues: {
        'id': newId,
        'institutionName': data['institutionName'],
        'logo': data['logo'],
        'policyUrl': data['policyUrl'],
      },
    );

    // 3. Успішна відповідь
    return Response.json(
      statusCode: 201,
      body: {'message': 'AppConfig created successfully', 'id': newId},
    );
  } on PostgreSQLException catch (e) {
    // Обробка помилки дублікату
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409, // Conflict
        body: {'error': 'AppConfig with this institutionName already exists.'},
      );
    }
    return Response.json(
      statusCode: 500,
      body: {'error': 'Database error: ${e.message}'},
    );
  } catch (e) {
    // Обробка помилок парсингу JSON або інших
    return Response.json(
      statusCode: 400,
      body: {'error': 'Bad Request: ${e.toString()}'},
    );
  }
}