import 'package:dart_frog/dart_frog.dart';
import 'package:bcrypt/bcrypt.dart';
import 'package:postgres/postgres.dart';
import '../../lib/auth/jwt.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response.json(statusCode: 405, body: {'error': 'Method Not Allowed'});
  }

  final data = await context.request.json() as Map<String, dynamic>;
  final connection = context.read<PostgreSQLConnection>();
  final email = data['email'] as String?;
  final password = data['password'] as String?;

  const invalidCredentialsMessage = 'Invalid email or password';

  if (email == null || password == null) {
    return Response.json(statusCode: 400, body: {'error': 'Email and password are required'});
  }

  final emailRegex = RegExp(r'^[^@]+@[^@]+\.[^@]+');
  if (!emailRegex.hasMatch(email)) {
    return Response.json(statusCode: 400, body: {'error': 'Invalid email format'});
  }

  try {
    // Повертаємо простий запит для отримання тільки id та хешу пароля
    final result = await connection.query(
      '''
      SELECT id, passwordHash FROM users WHERE email = @email AND authProvider = 'password'
      ''',
      substitutionValues: {'email': email},
    );

    if (result.isEmpty) {
      return Response.json(statusCode: 401, body: {'error': invalidCredentialsMessage});
    }

    final row = result.first;
    final userId = row[0] as String; // Отримуємо ID
    final storedHash = row[1] as String?; // Отримуємо хеш пароля

    if (storedHash == null) {
      return Response.json(statusCode: 401, body: {'error': 'This account uses a different sign-in method.'});
    }

    final isPasswordValid = BCrypt.checkpw(password, storedHash);

    if (!isPasswordValid) {
      return Response.json(statusCode: 401, body: {'error': invalidCredentialsMessage});
    }

    // Створення токенів
    final accessToken = createAccessToken(userId);
    final refreshToken = createRefreshToken(userId);

    // --- ЗМІНА: Додаємо тільки userId до відповіді ---
    return Response.json(body: {
      'message': 'Login successful',
      'accessToken': accessToken,
      'refreshToken': refreshToken,
      'userId': userId, // Додаємо ID користувача
    });

  } catch (e) {
    // ignore: avoid_print
    print('Login error: $e');
    return Response.json(statusCode: 500, body: {'error': 'Internal server error'});
  }
}