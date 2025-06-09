// routes/schedule_item/[id].dart
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
      return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }
}

// --- GET (Один запис) ---
Future<Response> _getById(PostgreSQLConnection connection, String id) async {
  try {
    final result = await connection.query(
      '''
      SELECT 
          si.id, si.room, s.id AS subject_id, s.title AS subject_title, s.shortTitle AS subject_short_title,
          g.id AS group_id, g.title AS group_title, u.id as teacher_id, u.firstName AS teacher_first_name,
          u.lastName AS teacher_last_name, u.midName AS teacher_mid_name, cs.id as call_schedule_id,
          cs.position AS lesson_position, to_char(cs.timeStart, 'HH24:MI') AS lesson_time_start,
          to_char(cs.timeFinish, 'HH24:MI') AS lesson_time_finish, sd.id as schedule_day_id,
          sd.dayNumber as day_number, sd.weekNumber as week_number
      FROM ScheduleItem si
      JOIN Subjects s ON si.subjectId = s.id
      JOIN Groups g ON si.groupId = g.id
      LEFT JOIN Users u ON si.userId = u.id
      JOIN CallSchedule cs ON si.callScheduleId = cs.id
      JOIN ScheduleDay sd ON si.scheduleDayId = sd.id
      WHERE si.id = @id
      ''',
      substitutionValues: {'id': id},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Schedule item not found'});
    }

    final rowMap = result.first.toColumnMap();
    return Response.json(body: {
      'id': rowMap['id'], 'room': rowMap['room'],
      'subject': {'id': rowMap['subject_id'], 'title': rowMap['subject_title'], 'shortTitle': rowMap['subject_short_title']},
      'group': {'id': rowMap['group_id'], 'title': rowMap['group_title']},
      'teacher': rowMap['teacher_id'] == null ? null : {'id': rowMap['teacher_id'], 'firstName': rowMap['teacher_first_name'], 'lastName': rowMap['teacher_last_name'], 'midName': rowMap['teacher_mid_name']},
      'callSchedule': {'id': rowMap['call_schedule_id'], 'position': rowMap['lesson_position'], 'timeStart': rowMap['lesson_time_start'], 'timeFinish': rowMap['lesson_time_finish']},
      'scheduleDay': {'id': rowMap['schedule_day_id'], 'dayNumber': rowMap['day_number'], 'weekNumber': rowMap['week_number']},
    });
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- PUT (Оновлення) ---
Future<Response> _update(RequestContext context, PostgreSQLConnection connection, String id) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;
    if (data.isEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Request body cannot be empty.'});
    }

    final existingResult = await connection.query('SELECT * FROM ScheduleItem WHERE id = @id', substitutionValues: {'id': id});
    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Schedule item not found'});
    }
    final existing = existingResult.first.toColumnMap();

    // Перевірка існування нових ID, якщо їх змінюють
    final checks = {'Users': 'userId', 'Subjects': 'subjectId', 'CallSchedule': 'callScheduleId', 'ScheduleDay': 'scheduleDayId', 'Groups': 'groupId'};
    for (final entry in checks.entries) {
      if (data.containsKey(entry.value) && data[entry.value] != null) {
        final result = await connection.query('SELECT 1 FROM ${entry.key} WHERE id = @id', substitutionValues: {'id': data[entry.value]});
        if (result.isEmpty) {
          return Response.json(statusCode: 404, body: {'error': '${entry.key.substring(0, entry.key.length - 1)} not found'});
        }
      }
    }
    
    // Перевірка ролі вчителя, якщо він змінюється
    if (data.containsKey('userId') && data['userId'] != null) {
      final userResult = await connection.query('SELECT type FROM Users WHERE id = @id', substitutionValues: {'id': data['userId']});
      if (userResult.first.toColumnMap()['type'] != 'TEACHER') {
        return Response.json(statusCode: 400, body: {'error': 'User is not a TEACHER'});
      }
    }

    await connection.query(
      '''
      UPDATE ScheduleItem SET userId = @userId, subjectId = @subjectId, callScheduleId = @callScheduleId, 
      scheduleDayId = @scheduleDayId, groupId = @groupId, room = @room WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'userId': data['userId'] ?? existing['userid'], 'subjectId': data['subjectId'] ?? existing['subjectid'],
        'callScheduleId': data['callScheduleId'] ?? existing['callscheduleid'], 'scheduleDayId': data['scheduleDayId'] ?? existing['scheduledayid'],
        'groupId': data['groupId'] ?? existing['groupid'], 'room': data['room'] ?? existing['room'],
      },
    );

    return Response.json(body: {'message': 'Schedule item updated successfully'});
  } on PostgreSQLException catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    final affectedRows = await connection.execute('DELETE FROM ScheduleItem WHERE id = @id', substitutionValues: {'id': id});
    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'Schedule item not found'});
    }
    return Response.json(body: {'message': 'Schedule item deleted successfully'});
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}