import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:bcrypt/bcrypt.dart';

// --- Валідатори ---
final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
bool _isValidEmail(String? email) => email != null && _emailRegex.hasMatch(email);
bool _isValidType(String? type) => type != null && ['STUDENT', 'TEACHER', 'ADMIN'].contains(type.toUpperCase());
bool _isValidAuthProvider(String? provider) => provider != null && ['google', 'password'].contains(provider.toLowerCase());

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
    // Оновлений запит для отримання одного користувача з правильною групою
    const query = '''
      SELECT 
        u.id, u.firstname, u.lastname, u.midname, u.email, u.avatar, 
        u.phone, u.type, u.authprovider,
        COALESCE(g1.id, g2.id) as groupid,
        COALESCE(g1.title, g2.title) as grouptitle
      FROM 
        users u
      LEFT JOIN 
        studentgroup sg ON u.id = sg.userid AND u.type = 'STUDENT'
      LEFT JOIN 
        groups g1 ON sg.groupid = g1.id
      LEFT JOIN 
        groups g2 ON u.groupid = g2.id AND u.type != 'STUDENT'
      WHERE u.id = @id
    ''';
    
    final result = await connection.query(query, substitutionValues: {'id': id});
    if (result.isEmpty) {
      return Response.json(statusCode: 404, body: {'error': 'User not found'});
    }
    
    final rowMap = result.first.toColumnMap();
    
    final groupData = rowMap['groupid'] != null
        ? {'id': rowMap['groupid'], 'title': rowMap['grouptitle']}
        : null;
        
    return Response.json(body: {
      'id': rowMap['id'],
      'firstName': rowMap['firstname'],
      'lastName': rowMap['lastname'],
      'midName': rowMap['midname'],
      'email': rowMap['email'],
      'avatar': rowMap['avatar'],
      'phone': rowMap['phone'],
      'type': rowMap['type'],
      'authProvider': rowMap['authprovider'],
      'group': groupData, // Виводимо об'єкт групи з назвою
    });
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- PUT (Оновлення) ---
Future<Response> _update(RequestContext context, PostgreSQLConnection connection, String id) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;
    if (data.isEmpty) return Response.json(statusCode: 400, body: {'error': 'Request body cannot be empty.'});

    final existingUserResult = await connection.query('SELECT type FROM users WHERE id = @id', substitutionValues: {'id': id});
    if (existingUserResult.isEmpty) return Response.json(statusCode: 404, body: {'error': 'User not found'});
    
    final userType = existingUserResult.first.toColumnMap()['type'] as String;

    // Валідація полів
    if (data.containsKey('email') && !_isValidEmail(data['email'] as String?)) return Response.json(statusCode: 400, body: {'error': 'Invalid email format.'});
    if (data.containsKey('type') && !_isValidType(data['type'] as String?)) return Response.json(statusCode: 400, body: {'error': 'Invalid user type.'});
    if (data.containsKey('authProvider') && !_isValidAuthProvider(data['authProvider'] as String?)) return Response.json(statusCode: 400, body: {'error': 'Invalid authProvider.'});
    if (data.containsKey('password') && (data['password'] == null || (data['password'] as String).length < 6)) {
        return Response.json(statusCode: 400, body: {'error': 'Password must be at least 6 characters.'});
    }

    // Валідація groupId (тільки для не-студентів)
    if (userType != 'STUDENT' && data.containsKey('groupId') && data['groupId'] != null) {
      final groupResult = await connection.query('SELECT 1 FROM groups WHERE id = @id', substitutionValues: {'id': data['groupId']});
      if (groupResult.isEmpty) {
        return Response.json(statusCode: 400, body: {'error': 'Group with the specified ID does not exist.'});
      }
    }
    
    final updateFields = <String>[];
    final substitutionValues = <String, dynamic>{'id': id};
    
    // Динамічне формування запиту
    data.forEach((key, value) {
      final dbKey = key.replaceAllMapped(RegExp(r'(?<!^)(?=[A-Z])'), (match) => '_${match.group(0)}').toLowerCase();

      if (key == 'password') {
        updateFields.add('passwordhash = @passwordHash');
        substitutionValues['passwordHash'] = BCrypt.hashpw(value as String, BCrypt.gensalt());
      } else if (key == 'groupId' && userType == 'STUDENT') {
        // Ігноруємо спробу оновити groupId для студента через цей ендпоінт
      } else if (key != 'id') {
        updateFields.add('$dbKey = @$key');
        substitutionValues[key] = value;
      }
    });

    if (updateFields.isEmpty) return Response.json(statusCode: 400, body: {'error': 'No valid fields to update.'});

    final query = 'UPDATE users SET ${updateFields.join(', ')} WHERE id = @id';
    await connection.query(query, substitutionValues: substitutionValues);
    
    return Response.json(body: {'message': 'User updated successfully'});
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') return Response.json(statusCode: 409, body: {'error': 'User with this email or phone already exists.'});
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}

// --- DELETE (Видалення) ---
Future<Response> _delete(PostgreSQLConnection connection, String id) async {
  try {
    // ON DELETE CASCADE в таблицях StudentGroup, ScheduleItem і т.д.
    // автоматично видалить пов'язані з користувачем записи.
    final affectedRows = await connection.execute('DELETE FROM users WHERE id = @id', substitutionValues: {'id': id});
    if (affectedRows == 0) return Response.json(statusCode: 404, body: {'error': 'User not found'});
    return Response(body: 'User deleted successfully');
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}