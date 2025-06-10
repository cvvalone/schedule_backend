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

// --- GET (Список з новою логікою фільтрації) ---
Future<Response> _getAll(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    // 1. Отримуємо параметри для пагінації та фільтрації
    final pageStr = context.request.url.queryParameters['page'] ?? '0';
    final page = int.tryParse(pageStr) ?? 0;
    final limit = 20;
    final offset = page * limit;
    final groupId = context.request.url.queryParameters['group_id'];

    // 2. Готуємо SQL-запит та параметри динамічно
    var whereClause = '';
    final substitutionValues = <String, dynamic>{
      'limit': limit,
      'offset': offset,
    };
    
    // Якщо group_id передано, додаємо умову WHERE
    if (groupId != null && groupId.isNotEmpty) {
      // Ця умова вибирає повідомлення для конкретної групи ТА загальні (де group_id IS NULL)
      whereClause = 'WHERE (n.group_id = @groupId OR n.group_id IS NULL)';
      substitutionValues['groupId'] = groupId;
    }

    // 3. Підраховуємо загальну кількість елементів з урахуванням фільтра для пагінації
    final totalCountQuery = 'SELECT COUNT(*) FROM Notifications n $whereClause';
    final totalCountResult = await connection.query(
      totalCountQuery,
      // Для підрахунку потрібен лише groupId, без limit/offset
      substitutionValues: { 
        if (groupId != null && groupId.isNotEmpty) 'groupId': groupId 
      },
    );
    final totalCount = totalCountResult.first[0] as int;
    final totalPage = totalCount > 0 ? (totalCount / limit).ceil() : 0;

    // 4. Виконуємо основний запит на отримання даних
    final query = '''
      SELECT 
          n.id, n.title, n.description, n.created_at,
          g.id AS group_id, g.title AS group_title,
          u.firstName AS author_firstname,
          u.lastName AS author_lastname
      FROM Notifications n
      LEFT JOIN Groups g ON n.group_id = g.id
      LEFT JOIN Users u ON n.user_id = u.id
      $whereClause
      ORDER BY n.created_at DESC
      LIMIT @limit OFFSET @offset
    ''';
    
    final result = await connection.query(
      query,
      substitutionValues: substitutionValues,
    );

    // 5. Форматуємо відповідь
    final notifications = result.map((row) {
      final rowMap = row.toColumnMap();
      return {
        'id': rowMap['id'],
        'title': rowMap['title'],
        'description': rowMap['description'],
        'createdAt': (rowMap['created_at'] as DateTime).toIso8601String(),
        'group': rowMap['group_id'] == null ? null : {'id': rowMap['group_id'], 'title': rowMap['group_title']},
        'author': rowMap['author_lastname'] == null
            ? null
            : {'firstName': rowMap['author_firstname'], 'lastName': rowMap['author_lastname']},
      };
    }).toList();

    return Response.json(
      body: {
        'page': page,
        'totalPage': totalPage,
        'items': notifications,
      },
    );
  } catch (e) {
    return Response.json(
      statusCode: 500,
      body: {'error': 'Internal Server Error: ${e.toString()}'},
    );
  }
}

// --- POST (Створення) ---
// Ця функція залишається без змін, вона вже коректно обробляє
// необов'язкове поле group_id.
Future<Response> _create(
  RequestContext context,
  PostgreSQLConnection connection,
) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    if (data['title'] == null || (data['title'] as String).isEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Missing required field: title'});
    }

    final groupId = data['group_id'];
    final userId = data['user_id'];

    if (groupId != null) {
      final groupExists = await connection.query('SELECT 1 FROM Groups WHERE id = @id', substitutionValues: {'id': groupId});
      if (groupExists.isEmpty) {
        return Response.json(statusCode: 404, body: {'error': 'Group with id $groupId not found'});
      }
    }
    if (userId != null) {
      final userExists = await connection.query('SELECT 1 FROM Users WHERE id = @id', substitutionValues: {'id': userId});
      if (userExists.isEmpty) {
        return Response.json(statusCode: 404, body: {'error': 'User with id $userId not found'});
      }
    }

    final newId = IdGenerator.generate();
    await connection.query(
      '''
      INSERT INTO Notifications (id, title, description, group_id, user_id)
      VALUES (@id, @title, @description, @group_id, @user_id)
      ''',
      substitutionValues: {
        'id': newId,
        'title': data['title'],
        'description': data['description'],
        'group_id': groupId,
        'user_id': userId,
      },
    );

    return Response.json(
      statusCode: 201,
      body: {'message': 'Notification created successfully', 'id': newId},
    );
  } on PostgreSQLException catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}