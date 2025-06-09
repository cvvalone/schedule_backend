import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';

Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getAll(context, connection);
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
Future<Response> _getAll(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    // 1. Парсинг та валідація параметрів запиту
    final params = context.request.uri.queryParameters;
    final startDateParam = params['startDate'];
    if (startDateParam == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required parameter: startDate'});
    }
    
    final startDate = DateTime.tryParse(startDateParam);
    if (startDate == null) {
        return Response.json(statusCode: 400, body: {'error': 'Invalid startDate format. Use YYYY-MM-DD'});
    }

    final targetDateParam = params['date'];
    final targetDay = (targetDateParam != null && DateTime.tryParse(targetDateParam) != null)
        ? DateTime.parse(targetDateParam)
        : DateTime.now();

    // 2. Логіка розрахунку тижня та дня
    final firstMonday = startDate.subtract(Duration(days: startDate.weekday - 1));
    final targetMonday = targetDay.subtract(Duration(days: targetDay.weekday - 1));
    if (targetMonday.isBefore(firstMonday)) {
      return Response.json(statusCode: 400, body: {'error': 'Target date cannot be before the start date'});
    }

    final fullWeeksPassed = targetMonday.difference(firstMonday).inDays ~/ 7;
    final weekNumber = (fullWeeksPassed % 2 == 0) ? 1 : 2;
    final dayNumber = targetDay.weekday;

    // 3. Динамічне формування SQL-запиту
    final query = StringBuffer('''
      SELECT 
          si.id, si.room, s.title AS subject_title, s.shortTitle AS subject_short_title,
          g.title AS group_title, u.firstName AS teacher_first_name, u.lastName AS teacher_last_name,
          u.midName AS teacher_mid_name, cs.position AS lesson_position,
          to_char(cs.timeStart, 'HH24:MI') AS lesson_time_start,
          to_char(cs.timeFinish, 'HH24:MI') AS lesson_time_finish
      FROM ScheduleItem si
      JOIN ScheduleDay sd ON si.scheduleDayId = sd.id
      JOIN Subjects s ON si.subjectId = s.id
      JOIN Groups g ON si.groupId = g.id
      LEFT JOIN Users u ON si.userId = u.id
      JOIN CallSchedule cs ON si.callScheduleId = cs.id
      WHERE sd.weekNumber = @week
    ''');

    final substitutionValues = <String, dynamic>{'week': weekNumber};

    if (params['groupId'] != null) {
      query.write(' AND si.groupId = @groupId');
      substitutionValues['groupId'] = params['groupId'];
    }

    if (targetDateParam != null) {
      query.write(' AND sd.dayNumber = @dayNumber');
      substitutionValues['dayNumber'] = dayNumber;
    }

    query.write(' ORDER BY cs.position');
    final result = await connection.query(query.toString(), substitutionValues: substitutionValues);

    // 4. Мапування результату
    final items = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'], 'room': rowMap['room'],
        'subject': {'title': rowMap['subject_title'], 'shortTitle': rowMap['subject_short_title']},
        'group': {'title': rowMap['group_title']},
        'teacher': rowMap['teacher_last_name'] == null ? null : {'firstName': rowMap['teacher_first_name'], 'lastName': rowMap['teacher_last_name'], 'midName': rowMap['teacher_mid_name']},
        'lesson': {'position': rowMap['lesson_position'], 'timeStart': rowMap['lesson_time_start'], 'timeFinish': rowMap['lesson_time_finish']}
      };
    }).toList();

    return Response.json(body: {'weekNumber': weekNumber, 'dayNumber': dayNumber, 'schedule': items});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- POST (Створення) ---
Future<Response> _create(RequestContext context, PostgreSQLConnection connection) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    // 1. Валідація
    final requiredFields = ['userId', 'subjectId', 'callScheduleId', 'scheduleDayId', 'groupId', 'room'];
    final missingFields = requiredFields.where((field) => data[field] == null).toList();
    if (missingFields.isNotEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required fields: ${missingFields.join(', ')}'});
    }

    // Перевірка існування всіх пов'язаних сутностей
    final checks = {
      'Users': data['userId'],
      'Subjects': data['subjectId'],
      'CallSchedule': data['callScheduleId'],
      'ScheduleDay': data['scheduleDayId'],
      'Groups': data['groupId'],
    };

    for (final entry in checks.entries) {
      final result = await connection.query('SELECT 1 FROM ${entry.key} WHERE id = @id', substitutionValues: {'id': entry.value});
      if (result.isEmpty) {
        return Response.json(statusCode: 404, body: {'error': '${entry.key.substring(0, entry.key.length - 1)} not found'});
      }
    }
    
    // Перевірка ролі вчителя
    final userResult = await connection.query('SELECT type FROM Users WHERE id = @id', substitutionValues: {'id': data['userId']});
    if (userResult.first.toColumnMap()['type'] != 'TEACHER') {
      return Response.json(statusCode: 400, body: {'error': 'User is not a TEACHER'});
    }

    // 2. Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO ScheduleItem (id, userId, subjectId, callScheduleId, scheduleDayId, groupId, room)
      VALUES (@id, @userId, @subjectId, @callScheduleId, @scheduleDayId, @groupId, @room)
      ''',
      substitutionValues: {'id': newId, ...data},
    );

    // 3. Успішна відповідь
    return Response.json(statusCode: 201, body: {'message': 'Schedule item created successfully', 'id': newId});
  } on PostgreSQLException catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}