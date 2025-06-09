import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';
import '../../lib/auth/jwt.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }

  final data = await context.request.json() as Map<String, dynamic>;
  final connection = context.read<PostgreSQLConnection>();

  final email = data['email'] as String?;
  final password = data['password'] as String?;
  final firstName = data['firstName'] as String?;
  final lastName = data['lastName'] as String?;
  final midName = data['midName'] as String?;
  final type = (data['type'] as String?)?.toUpperCase();

  if ([email, password, firstName, lastName, type].any((e) => e == null)) {
    return Response.json(statusCode: 400, body: {'error': 'Missing required fields'});
  }

  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
  if (!emailRegex.hasMatch(email!)) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid email format'});
  }

  if (password!.length < 8) {
    return Response.json(statusCode: 400, body: {'error': 'Password must be at least 8 characters long'});
  }

  if (!(type == 'TEACHER' || type == 'STUDENT' || type == 'ADMIN')) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid user type'});
  }

  try {
    final existingUser = await connection.query(
      'SELECT id FROM users WHERE email = @email',
      substitutionValues: {'email': email},
    );
    if (existingUser.isNotEmpty) {
      return Response.json(statusCode: 409, body: {'error': 'Email is already registered'});
    }

    final passwordHash = BCrypt.hashpw(password, BCrypt.gensalt());
    final userId = IdGenerator.generate();

    if (!IdGenerator.isValid(userId)) {
      return Response.json(statusCode: 500, body: {'error': 'Invalid UUID generated'});
    }

    await connection.query(
      '''
      INSERT INTO users (id, firstName, lastName, midName, email, passwordHash, authProvider, type)
      VALUES (@id, @firstName, @lastName, @midName, @email, @passwordHash, @authProvider, @type)
      ''',
      substitutionValues: {
        'id': userId,
        'firstName': firstName,
        'lastName': lastName,
        'midName': midName,
        'email': email,
        'passwordHash': passwordHash,
        'authProvider': 'password',
        'type': type,
      },
    );

    final accessToken = createAccessToken(userId);
    final refreshToken = createRefreshToken(userId);

    return Response.json(statusCode: 201, body: {
      'message': 'User registered',
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    });
  } catch (e) {
    return Response.json(statusCode: 500, body: {'error': 'Internal server error'});
  }
}
