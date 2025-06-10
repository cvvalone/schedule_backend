import 'dart:convert';
import 'package:dart_frog/dart_frog.dart';
import 'package:http/http.dart' as http;
import 'package:postgres/postgres.dart';
import 'package:schedule/database/uuid.dart';
import '../../lib/auth/jwt.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final data = await context.request.json() as Map<String, dynamic>;
  final accessToken = data['accessToken'] as String?;
  final type = (data['type'] as String?)?.toUpperCase();

  if (accessToken == null || type == null) {
    return Response(statusCode: 400, body: 'Missing accessToken or type');
  }

  if (!(type == 'TEACHER' || type == 'STUDENT' || type == 'ADMIN')) {
    return Response(statusCode: 400, body: 'Invalid user type');
  }

  try {
    final res = await http.get(
      Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
      headers: {
        'Authorization': 'Bearer $accessToken',
      },
    );

    if (res.statusCode != 200) {
      return Response(statusCode: 401, body: 'Invalid Google access token');
    }

    final userInfo = json.decode(res.body) as Map<String, dynamic>;

    final email = userInfo['email'] as String;
    final firstName = userInfo['given_name'] as String? ?? '';
    final lastName = userInfo['family_name'] as String? ?? '';
    final avatar = userInfo['picture'] as String? ?? '';

    final connection = context.read<PostgreSQLConnection>();

    final result = await connection.query(
      '''
      SELECT id FROM users
      WHERE email = @e AND authProvider = 'google'
      ''',
      substitutionValues: {'e': email},
    );

    String userId;

    if (result.isNotEmpty) {
      userId = result.first[0] as String;
    } else {
      userId = IdGenerator.generate();

      if (!IdGenerator.isValid(userId)) {
        return Response(statusCode: 500, body: 'Invalid UUID generated');
      }

      await connection.query(
        '''
        INSERT INTO users (id, firstName, lastName, midName, email, avatar, authProvider, type)
        VALUES (@id, @firstName, @lastName, '', @email, @avatar, 'google', @type)
        ''',
        substitutionValues: {
          'id': userId,
          'firstName': firstName,
          'lastName': lastName,
          'email': email,
          'avatar': avatar,
          'type': type,
        },
      );
    }

    final jwtAccessToken = createAccessToken(userId);
    final jwtRefreshToken = createRefreshToken(userId);

    return Response.json(body: {
      'message': 'Google login successful',
      'accessToken': jwtAccessToken,
      'refreshToken': jwtRefreshToken,
      'userId': userId, // ← ДОДАНО
    });
  } catch (e) {
    return Response(statusCode: 500, body: 'Error: $e');
  }
}
