import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class OperationalCacheDatabase {
  OperationalCacheDatabase._();

  static final OperationalCacheDatabase instance = OperationalCacheDatabase._();

  static const String databaseName = 'operational_cache.db';
  static const int databaseVersion = 1;

  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final databasesPath = await getDatabasesPath();
    final path = p.join(databasesPath, databaseName);
    _database = await openDatabase(
      path,
      version: databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, _) => _ensureSchema(db),
      onUpgrade: (db, _, __) => _ensureSchema(db),
      onOpen: _ensureSchema,
    );
    return _database!;
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS operational_locations (
  area TEXT NOT NULL,
  id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (area, id)
)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_operational_locations_area
ON operational_locations(area)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS operational_general_bills (
  area TEXT NOT NULL,
  id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (area, id)
)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_operational_general_bills_area
ON operational_general_bills(area)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS operational_regular_bills (
  area TEXT NOT NULL,
  id TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (area, id)
)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_operational_regular_bills_area
ON operational_regular_bills(area)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS operational_sectors (
  area TEXT NOT NULL,
  id TEXT NOT NULL,
  normalized_name TEXT NOT NULL,
  payload_json TEXT NOT NULL,
  PRIMARY KEY (area, id),
  UNIQUE (area, normalized_name)
)
''');
    await db.execute('''
CREATE INDEX IF NOT EXISTS idx_operational_sectors_area
ON operational_sectors(area)
''');
    await db.execute('''
CREATE TABLE IF NOT EXISTS operational_area_meta (
  area TEXT PRIMARY KEY,
  locations_ready INTEGER NOT NULL DEFAULT 0,
  general_bills_ready INTEGER NOT NULL DEFAULT 0,
  regular_bills_ready INTEGER NOT NULL DEFAULT 0,
  sectors_ready INTEGER NOT NULL DEFAULT 0,
  location_count INTEGER NOT NULL DEFAULT 0,
  general_bill_count INTEGER NOT NULL DEFAULT 0,
  regular_bill_count INTEGER NOT NULL DEFAULT 0,
  sector_count INTEGER NOT NULL DEFAULT 0,
  total_capacity INTEGER NOT NULL DEFAULT 0,
  has_monthly_parking INTEGER,
  synced_at_iso TEXT
)
''');
  }
}
