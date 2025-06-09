import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';

/// Обробник запитів на /schedule_day/:id
Future<Response> onRequest(RequestContext context, String id) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getScheduleDayById(connection, id);
    case HttpMethod.put:
      return _updateScheduleDay(context, connection, id);
    case HttpMethod.delete:
      return _deleteScheduleDay(connection, id);
    default:
      return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }
}

/// Отримати день розкладу за ID
Future<Response> _getScheduleDayById(PostgreSQLConnection connection, String id) async {
  try {
    final result = await connection.query(
      'SELECT * FROM ScheduleDay WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'ScheduleDay not found'});
    }

    final row = result.first;
    return Response.json(body: {
      'id': row[0],
      'dayNumber': row[1],
      'weekNumber': row[2],
    });
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Failed to get schedule day', 'details': e.toString()});
  }
}

/// Оновити день розкладу за ID
Future<Response> _updateScheduleDay(
  RequestContext context,
  PostgreSQLConnection connection,
  String id,
) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    final existing = await connection.query(
      'SELECT * FROM ScheduleDay WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (existing.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'ScheduleDay not found'});
    }

    final old = existing.first;
    final updatedDayNumber = data['dayNumber'] ?? old[1];
    final updatedWeekNumber = data['weekNumber'] ?? old[2];

    if (updatedDayNumber is! int || updatedDayNumber < 1 || updatedDayNumber > 7) {
      return Response.json(statusCode: 400, body: {'error': 'dayNumber must be an integer between 1 and 7'});
    }

    if (updatedWeekNumber is! int || updatedWeekNumber < 1 || updatedWeekNumber > 2) {
      return Response.json(statusCode: 400, body: {'error': 'weekNumber must be 1 or 2'});
    }

    await connection.query(
      '''
      UPDATE ScheduleDay
      SET dayNumber = @dayNumber,
          weekNumber = @weekNumber
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'dayNumber': updatedDayNumber,
        'weekNumber': updatedWeekNumber,
      },
    );

    return Response.json(body: {'message': 'ScheduleDay updated'});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Failed to update schedule day', 'details': e.toString()});
  }
}

/// Видалити день розкладу за ID
Future<Response> _deleteScheduleDay(PostgreSQLConnection connection, String id) async {
  try {
    final result = await connection.execute(
      'DELETE FROM ScheduleDay WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (result == 0) {
      return Response.json(statusCode: 404, body: {'error': 'ScheduleDay not found'});
    }

    return Response.json(body: {'message': 'ScheduleDay deleted'});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Failed to delete schedule day', 'details': e.toString()});
  }
}
