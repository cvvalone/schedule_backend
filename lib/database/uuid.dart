import 'package:uuid/uuid.dart';

class IdGenerator {
  static final Uuid _uuid = Uuid();
  static const int uuidLength = 36; // UUID v4 має довжину 36 символів

  /// Генерує унікальний id типу UUID v4
  static String generate() {
    return _uuid.v4();
  }

  /// Перевіряє чи переданий рядок є валідним UUID по довжині
  static bool isValid(String id) {
    return id.length == uuidLength;
  }
}
