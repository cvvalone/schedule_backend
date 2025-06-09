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
        id,
        dayNumber,
        position,
        to_char(timeStart, 'HH24:MI') AS "timeStart",
        to_char(timeFinish, 'HH24:MI') AS "timeFinish"
      FROM CallSchedule 
      WHERE id = @id
      ''',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Call schedule not found'});
    }

    final schedule = result.first.toColumnMap();
    return Response.json(body: {
      'id': schedule['id'],
      'dayNumber': schedule['daynumber'],
      'position': schedule['position'],
      'timeStart': schedule['timeStart'],
      'timeFinish': schedule['timeFinish'],
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
      '''
      SELECT 
        dayNumber, 
        position, 
        to_char(timeStart, 'HH24:MI') as "timeStart",
        to_char(timeFinish, 'HH24:MI') as "timeFinish"
      FROM CallSchedule WHERE id = @id
      ''',
      substitutionValues: {'id': id},
    );

    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Call schedule not found'});
    }
    
    final existing = existingResult.first.toColumnMap();

    // 2. Валідація нових даних
    final dayNumber = data['dayNumber'] ?? existing['daynumber'];
    final position = data['position'] ?? existing['position'];
    if (dayNumber is int && (dayNumber < 1 || dayNumber > 7)) {
        return Response.json(statusCode: 400, body: {'error': 'dayNumber must be between 1 and 7.'});
    }
    if (position is int && position < 0) {
        return Response.json(statusCode: 400, body: {'error': 'position cannot be negative.'});
    }

    final timeStart = data['timeStart'] ?? existing['timeStart'];
    final timeFinish = data['timeFinish'] ?? existing['timeFinish'];
    if ((timeStart as String).compareTo(timeFinish as String) >= 0) {
      return Response.json(statusCode: 400, body: {'error': 'timeStart must be before timeFinish.'});
    }
    
    // 3. Виконання запиту
    await connection.query(
      '''
      UPDATE CallSchedule
      SET dayNumber = @dayNumber,
          position = @position,
          timeStart = @timeStart::time,
          timeFinish = @timeFinish::time
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'dayNumber': dayNumber,
        'position': position,
        'timeStart': timeStart,
        'timeFinish': timeFinish,
      },
    );

    return Response.json(body: {'message': 'Call schedule updated successfully'});
  } on PostgreSQLException catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } on FormatException {
    return Response.json(
      statusCode: 400, 
      body: {'error': 'Invalid data format. Check if numbers are correct.'});
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
      'DELETE FROM CallSchedule WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'Call schedule not found'});
    }

    return Response.json(body: {'message': 'Call schedule deleted successfully'});
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}