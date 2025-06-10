import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';

Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getSchedule(context, connection);
    case HttpMethod.post:
      return _create(context, connection);
    default:
      return Response.json(
        statusCode: 405,
        body: {'error': 'Method Not Allowed'},
      );
  }
}

// --- GET (Розклад на день АБО на тиждень) ---
Future<Response> _getSchedule(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    // 1. Парсинг та валідація спільних параметрів
    final params = context.request.uri.queryParameters;
    final startDateParam = params['startDate'];
    final groupId = params['groupId'];
    final dateParam = params['date'];
    final weekOfParam = params['weekOf'];

    // Валідація обов'язкових параметрів
    if (startDateParam == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required parameter: startDate'});
    }
    if (groupId == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required parameter: groupId'});
    }
    if (dateParam == null && weekOfParam == null) {
      return Response.json(statusCode: 400, body: {'error': "Missing required parameter: either 'date' or 'weekOf' must be provided."});
    }

    final startDate = DateTime.tryParse(startDateParam);
    if (startDate == null) {
        return Response.json(statusCode: 400, body: {'error': 'Invalid startDate format. Use YYYY-MM-DD'});
    }
    
    // 2. Визначення логіки: на день чи на тиждень?

    // --- ЛОГІКА ДЛЯ КОНКРЕТНОГО ДНЯ (якщо є параметр 'date') ---
    if (dateParam != null) {
      final targetDay = DateTime.tryParse(dateParam);
      if (targetDay == null) {
        return Response.json(statusCode: 400, body: {'error': "Invalid date format. Use YYYY-MM-DD"});
      }

      // Розрахунок тижня та дня
      final firstMonday = startDate.subtract(Duration(days: startDate.weekday - 1));
      final targetMonday = targetDay.subtract(Duration(days: targetDay.weekday - 1));
      final fullWeeksPassed = targetMonday.difference(firstMonday).inDays ~/ 7;
      final weekNumber = (fullWeeksPassed % 2 == 0) ? 1 : 2;
      final dayNumber = targetDay.weekday;

      // Запит до БД
      final result = await connection.query(
        '''
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
        WHERE sd.weekNumber = @week AND sd.dayNumber = @day AND si.groupId = @groupId
        ORDER BY cs.position
        ''',
        substitutionValues: { 'week': weekNumber, 'day': dayNumber, 'groupId': groupId },
      );
      
      // Мапування результату
      final lessons = result.map((row) {
        final rowMap = row.toColumnMap();
        return {
          'id': rowMap['id'], 'room': rowMap['room'],
          'subject': {'title': rowMap['subject_title'], 'shortTitle': rowMap['subject_short_title']},
          'group': {'title': rowMap['group_title']},
          'teacher': rowMap['teacher_last_name'] == null ? null : {'firstName': rowMap['teacher_first_name'], 'lastName': rowMap['teacher_last_name'], 'midName': rowMap['teacher_mid_name']},
          'lesson': {'position': rowMap['lesson_position'], 'timeStart': rowMap['lesson_time_start'], 'timeFinish': rowMap['lesson_time_finish']}
        };
      }).toList();

      // --- ЗМІНЕНО: Формування відповіді ---
      // Тепер відповідь має таку ж структуру, як і для тижня, але з одним днем.
      return Response.json(body: {
        'weekNumber': weekNumber,
        'schedule': [ // Створюємо масив з одним елементом
          {
            'date': dateParam, // Додаємо саму дату, яку запитували
            'dayNumber': dayNumber,
            'lessons': lessons, // Вкладаємо список пар
          },
        ],
      });
    }

    // --- ЛОГІКА ДЛЯ ЦІЛОГО ТИЖНЯ (якщо є параметр 'weekOf') ---
    else {
      final weekOfDate = DateTime.tryParse(weekOfParam!);
      if (weekOfDate == null) {
        return Response.json(statusCode: 400, body: {'error': "Invalid weekOf format. Use YYYY-MM-DD"});
      }

      // Розрахунок тижня та дат
      final startOfWeek = weekOfDate.subtract(Duration(days: weekOfDate.weekday - 1));
      final firstMonday = startDate.subtract(Duration(days: startDate.weekday - 1));

      if (startOfWeek.isBefore(firstMonday)) {
        return Response.json(body: {'weekNumber': 1, 'schedule': []});
      }
      
      final fullWeeksPassed = startOfWeek.difference(firstMonday).inDays ~/ 7;
      final weekNumber = (fullWeeksPassed % 2 == 0) ? 1 : 2;

      // Запит до БД
      final result = await connection.query(
        '''
        SELECT 
            si.id, si.room, s.title AS subject_title, s.shortTitle AS subject_short_title,
            g.title AS group_title, u.firstName AS teacher_first_name, u.lastName AS teacher_last_name,
            u.midName AS teacher_mid_name, cs.position AS lesson_position,
            to_char(cs.timeStart, 'HH24:MI') AS lesson_time_start,
            to_char(cs.timeFinish, 'HH24:MI') AS lesson_time_finish,
            sd.dayNumber as day_number
        FROM ScheduleItem si
        JOIN ScheduleDay sd ON si.scheduleDayId = sd.id
        JOIN Subjects s ON si.subjectId = s.id
        JOIN Groups g ON si.groupId = g.id
        LEFT JOIN Users u ON si.userId = u.id
        JOIN CallSchedule cs ON si.callScheduleId = cs.id
        WHERE sd.weekNumber = @week AND si.groupId = @groupId
        ORDER BY sd.dayNumber, cs.position
        ''',
        substitutionValues: { 'week': weekNumber, 'groupId': groupId },
      );

      // Групування по днях
      final scheduleByDay = <int, List<Map<String, dynamic>>>{};
      for (final row in result) {
        final rowMap = row.toColumnMap();
        final dayNumber = rowMap['day_number'] as int;
        scheduleByDay.putIfAbsent(dayNumber, () => []).add({
          'id': rowMap['id'], 'room': rowMap['room'],
          'subject': {'title': rowMap['subject_title'], 'shortTitle': rowMap['subject_short_title']},
          'group': {'title': rowMap['group_title']},
          'teacher': rowMap['teacher_last_name'] == null ? null : {'firstName': rowMap['teacher_first_name'], 'lastName': rowMap['teacher_last_name'], 'midName': rowMap['teacher_mid_name']},
          'lesson': {'position': rowMap['lesson_position'], 'timeStart': rowMap['lesson_time_start'], 'timeFinish': rowMap['lesson_time_finish']}
        });
      }

      // Формування фінальної відповіді з датами
      final weeklySchedule = <Map<String, dynamic>>[];
      for (var dayNum = 1; dayNum <= 7; dayNum++) {
        if (scheduleByDay.containsKey(dayNum)) {
          final lessonDate = startOfWeek.add(Duration(days: dayNum - 1));
          weeklySchedule.add({
            'date': '${lessonDate.year}-${lessonDate.month.toString().padLeft(2, '0')}-${lessonDate.day.toString().padLeft(2, '0')}',
            'dayNumber': dayNum,
            'lessons': scheduleByDay[dayNum],
          });
        }
      }
      return Response.json(body: {'weekNumber': weekNumber, 'schedule': weeklySchedule});
    }
  } catch (e) {
    print(e);
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- POST (Створення) ---
// Ця функція залишається без змін
Future<Response> _create(RequestContext context, PostgreSQLConnection connection) async {
  // ... тіло функції _create залишається таким самим
    try {
    final data = await context.request.json() as Map<String, dynamic>;

    // Валідація
    final requiredFields = ['userId', 'subjectId', 'callScheduleId', 'scheduleDayId', 'groupId', 'room'];
    final missingFields = requiredFields.where((field) => data[field] == null).toList();
    if (missingFields.isNotEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required fields: ${missingFields.join(', ')}'});
    }

    // Перевірка існування всіх пов'язаних сутностей
    final checks = {
      'Users': data['userId'], 'Subjects': data['subjectId'], 'CallSchedule': data['callScheduleId'],
      'ScheduleDay': data['scheduleDayId'], 'Groups': data['groupId'],
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

    // Виконання запиту
    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO ScheduleItem (id, userId, subjectId, callScheduleId, scheduleDayId, groupId, room)
      VALUES (@id, @userId, @subjectId, @callScheduleId, @scheduleDayId, @groupId, @room)
      ''',
      substitutionValues: {'id': newId, ...data},
    );

    // Успішна відповідь
    return Response.json(statusCode: 201, body: {'message': 'Schedule item created successfully', 'id': newId});
  } on PostgreSQLException catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}