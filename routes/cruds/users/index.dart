import 'package:dart_frog/dart_frog.dart';
import 'package:postgres/postgres.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:schedule/database/uuid.dart';

// --- Валідатори ---
final _emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
bool _isValidEmail(String? email) => email != null && _emailRegex.hasMatch(email);
bool _isValidType(String? type) => type != null && ['STUDENT', 'TEACHER', 'ADMIN'].contains(type.toUpperCase());
bool _isValidAuthProvider(String? provider) => provider != null && ['google', 'password'].contains(provider.toLowerCase());

Future<Response> onRequest(RequestContext context) async {
  final connection = context.read<PostgreSQLConnection>();
  switch (context.request.method) {
    case HttpMethod.get:
      return _getAll(context, connection);
    case HttpMethod.post:
      return _create(context, connection);
    default:
      return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }
}

// --- GET (Список) ---
Future<Response> _getAll(RequestContext context, PostgreSQLConnection connection) async {
  try {
    final params = context.request.uri.queryParameters;
    final userType = params['type'];
    final unassigned = params['unassigned'] == 'true';

    final substitutionValues = <String, dynamic>{};
    final whereClauses = <String>[];

    // Оновлений запит:
    // - для студентів знаходить групу через `StudentGroup`
    // - для інших користувачів — через `Users.groupId`
    // - COALESCE вибирає перший не-NULL результат для groupid та grouptitle
    final query = StringBuffer('''
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
    ''');
    
    // Динамічно будуємо WHERE-умову
    if (userType != null && userType.isNotEmpty) {
      if (!_isValidType(userType)) {
        return Response.json(statusCode: 400, body: {'error': 'Invalid user type.'});
      }
      whereClauses.add('u.type = @type');
      substitutionValues['type'] = userType.toUpperCase();
    }
    
    // Додаємо умову для фільтрації неприв'язаних користувачів
    if (unassigned) {
      // Якщо шукаємо неприв'язаних студентів, перевіряємо StudentGroup
      if (userType?.toUpperCase() == 'STUDENT') {
        whereClauses.add('sg.userid IS NULL');
      } else {
      // Для інших типів (або якщо тип не вказано) перевіряємо обидві умови
        whereClauses.add('sg.userid IS NULL AND u.groupid IS NULL');
      }
    }
    
    if (whereClauses.isNotEmpty) {
      query.write(' WHERE ${whereClauses.join(' AND ')}');
    }

    query.write(' ORDER BY u.lastName, u.firstName');

    final result = await connection.query(query.toString(), substitutionValues: substitutionValues);

    final users = result.map((row) {
      final rowMap = row.toColumnMap();
      final groupData = rowMap['groupid'] != null
          ? {'id': rowMap['groupid'], 'title': rowMap['grouptitle']}
          : null;
      
      return {
        'id': rowMap['id'], 'firstName': rowMap['firstname'], 'lastName': rowMap['lastname'],
        'midName': rowMap['midname'], 'email': rowMap['email'], 'avatar': rowMap['avatar'],
        'phone': rowMap['phone'], 'type': rowMap['type'], 'authProvider': rowMap['authprovider'],
        'group': groupData, // Виводимо об'єкт групи з назвою
      };
    }).toList();

    return Response.json(body: users);
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal Server Error: ${e.toString()}'});
  }
}

// --- POST (Створення) ---
Future<Response> _create(RequestContext context, PostgreSQLConnection connection) async {
  try {
    final data = await context.request.json() as Map<String, dynamic>;

    // 1. Валідація
    final requiredFields = ['firstName', 'lastName', 'email', 'password', 'type'];
    final missingFields = requiredFields.where((field) => data[field] == null || data[field].toString().isEmpty).toList();
    if (missingFields.isNotEmpty) {
      return Response.json(statusCode: 400, body: {'error': 'Missing or empty required fields: ${missingFields.join(', ')}'});
    }
    if (!_isValidEmail(data['email'] as String)) return Response.json(statusCode: 400, body: {'error': 'Invalid email format.'});
    if ((data['password'] as String).length < 6) return Response.json(statusCode: 400, body: {'error': 'Password must be at least 6 characters.'});
    if (!_isValidType(data['type'] as String)) return Response.json(statusCode: 400, body: {'error': 'Invalid user type.'});
    
    final authProvider = data['authProvider']?.toString().toLowerCase() ?? 'password';
    if(!_isValidAuthProvider(authProvider)) return Response.json(statusCode: 400, body: {'error': 'Invalid authProvider.'});

    // Валідація groupId (для не-студентів)
    final userType = (data['type'] as String).toUpperCase();
    if (userType != 'STUDENT' && data.containsKey('groupId') && data['groupId'] != null) {
      final groupResult = await connection.query('SELECT 1 FROM groups WHERE id = @id', substitutionValues: {'id': data['groupId']});
      if (groupResult.isEmpty) {
        return Response.json(statusCode: 400, body: {'error': 'Group with the specified ID does not exist.'});
      }
    }
    
    // 2. Виконання запиту
    final hashedPassword = BCrypt.hashpw(data['password'] as String, BCrypt.gensalt());
    final newId = IdGenerator.generate();
    
    await connection.query(
      '''
      INSERT INTO Users (id, firstName, lastName, midName, email, avatar, phone, type, passwordHash, authProvider, groupId) 
      VALUES (@id, @firstName, @lastName, @midName, @email, @avatar, @phone, @type, @passwordHash, @authProvider, @groupId)
      ''',
      substitutionValues: {
        'id': newId,
        'firstName': data['firstName'], 'lastName': data['lastName'], 'midName': data['midName'],
        'email': data['email'], 'avatar': data['avatar'], 'phone': data['phone'],
        'type': userType,
        'passwordHash': hashedPassword,
        'authProvider': authProvider,
        // groupId зберігається тільки для не-студентів
        'groupId': userType != 'STUDENT' ? data['groupId'] : null,
      },
    );

    // Примітка: для прив'язки студента до групи (в StudentGroup)
    // потрібен буде окремий запит/ендпоінт.

    // 3. Успішна відповідь
    return Response.json(statusCode: 201, body: {'message': 'User created successfully', 'id': newId});
  } on PostgreSQLException catch (e) {
    if (e.code == '23505') return Response.json(statusCode: 409, body: {'error': 'User with this email or phone already exists.'});
    return Response.json(statusCode: 500, body: {'error': 'Database error: ${e.message}'});
  } catch (e) {
    return Response.json(statusCode: 400, body: {'error': 'Bad Request: ${e.toString()}'});
  }
}