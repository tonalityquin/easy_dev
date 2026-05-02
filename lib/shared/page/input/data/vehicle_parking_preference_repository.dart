import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'vehicle_parking_preference.dart';

class VehicleParkingPreferenceRepository {
  VehicleParkingPreferenceRepository._();

  static final VehicleParkingPreferenceRepository instance =
      VehicleParkingPreferenceRepository._();

  static const String _dbName = 'vehicle_parking_preferences.db';
  static const int _dbVersion = 4;
  static const int _seedVersion = 4;
  static const String tableName = 'vehicle_parking_preferences';
  static const String _metaTableName = 'vehicle_parking_meta';

  static const List<_VehicleParkingPreferenceSeed> _seedRows =
      <_VehicleParkingPreferenceSeed>[
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Genesis',
      modelName: 'G80',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Hyundai',
      modelName: 'Grandeur HG',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Kia',
      modelName: 'Carnival',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Hyundai',
      modelName: 'Grand Starex',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Hyundai',
      modelName: 'Staria',
      priority1SlotKey: ParkingSlotPreferenceKey.extended,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Chevrolet',
      modelName: 'Matiz',
      priority1SlotKey: ParkingSlotPreferenceKey.compact,
      priority2SlotKey: ParkingSlotPreferenceKey.standard,
      priority3SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'MINI',
      modelName: 'Cooper',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
    ),
    _VehicleParkingPreferenceSeed(
      manufacturerName: 'Hyundai',
      modelName: 'Sonata',
      priority1SlotKey: ParkingSlotPreferenceKey.standard,
      priority2SlotKey: ParkingSlotPreferenceKey.extended,
    ),
  ];

  static const List<({String manufacturerName, String modelName})>
      _obsoleteSeedKeys = <({String manufacturerName, String modelName})>[
    (manufacturerName: '제네시스', modelName: 'G80'),
    (manufacturerName: '현대', modelName: '그랜저 HG330'),
    (manufacturerName: 'Hyundai', modelName: 'Grandeur HG330'),
  ];

  Database? _db;

  Future<Database> get database async {
    final cached = _db;
    if (cached != null) return cached;

    final dbPath = await getDatabasesPath();
    final fullPath = p.join(dbPath, _dbName);

    final opened = await openDatabase(
      fullPath,
      version: _dbVersion,
      onCreate: (db, version) async {
        await _ensureSchema(db);
        await _applySeedDataIfNeeded(db, force: true);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _ensureSchema(db);
        await _applySeedDataIfNeeded(db, force: true);
      },
      onOpen: (db) async {
        await _ensureSchema(db);
        await _applySeedDataIfNeeded(db);
      },
    );

    _db = opened;
    return opened;
  }

  static Future<void> _ensureSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS $tableName (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  manufacturer_name TEXT NOT NULL,
  model_name TEXT NOT NULL,
  priority_1_slot_key TEXT,
  priority_2_slot_key TEXT,
  priority_3_slot_key TEXT,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL,
  UNIQUE(manufacturer_name, model_name)
)
''');

    await db.execute('''
CREATE TABLE IF NOT EXISTS $_metaTableName (
  key TEXT PRIMARY KEY,
  value TEXT NOT NULL,
  updated_at INTEGER NOT NULL
)
''');

    await _ensureColumn(db, tableName, 'priority_1_slot_key', 'TEXT');
    await _ensureColumn(db, tableName, 'priority_2_slot_key', 'TEXT');
    await _ensureColumn(db, tableName, 'priority_3_slot_key', 'TEXT');

    await db.execute(
      'CREATE UNIQUE INDEX IF NOT EXISTS idx_vehicle_parking_pref_unique_model ON $tableName (manufacturer_name, model_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicle_parking_pref_manufacturer ON $tableName (manufacturer_name)',
    );
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_vehicle_parking_pref_model ON $tableName (model_name)',
    );
  }

  static Future<void> _ensureColumn(
    Database db,
    String table,
    String column,
    String type,
  ) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name'] == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $type');
  }

  static Future<int> _currentSeedVersion(Database db) async {
    final rows = await db.query(
      _metaTableName,
      columns: const <String>['value'],
      where: 'key = ?',
      whereArgs: const <Object?>['vehicle_seed_version'],
      limit: 1,
    );
    if (rows.isEmpty) return 0;
    return int.tryParse((rows.first['value'] ?? '').toString()) ?? 0;
  }

  static Future<void> _setSeedVersion(Database db, int version) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.insert(
      _metaTableName,
      <String, Object?>{
        'key': 'vehicle_seed_version',
        'value': version.toString(),
        'updated_at': now,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  static Future<void> _applySeedDataIfNeeded(
    Database db, {
    bool force = false,
  }) async {
    final current = await _currentSeedVersion(db);
    if (!force && current >= _seedVersion) return;

    final batch = db.batch();
    for (final key in _obsoleteSeedKeys) {
      batch.delete(
        tableName,
        where: 'manufacturer_name = ? AND model_name = ?',
        whereArgs: <Object?>[key.manufacturerName, key.modelName],
      );
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final row in _seedRows) {
      batch.insert(
        tableName,
        <String, Object?>{
          'manufacturer_name': row.manufacturerName,
          'model_name': row.modelName,
          'priority_1_slot_key': row.priority1SlotKey,
          'priority_2_slot_key': row.priority2SlotKey,
          'priority_3_slot_key': row.priority3SlotKey,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    }
    await batch.commit(noResult: true);
    await _setSeedVersion(db, _seedVersion);
  }

  Future<List<String>> getManufacturers() async {
    final db = await database;
    final rows = await db.query(
      tableName,
      columns: const <String>['manufacturer_name'],
      distinct: true,
      orderBy: 'manufacturer_name ASC',
    );

    return rows
        .map((e) => ((e['manufacturer_name'] as String?) ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<List<String>> getModelsByManufacturer(String manufacturerName) async {
    final db = await database;
    final cleanManufacturerName = manufacturerName.trim();
    if (cleanManufacturerName.isEmpty) return const <String>[];

    final rows = await db.query(
      tableName,
      columns: const <String>['model_name'],
      where: 'manufacturer_name = ?',
      whereArgs: <Object?>[cleanManufacturerName],
      orderBy: 'model_name ASC',
    );

    return rows
        .map((e) => ((e['model_name'] as String?) ?? '').trim())
        .where((e) => e.isNotEmpty)
        .toList(growable: false);
  }

  Future<VehicleParkingPreference?> findPreference({
    required String manufacturerName,
    required String modelName,
  }) async {
    final db = await database;
    final cleanManufacturerName = manufacturerName.trim();
    final cleanModelName = modelName.trim();
    if (cleanManufacturerName.isEmpty || cleanModelName.isEmpty) return null;

    final rows = await db.query(
      tableName,
      where: 'manufacturer_name = ? AND model_name = ?',
      whereArgs: <Object?>[cleanManufacturerName, cleanModelName],
      limit: 1,
    );

    if (rows.isEmpty) return null;
    return VehicleParkingPreference.fromMap(rows.first);
  }

  Future<void> upsertPreference({
    required String manufacturerName,
    required String modelName,
    required String priority1SlotKey,
    String? priority2SlotKey,
    String? priority3SlotKey,
  }) async {
    final db = await database;
    final cleanManufacturerName = manufacturerName.trim();
    final cleanModelName = modelName.trim();
    final cleanPriority1SlotKey = ParkingSlotPreferenceKey.normalize(priority1SlotKey);
    final cleanPriority2SlotKey = priority2SlotKey == null
        ? null
        : ParkingSlotPreferenceKey.normalize(priority2SlotKey);
    final cleanPriority3SlotKey = priority3SlotKey == null
        ? null
        : ParkingSlotPreferenceKey.normalize(priority3SlotKey);

    if (cleanManufacturerName.isEmpty || cleanModelName.isEmpty) return;
    if (!ParkingSlotPreferenceKey.isValid(cleanPriority1SlotKey)) return;
    if (cleanPriority2SlotKey != null &&
        cleanPriority2SlotKey.isNotEmpty &&
        !ParkingSlotPreferenceKey.isValid(cleanPriority2SlotKey)) return;
    if (cleanPriority3SlotKey != null &&
        cleanPriority3SlotKey.isNotEmpty &&
        !ParkingSlotPreferenceKey.isValid(cleanPriority3SlotKey)) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final existing = await findPreference(
      manufacturerName: cleanManufacturerName,
      modelName: cleanModelName,
    );

    if (existing == null) {
      await db.insert(
        tableName,
        <String, Object?>{
          'manufacturer_name': cleanManufacturerName,
          'model_name': cleanModelName,
          'priority_1_slot_key': cleanPriority1SlotKey,
          'priority_2_slot_key': cleanPriority2SlotKey,
          'priority_3_slot_key': cleanPriority3SlotKey,
          'created_at': now,
          'updated_at': now,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      return;
    }

    await db.update(
      tableName,
      <String, Object?>{
        'priority_1_slot_key': cleanPriority1SlotKey,
        'priority_2_slot_key': cleanPriority2SlotKey,
        'priority_3_slot_key': cleanPriority3SlotKey,
        'updated_at': now,
      },
      where: 'manufacturer_name = ? AND model_name = ?',
      whereArgs: <Object?>[cleanManufacturerName, cleanModelName],
    );
  }
}

class _VehicleParkingPreferenceSeed {
  final String manufacturerName;
  final String modelName;
  final String priority1SlotKey;
  final String? priority2SlotKey;
  final String? priority3SlotKey;

  const _VehicleParkingPreferenceSeed({
    required this.manufacturerName,
    required this.modelName,
    required this.priority1SlotKey,
    this.priority2SlotKey,
    this.priority3SlotKey,
  });
}
