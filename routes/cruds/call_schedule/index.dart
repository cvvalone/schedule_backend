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
    // Форматуємо час в базі даних та сортуємо для послідовного виводу
    final result = await connection.query('''
      SELECT
        id,
        dayNumber,
        position,
        to_char(timeStart, 'HH24:MI') AS "timeStart",
        to_char(timeFinish, 'HH24:MI') AS "timeFinish"
      FROM CallSchedule
      ORDER BY dayNumber, position
    ''');

    final schedules = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'dayNumber': rowMap['daynumber'],
        'position': rowMap['position'],
        'timeStart': rowMap['timeStart'],
        'timeFinish': rowMap['timeFinish'],
      };
    }).toList();

    return Response.json(body: schedules);
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
    final requiredFields = ['dayNumber', 'position', 'timeStart', 'timeFinish'];
    final missingFields = requiredFields.where((field) => data[field] == null).toList();
    if (missingFields.isNotEmpty) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'Missing required fields: ${missingFields.join(', ')}'},
      );
    }
    
    final dayNumber = data['dayNumber'] as int;
    final position = data['position'] as int;
    if (dayNumber < 1 || dayNumber > 7) {
        return Response.json(statusCode: 400, body: {'error': 'dayNumber must be between 1 and 7.'});
    }
    if (position < 0) {
        return Response.json(statusCode: 400, body: {'error': 'position cannot be negative.'});
    }

    final timeStart = data['timeStart'] as String;
    final timeFinish = data['timeFinish'] as String;
    if (timeStart.compareTo(timeFinish) >= 0) {
      return Response.json(
        statusCode: 400,
        body: {'error': 'timeStart must be before timeFinish.'},
      );
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO CallSchedule (id, dayNumber, position, timeStart, timeFinish)
      VALUES (@id, @dayNumber, @position, @timeStart::time, @timeFinish::time)
      ''',
      substitutionValues: {
        'id': newId,
        'dayNumber': dayNumber,
        'position': position,
        'timeStart': timeStart,
        'timeFinish': timeFinish,
      },
    );

    // 3. Успішна відповідь
    return Response.json(
      statusCode: 201,
      body: {'message': 'Call schedule created successfully', 'id': newId},
    );
  } on PostgreSQLException catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Database error: ${e.message}'},
    );
  } on FormatException {
    return Response.json(
      statusCode: 400, 
      body: {'error': 'Invalid data format. Check if time is in HH:mm format or if numbers are correct.'});
  } catch (e) {
    return Response.json(
      statusCode: 400,
      body: {'error': 'Bad Request: ${e.toString()}'},
    );
  }
}