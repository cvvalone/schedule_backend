import 'package:dart_frog/dart_frog.dart';
import '../../lib/auth/jwt.dart';

Future<Response> onRequest(RequestContext context) async {
  if (context.request.method != HttpMethod.post) {
    return Response(statusCode: 405, body: 'Method Not Allowed');
  }

  final data = await context.request.json() as Map<String, dynamic>;
  final refreshToken = data['refreshToken'] as String?;

  if (refreshToken == null) {
    return Response(statusCode: 400, body: 'Refresh token is required');
  }

  final jwt = verifyJwt(refreshToken);

  if (jwt == null) {
    return Response(statusCode: 401, body: 'Invalid or expired refresh token');
  }

  final userId = jwt.payload['id'] as String?;
  if (userId == null || userId.isEmpty) {
    return Response(statusCode: 400, body: 'Invalid user ID in token');
  }

  final newAccessToken = createAccessToken(userId);

  return Response.json(body: {
    'accessToken': newAccessToken,
  });
}
