import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';

class DatabaseHelper {
  static final DatabaseHelper instance = DatabaseHelper._init();
  static Database? _database;

  DatabaseHelper._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('measurements.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE measurements (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        temperature REAL,
        humidity REAL,
        humidityExtra REAL,
        timestamp INTEGER,
        is_manual INTEGER DEFAULT 0
      )
    ''');
  }

  Future _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE measurements ADD COLUMN is_manual INTEGER DEFAULT 0');
    }
  }

  Future<int> insertMeasurement(Map<String, dynamic> row) async {
    final db = await instance.database;
    return await db.insert('measurements', row);
  }

  /// Inserts a measurement only if a row with the same timestamp doesn't exist.
  /// Used when restoring from Firestore to avoid duplicates.
  Future<void> insertMeasurementIfNotExists(Map<String, dynamic> row) async {
    final db = await instance.database;
    final ts = row['timestamp'] as int;
    final existing = await db.query(
      'measurements',
      where: 'timestamp = ?',
      whereArgs: [ts],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('measurements', row);
    }
  }

  /// Returns the total number of measurements stored locally.
  Future<int> countMeasurements() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as cnt FROM measurements');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<List<Map<String, dynamic>>> getAllMeasurements() async {
    final db = await instance.database;
    return await db.query('measurements', orderBy: 'timestamp ASC');
  }

  Future<List<Map<String, dynamic>>> getDetailedMeasurements({int limit = 100}) async {
    final db = await instance.database;
    return await db.query(
      'measurements',
      orderBy: 'timestamp DESC',
      limit: limit,
    );
  }

  Future<List<Map<String, dynamic>>> getDailyAverages() async {
    final db = await instance.database;
    // Agrupa por fecha (YYYY-MM-DD) y calcula estadisticas
    return await db.rawQuery('''
      SELECT 
        date(timestamp / 1000, 'unixepoch', 'localtime') as date,
        AVG(temperature) as avg_temp,
        MIN(temperature) as min_temp,
        MAX(temperature) as max_temp,
        AVG(humidity) as avg_hum,
        MIN(humidity) as min_hum,
        MAX(humidity) as max_hum
      FROM measurements
      GROUP BY date(timestamp / 1000, 'unixepoch', 'localtime')
      ORDER BY date ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getHourlyAverages() async {
    final db = await instance.database;
    // Agrupa por hora del dia (00:00 a 23:00)
    return await db.rawQuery('''
      SELECT 
        strftime('%H', timestamp / 1000, 'unixepoch', 'localtime') || ':00' as date,
        AVG(temperature) as avg_temp,
        MIN(temperature) as min_temp,
        MAX(temperature) as max_temp,
        AVG(humidity) as avg_hum,
        MIN(humidity) as min_hum,
        MAX(humidity) as max_hum
      FROM measurements
      GROUP BY strftime('%H', timestamp / 1000, 'unixepoch', 'localtime')
      ORDER BY date ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getWeeklyAverages() async {
    final db = await instance.database;
    // Agrupa por año y número de semana (YYYY-Www)
    return await db.rawQuery('''
      SELECT 
        strftime('%Y-W%W', timestamp / 1000, 'unixepoch', 'localtime') as date,
        MIN(date(timestamp / 1000, 'unixepoch', 'localtime')) as min_date,
        MAX(date(timestamp / 1000, 'unixepoch', 'localtime')) as max_date,
        AVG(temperature) as avg_temp,
        MIN(temperature) as min_temp,
        MAX(temperature) as max_temp,
        AVG(humidity) as avg_hum,
        MIN(humidity) as min_hum,
        MAX(humidity) as max_hum
      FROM measurements
      GROUP BY strftime('%Y-W%W', timestamp / 1000, 'unixepoch', 'localtime')
      ORDER BY date ASC
    ''');
  }

  Future<List<Map<String, dynamic>>> getMonthlyAverages() async {
    final db = await instance.database;
    // Agrupa por año y mes (YYYY-MM)
    return await db.rawQuery('''
      SELECT 
        strftime('%Y-%m', timestamp / 1000, 'unixepoch', 'localtime') as date,
        AVG(temperature) as avg_temp,
        MIN(temperature) as min_temp,
        MAX(temperature) as max_temp,
        AVG(humidity) as avg_hum,
        MIN(humidity) as min_hum,
        MAX(humidity) as max_hum
      FROM measurements
      GROUP BY strftime('%Y-%m', timestamp / 1000, 'unixepoch', 'localtime')
      ORDER BY date ASC
    ''');
  }

  Future<int> clearAll() async {
    final db = await instance.database;
    return await db.delete('measurements');
  }
}
