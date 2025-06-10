import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';

Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();

  switch (context.request.method) {
    case HttpMethod.get:
      return _getAllForWeek(context, connection); // Змінив назву для ясності
    case HttpMethod.post:
      return _create(context, connection);
    default:
      return Response.json(
        statusCode: 405,
        body: {'error': 'Method Not Allowed'},
      );
  }
}

// --- GET (Список на тиждень з датами) ---
Future<Response> _getAllForWeek(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    // 1. Парсинг та валідація параметрів запиту
    final params = context.request.uri.queryParameters;
    final startDateParam = params['startDate']; // Дата початку семестру (напр, 2023-09-01)
    final weekOfParam = params['weekOf'];       // Будь-яка дата в межах тижня (напр, 2024-03-13)
    final groupId = params['groupId'];          // ID групи

    // Валідація обов'язкових параметрів
    if (startDateParam == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required parameter: startDate'});
    }
    if (weekOfParam == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required parameter: weekOf'});
    }
    if (groupId == null) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required parameter: groupId'});
    }
    
    final startDate = DateTime.tryParse(startDateParam);
    final weekOfDate = DateTime.tryParse(weekOfParam);

    if (startDate == null) {
        return Response.json(statusCode: 400, body: {'error': 'Invalid startDate format. Use YYYY-MM-DD'});
    }
    if (weekOfDate == null) {
        return Response.json(statusCode: 400, body: {'error': 'Invalid weekOf format. Use YYYY-MM-DD'});
    }

    // 2. Логіка розрахунку тижня та дат
    
    // Знаходимо понеділок тижня, для якого робимо запит. weekday: 1=Пн, 7=Нд
    final startOfWeek = weekOfDate.subtract(Duration(days: weekOfDate.weekday - 1));

    // Знаходимо понеділок першого навчального тижня
    final firstMonday = startDate.subtract(Duration(days: startDate.weekday - 1));

    // Перевірка, чи запитувана дата не раніше дати початку
    if (startOfWeek.isBefore(firstMonday)) {
      // Повертаємо порожній розклад, якщо тиждень ще не почався
      return Response.json(body: {'weekNumber': 1, 'schedule': []});
    }

    // Рахуємо, скільки повних тижнів пройшло з початку семестру
    final fullWeeksPassed = startOfWeek.difference(firstMonday).inDays ~/ 7;

    // Визначаємо номер тижня (1 - непарний, 2 - парний).
    final weekNumber = (fullWeeksPassed % 2 == 0) ? 1 : 2; 

    // 3. SQL-запит для отримання ВСІХ пар на розрахований номер тижня
    final result = await connection.query(
      '''
      SELECT 
          si.id, si.room, s.title AS subject_title, s.shortTitle AS subject_short_title,
          g.title AS group_title, u.firstName AS teacher_first_name, u.lastName AS teacher_last_name,
          u.midName AS teacher_mid_name, cs.position AS lesson_position,
          to_char(cs.timeStart, 'HH24:MI') AS lesson_time_start,
          to_char(cs.timeFinish, 'HH24:MI') AS lesson_time_finish,
          sd.dayNumber as day_number -- ВАЖЛИВО: отримуємо номер дня тижня
      FROM ScheduleItem si
      JOIN ScheduleDay sd ON si.scheduleDayId = sd.id
      JOIN Subjects s ON si.subjectId = s.id
      JOIN Groups g ON si.groupId = g.id
      LEFT JOIN Users u ON si.userId = u.id
      JOIN CallSchedule cs ON si.callScheduleId = cs.id
      WHERE sd.weekNumber = @week
      AND si.groupId = @groupId
      ORDER BY sd.dayNumber, cs.position -- Сортуємо по дню тижня, а потім по номеру пари
      ''',
      substitutionValues: {
        'week': weekNumber,
        'groupId': groupId,
      },
    );

    // 4. Групування результатів по днях
    final Map<int, List<Map<String, dynamic>>> scheduleByDay = {};

    for (final row in result) {
      final rowMap = row.toColumnMap();
      final dayNumber = rowMap['day_number'] as int;

      scheduleByDay.putIfAbsent(dayNumber, () => []);

      scheduleByDay[dayNumber]!.add({
        'id': rowMap['id'], 'room': rowMap['room'],
        'subject': {'title': rowMap['subject_title'], 'shortTitle': rowMap['subject_short_title']},
        'group': {'title': rowMap['group_title']},
        'teacher': rowMap['teacher_last_name'] == null ? null : {'firstName': rowMap['teacher_first_name'], 'lastName': rowMap['teacher_last_name'], 'midName': rowMap['teacher_mid_name']},
        'lesson': {'position': rowMap['lesson_position'], 'timeStart': rowMap['lesson_time_start'], 'timeFinish': rowMap['lesson_time_finish']}
      });
    }

    // 5. Формування фінальної відповіді з розрахунком дати для кожного дня
    final List<Map<String, dynamic>> weeklySchedule = [];
    for (var dayNum = 1; dayNum <= 7; dayNum++) {
      // Додаємо день до розкладу, тільки якщо в цей день є пари
      if (scheduleByDay.containsKey(dayNum)) {
        // Розраховуємо КОНКРЕТНУ ДАТУ для цього дня тижня
        final lessonDate = startOfWeek.add(Duration(days: dayNum - 1));
        
        weeklySchedule.add({
          // Додаємо дату у форматі YYYY-MM-DD
          'date': '${lessonDate.year}-${lessonDate.month.toString().padLeft(2, '0')}-${lessonDate.day.toString().padLeft(2, '0')}',
          'dayNumber': dayNum,
          'lessons': scheduleByDay[dayNum],
        });
      }
    }

    return Response.json(body: {
      'weekNumber': weekNumber,
      'schedule': weeklySchedule,
    });
  } catch (e) {
    print(e); // Важливо для дебагу на сервері
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