import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';

const _secret = '1111'; // 🔐 Заміни на надійний секрет у продакшн

// --- Створення access токена з UUID як String ---
String createAccessToken(String userId) {
  final jwt = JWT(
    {'id': userId},
    issuer: 'Schedule',
  );

  return jwt.sign(
    SecretKey(_secret),
    expiresIn: Duration(minutes: 15),
  );
}

// --- Створення refresh токена з UUID як String ---
String createRefreshToken(String userId) {
  final jwt = JWT(
    {'id': userId},
    issuer: 'Schedule',
  );

  return jwt.sign(
    SecretKey(_secret),
    expiresIn: Duration(days: 30),
  );
}

// --- Перевірка JWT токена ---
JWT? verifyJwt(String token) {
  try {
    return JWT.verify(token, SecretKey(_secret));
  } catch (_) {
    return null;
  }
}
