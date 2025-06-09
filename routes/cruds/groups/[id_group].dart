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
    // Запит 1: Отримати дані про групу та її факультет
    final groupResult = await connection.query(
      '''
      SELECT 
        g.id, g.title, g.yearStart, g.yearFinish, 
        d.id as department_id, d.name as department_name 
      FROM Groups g
      JOIN Departments d ON g.departmentId = d.id
      WHERE g.id = @id
      ''',
      substitutionValues: {'id': id},
    );

    if (groupResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Group not found'});
    }

    // Запит 2: Отримати список студентів цієї групи
    final studentsResult = await connection.query(
      '''
      SELECT u.id, u.firstName, u.lastName, u.midName
      FROM Users u
      JOIN StudentGroup sg ON u.id = sg.userId
      WHERE sg.groupId = @groupId
      ORDER BY u.lastName, u.firstName
      ''',
      substitutionValues: {'groupId': id},
    );

    final students = studentsResult.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'firstName': rowMap['firstname'],
        'lastName': rowMap['lastname'],
        'midName': rowMap['midname'],
      };
    }).toList();

    final groupRow = groupResult.first.toColumnMap();
    
    // Комбінуємо результати
    final responseBody = {
      'id': groupRow['id'],
      'title': groupRow['title'],
      'yearStart': groupRow['yearstart'],
      'yearFinish': groupRow['yearfinish'],
      'department': {
        'id': groupRow['department_id'],
        'name': groupRow['department_name'],
      },
      'students': students,
    };

    return Response.json(body: responseBody);
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
      'SELECT title, departmentId, yearStart, yearFinish FROM Groups WHERE id = @id',
      substitutionValues: {'id': id},
    );
    if (existingResult.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'Group not found'});
    }
    final existing = existingResult.first.toColumnMap();
    
    // Перевірка існування нового факультету, якщо він змінюється
    if (data.containsKey('departmentId') && data['departmentId'] != null) {
      final deptResult = await connection.query(
        'SELECT 1 FROM Departments WHERE id = @id',
        substitutionValues: {'id': data['departmentId']},
      );
      if (deptResult.isEmpty) {
        return Response.json(statusCode: 404, body: {'error': 'New department not found'});
      }
    }
    
    // 2. Виконання оновлення
    await connection.query(
      '''
      UPDATE Groups
      SET title = @title, departmentId = @departmentId,
          yearStart = @yearStart, yearFinish = @yearFinish
      WHERE id = @id
      ''',
      substitutionValues: {
        'id': id,
        'title': data['title'] ?? existing['title'],
        'departmentId': data['departmentId'] ?? existing['departmentid'],
        'yearStart': data['yearStart'] ?? existing['yearstart'],
        'yearFinish': data['yearFinish'] ?? existing['yearfinish'],
      },
    );

    return Response.json(body: {'message': 'Group updated successfully'});
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') {
      return Response.json(
        statusCode: 409,
        body: {'error': 'Group with this title might already exist.'},
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

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    final affectedRows = await connection.execute(
      'DELETE FROM Groups WHERE id = @id',
      substitutionValues: {'id': id},
    );

    if (affectedRows == 0) {
      return Response.json(statusCode: 404, body: {'error': 'Group not found'});
    }

    return Response.json(body: {'message': 'Group deleted successfully'});
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}