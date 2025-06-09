import 'package:dotenv/dotenv.dart';

final dotenv = DotEnv()..load();

class DbConfig {
  static final host = dotenv['DB_HOST'] ?? 'localhost';
  static final port = int.tryParse(dotenv['DB_PORT'] ?? '5432') ?? 5432;
  static final database = dotenv['DB_NAME'] ?? 'Schedule';
  static final user = dotenv['DB_USER'] ?? 'postgres';
  static final password = dotenv['DB_PASS'] ?? '1111';
}
