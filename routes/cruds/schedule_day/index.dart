import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';

/// Обробник запитів на /schedule_day
Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getScheduleDays(connection);
    case HttpMethod.post:
      return _createScheduleDay(context, connection);
    default:
      return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }
}

/// Отримати всі дні розкладу
Future<Response> _getScheduleDays(PostgreSQLConnection connection) async {
  try {
    final result = await connection.mappedResultsQuery('SELECT * FROM ScheduleDay');
    final days = result.map((row) => row['scheduleday']).toList();
    return Response.json(body: days);
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Failed to fetch schedule days', 'details': e.toString()});
  }
}

/// Створити новий день розкладу
Future<Response> _createScheduleDay(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;
    final dayNumber = data['dayNumber'];
    final weekNumber = data['weekNumber'];

    if (dayNumber == null || weekNumber == null) {
      return Response.json(statusCode: 400, body: {'error': 'dayNumber and weekNumber are required'});
    }

    if (dayNumber is! int || dayNumber < 1 || dayNumber > 7) {
      return Response.json(statusCode: 400, body: {'error': 'dayNumber must be an integer between 1 and 7'});
    }

    if (weekNumber is! int || weekNumber < 1 || weekNumber > 2) {
      return Response.json(statusCode: 400, body: {'error': 'weekNumber must be 1 or 2'});
    }

    final id = IdGenerator.generate();

    await connection.query(
      '''
      INSERT INTO ScheduleDay (id, dayNumber, weekNumber)
      VALUES (@id, @dayNumber, @weekNumber)
      ''',
      substitutionValues: {
        'id': id,
        'dayNumber': dayNumber,
        'weekNumber': weekNumber,
      },
    );

    return Response.json(statusCode: 201, body: {'message': 'ScheduleDay created', 'id': id});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Failed to create schedule day', 'details': e.toString()});
  }
}
