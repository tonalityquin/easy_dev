import 'dart:convert';

import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import '../domain/sprint_models.dart';

class SprintDatabaseSnapshot {
  const SprintDatabaseSnapshot({
    required this.projects,
    required this.tasks,
    required this.blocks,
    required this.externalEvents,
    required this.attentionItems,
    required this.projectReports,
    required this.activityEvents,
    required this.conflictResolutions,
    required this.googleAccounts,
    required this.calendarProfiles,
    required this.defaultCalendarProfileId,
    required this.workspaceScope,
    required this.selectedDate,
    required this.lastObservedToday,
    required this.weekMode,
    required this.googleCalendarId,
    required this.googleCalendarIdLocked,
    required this.legacyCalendarConfigured,
  });

  final List<SprintProject> projects;
  final List<SprintTask> tasks;
  final List<SprintScheduleBlock> blocks;
  final List<SprintExternalEvent> externalEvents;
  final List<SprintAttentionItem> attentionItems;
  final List<SprintProjectReport> projectReports;
  final List<SprintActivityEvent> activityEvents;
  final List<SprintConflictResolution> conflictResolutions;
  final List<SprintGoogleAccount> googleAccounts;
  final List<SprintCalendarProfile> calendarProfiles;
  final String? defaultCalendarProfileId;
  final SprintWorkspaceScope workspaceScope;
  final DateTime selectedDate;
  final DateTime lastObservedToday;
  final bool weekMode;
  final String googleCalendarId;
  final bool googleCalendarIdLocked;
  final bool legacyCalendarConfigured;
}

class SprintDatabase {
  SprintDatabase._();

  static final SprintDatabase instance = SprintDatabase._();

  static const String _databaseName = 'sprint_mode.db';
  static const int _databaseVersion = 12;
  static const String _legacyMigrationKey = 'legacy_preferences_migrated';
  static const String _calendarProfilesMigrationKey =
      'calendar_profiles_migrated_v10';

  Database? _database;

  Future<Database> get database async {
    final current = _database;
    if (current != null && current.isOpen) return current;
    final databasesPath = await getDatabasesPath();
    final fullPath = p.join(databasesPath, _databaseName);
    _database = await openDatabase(
      fullPath,
      version: _databaseVersion,
      onConfigure: (db) async {
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: _createSchema,
      onUpgrade: _upgradeSchema,
      onOpen: _ensureSchema,
    );
    await _migrateLegacyPreferences(_database!);
    return _database!;
  }

  Future<void> _createSchema(Database db, int version) async {
    await _ensureSchema(db);
  }

  Future<void> _upgradeSchema(
    Database db,
    int oldVersion,
    int _,
  ) async {
    if (oldVersion < 3) {
      await _ensureLifecycleColumns(db);
    }
    await _ensureSchema(db);
    if (oldVersion < 4) {
      await _removeFocusStorage(db);
    }
    if (oldVersion < 5) {
      await _ensureProjectStartColumn(db);
    }
    if (oldVersion < 6) {
      await _ensureAllDayTaskColumns(db);
    }
    if (oldVersion < 7) {
      await _ensureCalendarSyncColumns(db);
    }
    if (oldVersion < 8) {
      await _ensureTaskDescriptionColumn(db);
    }
    if (oldVersion < 9) {
      await _ensureCalendarProfileStorage(db);
    }
    if (oldVersion < 10 && oldVersion >= 9) {
      await _resetLegacyCalendarAccountBinding(db);
      await _setSetting(
        db,
        _calendarProfilesMigrationKey,
        '1',
        DateTime.now().millisecondsSinceEpoch,
      );
    }
    if (oldVersion < 12) {
      await _migrateCalendarProfileRoles(db);
    }
    await _ensureSchema(db);
  }

  Future<void> _ensureAllDayTaskColumns(Database db) async {
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'priority',
      definition: "TEXT NOT NULL DEFAULT 'normal'",
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'start_date_ms',
      definition: 'INTEGER',
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'end_date_ms',
      definition: 'INTEGER',
    );
    await _ensureColumn(
      db,
      table: 'sprint_schedule_blocks',
      column: 'all_day',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      db,
      table: 'sprint_project_reports',
      column: 'total_task_count',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_project_reports',
      column: 'high_priority_completed_count',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_project_reports',
      column: 'on_time_completed_count',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_project_reports',
      column: 'overdue_completed_count',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
  }

  Future<void> _ensureProjectStartColumn(Database db) async {
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'target_start_at_ms',
      definition: 'INTEGER',
    );
  }

  Future<void> _ensureCalendarSyncColumns(Database db) async {
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'google_color_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'calendar_sync_enabled',
      definition: 'INTEGER NOT NULL DEFAULT 1',
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'google_event_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'google_calendar_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'google_sync_state',
      definition: "TEXT NOT NULL DEFAULT 'none'",
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'google_sync_error',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'google_delete_after_sync',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_external_events',
      column: 'color_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_external_events',
      column: 'managed_by_sprint',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_external_events',
      column: 'linked_task_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_external_events',
      column: 'linked_project_id',
      definition: 'TEXT',
    );
  }

  Future<void> _ensureCalendarProfileRoleColumn(Database db) async {
    await _ensureColumn(
      db,
      table: 'sprint_calendar_profiles',
      column: 'profile_role',
      definition: "TEXT NOT NULL DEFAULT 'secondary'",
    );
  }

  Future<void> _migrateCalendarProfileRoles(Database db) async {
    await _ensureCalendarProfileRoleColumn(db);
    await db.update(
      'sprint_calendar_profiles',
      <String, Object?>{'profile_role': 'secondary'},
      where: 'deleted_at_ms IS NULL',
    );
    final settings = await db.query(
      'sprint_settings',
      columns: <String>['setting_key', 'setting_value'],
      where: 'setting_key IN (?, ?)',
      whereArgs: <Object?>[
        'default_calendar_profile_id',
        'active_calendar_profile_id',
      ],
      orderBy: "CASE setting_key WHEN 'default_calendar_profile_id' THEN 0 ELSE 1 END",
    );
    String? defaultProfileId;
    for (final row in settings) {
      final value = row['setting_value']?.toString().trim();
      if (value?.isNotEmpty == true) {
        final matches = Sqflite.firstIntValue(
              await db.rawQuery(
                '''
                SELECT COUNT(*)
                FROM sprint_calendar_profiles
                WHERE id = ? AND enabled = 1 AND deleted_at_ms IS NULL
                ''',
                <Object?>[value],
              ),
            ) ??
            0;
        if (matches > 0) {
          defaultProfileId = value;
          break;
        }
      }
    }
    if (defaultProfileId == null) {
      final profiles = await db.query(
        'sprint_calendar_profiles',
        columns: <String>['id'],
        where: 'enabled = 1 AND deleted_at_ms IS NULL',
        orderBy: 'sort_order ASC, created_at_ms ASC',
        limit: 1,
      );
      if (profiles.isNotEmpty) {
        defaultProfileId = profiles.first['id']?.toString();
      }
    }
    if (defaultProfileId?.isNotEmpty == true) {
      await db.update(
        'sprint_calendar_profiles',
        <String, Object?>{'profile_role': 'primary'},
        where: 'id = ? AND deleted_at_ms IS NULL',
        whereArgs: <Object?>[defaultProfileId],
      );
      await _setSetting(
        db,
        'default_calendar_profile_id',
        defaultProfileId!,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }

  Future<void> _ensureTaskDescriptionColumn(Database db) async {
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'description',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
  }

  Future<void> _resetLegacyCalendarAccountBinding(Database db) async {
    final profileCount = Sqflite.firstIntValue(
          await db.rawQuery(
            '''
            SELECT COUNT(*)
            FROM sprint_calendar_profiles
            WHERE id = ? AND account_id = ? AND deleted_at_ms IS NULL
            ''',
            <Object?>['legacy-calendar-profile', 'legacy-google-account'],
          ),
        ) ??
        0;
    if (profileCount == 0) return;
    await db.update(
      'sprint_google_accounts',
      <String, Object?>{
        'google_user_id': null,
        'email': '',
        'display_name': '',
        'requires_reauthentication': 1,
        'updated_at_ms': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ? AND deleted_at_ms IS NULL',
      whereArgs: <Object?>['legacy-google-account'],
    );
  }

  Future<void> _ensureCalendarProfileStorage(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_google_accounts (
        id TEXT PRIMARY KEY,
        google_user_id TEXT,
        email TEXT NOT NULL,
        display_name TEXT NOT NULL DEFAULT '',
        requires_reauthentication INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_calendar_profiles (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        label TEXT NOT NULL,
        profile_role TEXT NOT NULL DEFAULT 'secondary',
        locked INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        last_synced_at_ms INTEGER,
        last_sync_error TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY(account_id) REFERENCES sprint_google_accounts(id)
      )
    ''');
    await _ensureCalendarProfileRoleColumn(db);
    await _ensureColumn(
      db,
      table: 'sprint_tasks',
      column: 'google_calendar_profile_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_external_events',
      column: 'calendar_profile_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await _ensureColumn(
      db,
      table: 'sprint_external_events',
      column: 'google_event_id',
      definition: "TEXT NOT NULL DEFAULT ''",
    );
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_calendar_profiles_account
      ON sprint_calendar_profiles(account_id, sort_order)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_external_profile_start
      ON sprint_external_events(calendar_profile_id, start_at_ms)
    ''');
  }

  Future<void> _removeFocusStorage(Database db) async {
    await db.execute('DROP INDEX IF EXISTS idx_sprint_focus_task_started');
    await db.execute('DROP TABLE IF EXISTS sprint_focus_sessions');
    final columns =
        await db.rawQuery('PRAGMA table_info(sprint_project_reports)');
    final hasLegacyColumns = columns.any(
      (row) =>
          row['name'] == 'focus_session_count' ||
          row['name'] == 'stopped_session_count',
    );
    if (!hasLegacyColumns) return;
    await db.execute('DROP TABLE IF EXISTS sprint_project_reports_v4');
    await db.execute('''
      CREATE TABLE sprint_project_reports_v4 (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        completed_at_ms INTEGER NOT NULL,
        total_task_count INTEGER NOT NULL DEFAULT 0,
        high_priority_completed_count INTEGER NOT NULL DEFAULT 0,
        on_time_completed_count INTEGER NOT NULL DEFAULT 0,
        overdue_completed_count INTEGER NOT NULL DEFAULT 0,
        planned_minutes INTEGER NOT NULL,
        actual_minutes INTEGER NOT NULL,
        scheduled_minutes INTEGER NOT NULL,
        completed_task_count INTEGER NOT NULL,
        cancelled_task_count INTEGER NOT NULL,
        postpone_count INTEGER NOT NULL,
        conflict_count INTEGER NOT NULL,
        resolved_conflict_count INTEGER NOT NULL,
        target_delta_days INTEGER NOT NULL,
        review_note TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY(project_id) REFERENCES sprint_projects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      INSERT INTO sprint_project_reports_v4 (
        id,
        project_id,
        completed_at_ms,
        planned_minutes,
        actual_minutes,
        scheduled_minutes,
        completed_task_count,
        cancelled_task_count,
        postpone_count,
        conflict_count,
        resolved_conflict_count,
        target_delta_days,
        review_note,
        created_at_ms,
        updated_at_ms,
        deleted_at_ms
      )
      SELECT
        id,
        project_id,
        completed_at_ms,
        planned_minutes,
        actual_minutes,
        scheduled_minutes,
        completed_task_count,
        cancelled_task_count,
        postpone_count,
        conflict_count,
        resolved_conflict_count,
        target_delta_days,
        review_note,
        created_at_ms,
        updated_at_ms,
        deleted_at_ms
      FROM sprint_project_reports
    ''');
    await db.execute('DROP TABLE sprint_project_reports');
    await db.execute(
      'ALTER TABLE sprint_project_reports_v4 RENAME TO sprint_project_reports',
    );
  }

  Future<void> _ensureLifecycleColumns(Database db) async {
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'status',
      definition: "TEXT NOT NULL DEFAULT 'active'",
    );
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'completed_at_ms',
      definition: 'INTEGER',
    );
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'archived_at_ms',
      definition: 'INTEGER',
    );
    await _ensureColumn(
      db,
      table: 'sprint_projects',
      column: 'reopened_at_ms',
      definition: 'INTEGER',
    );
    await _ensureColumn(
      db,
      table: 'sprint_schedule_blocks',
      column: 'status',
      definition: "TEXT NOT NULL DEFAULT 'planned'",
    );
    await _ensureColumn(
      db,
      table: 'sprint_schedule_blocks',
      column: 'executed_minutes',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_schedule_blocks',
      column: 'locked',
      definition: 'INTEGER NOT NULL DEFAULT 0',
    );
    await _ensureColumn(
      db,
      table: 'sprint_attention_items',
      column: 'task_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_attention_items',
      column: 'block_id',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_attention_items',
      column: 'conflict_type',
      definition: 'TEXT',
    );
    await _ensureColumn(
      db,
      table: 'sprint_attention_items',
      column: 'suggested_at_ms',
      definition: 'INTEGER',
    );
  }

  Future<void> _ensureColumn(
    Database db, {
    required String table,
    required String column,
    required String definition,
  }) async {
    final columns = await db.rawQuery('PRAGMA table_info($table)');
    final exists = columns.any((row) => row['name']?.toString() == column);
    if (exists) return;
    await db.execute('ALTER TABLE $table ADD COLUMN $column $definition');
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_projects (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        icon_key TEXT NOT NULL,
        target_start_at_ms INTEGER,
        target_at_ms INTEGER,
        status TEXT NOT NULL DEFAULT 'active',
        google_color_id TEXT,
        calendar_sync_enabled INTEGER NOT NULL DEFAULT 1,
        completed_at_ms INTEGER,
        archived_at_ms INTEGER,
        reopened_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_tasks (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        title TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '',
        priority TEXT NOT NULL DEFAULT 'normal',
        start_date_ms INTEGER,
        end_date_ms INTEGER,
        estimated_minutes INTEGER NOT NULL,
        actual_minutes INTEGER NOT NULL,
        order_index INTEGER NOT NULL,
        state TEXT NOT NULL,
        placement_mode TEXT NOT NULL,
        deadline_at_ms INTEGER,
        google_event_id TEXT,
        google_calendar_id TEXT,
        google_calendar_profile_id TEXT,
        google_sync_state TEXT NOT NULL DEFAULT 'none',
        google_sync_error TEXT,
        google_delete_after_sync INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY(project_id) REFERENCES sprint_projects(id) ON DELETE SET NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_schedule_blocks (
        id TEXT PRIMARY KEY,
        task_id TEXT NOT NULL,
        start_at_ms INTEGER NOT NULL,
        end_at_ms INTEGER NOT NULL,
        all_day INTEGER NOT NULL DEFAULT 1,
        completed INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'planned',
        executed_minutes INTEGER NOT NULL DEFAULT 0,
        locked INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY(task_id) REFERENCES sprint_tasks(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_external_events (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        start_at_ms INTEGER NOT NULL,
        end_at_ms INTEGER NOT NULL,
        all_day INTEGER NOT NULL DEFAULT 0,
        blocks_time INTEGER NOT NULL DEFAULT 1,
        source_url TEXT,
        color_id TEXT,
        managed_by_sprint INTEGER NOT NULL DEFAULT 0,
        linked_task_id TEXT,
        linked_project_id TEXT,
        calendar_id TEXT NOT NULL,
        calendar_profile_id TEXT NOT NULL DEFAULT '',
        google_event_id TEXT NOT NULL DEFAULT '',
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_attention_items (
        id TEXT PRIMARY KEY,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        project_id TEXT,
        task_id TEXT,
        block_id TEXT,
        conflict_type TEXT,
        suggested_at_ms INTEGER,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        FOREIGN KEY(project_id) REFERENCES sprint_projects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_project_reports (
        id TEXT PRIMARY KEY,
        project_id TEXT NOT NULL,
        completed_at_ms INTEGER NOT NULL,
        total_task_count INTEGER NOT NULL DEFAULT 0,
        high_priority_completed_count INTEGER NOT NULL DEFAULT 0,
        on_time_completed_count INTEGER NOT NULL DEFAULT 0,
        overdue_completed_count INTEGER NOT NULL DEFAULT 0,
        planned_minutes INTEGER NOT NULL,
        actual_minutes INTEGER NOT NULL,
        scheduled_minutes INTEGER NOT NULL,
        completed_task_count INTEGER NOT NULL,
        cancelled_task_count INTEGER NOT NULL,
        postpone_count INTEGER NOT NULL,
        conflict_count INTEGER NOT NULL,
        resolved_conflict_count INTEGER NOT NULL,
        target_delta_days INTEGER NOT NULL,
        review_note TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY(project_id) REFERENCES sprint_projects(id) ON DELETE CASCADE
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_activity_events (
        id TEXT PRIMARY KEY,
        project_id TEXT,
        task_id TEXT,
        block_id TEXT,
        event_type TEXT NOT NULL,
        occurred_at_ms INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        created_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_conflict_resolutions (
        id TEXT PRIMARY KEY,
        block_id TEXT,
        conflict_key TEXT NOT NULL,
        resolution_type TEXT NOT NULL,
        resolved_at_ms INTEGER NOT NULL,
        created_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_google_accounts (
        id TEXT PRIMARY KEY,
        google_user_id TEXT,
        email TEXT NOT NULL,
        display_name TEXT NOT NULL DEFAULT '',
        requires_reauthentication INTEGER NOT NULL DEFAULT 0,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_calendar_profiles (
        id TEXT PRIMARY KEY,
        account_id TEXT NOT NULL,
        calendar_id TEXT NOT NULL,
        label TEXT NOT NULL,
        profile_role TEXT NOT NULL DEFAULT 'secondary',
        locked INTEGER NOT NULL DEFAULT 0,
        enabled INTEGER NOT NULL DEFAULT 1,
        sort_order INTEGER NOT NULL DEFAULT 0,
        last_synced_at_ms INTEGER,
        last_sync_error TEXT,
        created_at_ms INTEGER NOT NULL,
        updated_at_ms INTEGER NOT NULL,
        deleted_at_ms INTEGER,
        FOREIGN KEY(account_id) REFERENCES sprint_google_accounts(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS sprint_settings (
        setting_key TEXT PRIMARY KEY,
        setting_value TEXT NOT NULL,
        updated_at_ms INTEGER NOT NULL
      )
    ''');
    await _ensureLifecycleColumns(db);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_tasks_project_order
      ON sprint_tasks(project_id, order_index)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_blocks_task_start
      ON sprint_schedule_blocks(task_id, start_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_blocks_start_end
      ON sprint_schedule_blocks(start_at_ms, end_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_external_start_end
      ON sprint_external_events(start_at_ms, end_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_reports_project_completed
      ON sprint_project_reports(project_id, completed_at_ms)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_activity_project_occurred
      ON sprint_activity_events(project_id, occurred_at_ms)
    ''');
    await _ensureProjectStartColumn(db);
    await _ensureAllDayTaskColumns(db);
    await _ensureCalendarSyncColumns(db);
    await _ensureTaskDescriptionColumn(db);
    await _ensureCalendarProfileStorage(db);
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_sprint_conflict_block_key
      ON sprint_conflict_resolutions(block_id, conflict_key)
    ''');
  }

  Future<void> _migrateLegacyPreferences(Database db) async {
    final migrated = await _setting(db, _legacyMigrationKey);
    if (migrated == '1') return;
    final preferences = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    final existingProjectCount = Sqflite.firstIntValue(
          await db.rawQuery('SELECT COUNT(*) FROM sprint_projects'),
        ) ??
        0;
    if (existingProjectCount == 0) {
      final encoded = preferences.getString('sprint_custom_projects');
      if (encoded != null && encoded.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(encoded);
          if (decoded is List) {
            for (final item in decoded) {
              if (item is! Map) continue;
              final id = item['id']?.toString().trim() ?? '';
              final name = item['name']?.toString().trim() ?? '';
              final iconKey = item['iconKey']?.toString().trim() ?? 'folder';
              final targetStartDate = DateTime.tryParse(
                item['targetStartDate']?.toString() ?? '',
              );
              final targetDate = DateTime.tryParse(
                item['targetDate']?.toString() ?? '',
              );
              if (id.isEmpty || name.isEmpty) continue;
              await db.insert(
                'sprint_projects',
                <String, Object?>{
                  'id': id,
                  'name': name,
                  'icon_key': sprintProjectIcons.containsKey(iconKey)
                      ? iconKey
                      : 'folder',
                  'target_start_at_ms':
                      targetStartDate?.millisecondsSinceEpoch,
                  'target_at_ms': targetDate?.millisecondsSinceEpoch,
                  'created_at_ms': now,
                  'updated_at_ms': now,
                  'deleted_at_ms': null,
                },
                conflictAlgorithm: ConflictAlgorithm.ignore,
              );
            }
          }
        } catch (_) {}
      }
    }
    final calendarId = preferences.getString('sprint_google_calendar_id');
    final calendarLocked =
        preferences.getBool('sprint_google_calendar_id_locked');
    final selectedProject =
        preferences.getString('sprint_selected_project_id');
    if (calendarId != null && calendarId.trim().isNotEmpty) {
      await _setSetting(db, 'google_calendar_id', calendarId.trim(), now);
    }
    if (calendarLocked != null) {
      await _setSetting(
        db,
        'google_calendar_id_locked',
        calendarLocked ? '1' : '0',
        now,
      );
    }
    if (selectedProject != null && selectedProject.trim().isNotEmpty) {
      final exists = Sqflite.firstIntValue(
            await db.rawQuery(
              'SELECT COUNT(*) FROM sprint_projects WHERE id = ?',
              <Object?>[selectedProject.trim()],
            ),
          ) ??
          0;
      if (exists > 0) {
        await _setSetting(
          db,
          'workspace_scope',
          SprintWorkspaceScope.project(selectedProject.trim()).storageValue,
          now,
        );
      }
    }
    await _setSetting(db, _legacyMigrationKey, '1', now);
    await preferences.remove('sprint_custom_projects');
    await preferences.remove('sprint_google_calendar_id');
    await preferences.remove('sprint_google_calendar_id_locked');
    await preferences.remove('sprint_selected_project_id');
  }

  Future<String?> _setting(DatabaseExecutor db, String key) async {
    final rows = await db.query(
      'sprint_settings',
      columns: <String>['setting_value'],
      where: 'setting_key = ?',
      whereArgs: <Object?>[key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['setting_value']?.toString();
  }

  Future<void> _setSetting(
    DatabaseExecutor db,
    String key,
    String value,
    int updatedAt,
  ) async {
    await db.insert(
      'sprint_settings',
      <String, Object?>{
        'setting_key': key,
        'setting_value': value,
        'updated_at_ms': updatedAt,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<SprintDatabaseSnapshot> loadSnapshot() async {
    final db = await database;
    final projectRows = await db.query(
      'sprint_projects',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'created_at_ms ASC',
    );
    final taskRows = await db.query(
      'sprint_tasks',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'project_id ASC, order_index ASC, created_at_ms ASC',
    );
    final blockRows = await db.query(
      'sprint_schedule_blocks',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'start_at_ms ASC',
    );
    final externalRows = await db.query(
      'sprint_external_events',
      orderBy: 'start_at_ms ASC',
    );
    final attentionRows = await db.query(
      'sprint_attention_items',
      orderBy: 'created_at_ms ASC',
    );
    final reportRows = await db.query(
      'sprint_project_reports',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'completed_at_ms ASC',
    );
    final activityRows = await db.query(
      'sprint_activity_events',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'occurred_at_ms ASC',
    );
    final resolutionRows = await db.query(
      'sprint_conflict_resolutions',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'resolved_at_ms ASC',
    );
    final accountRows = await db.query(
      'sprint_google_accounts',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'created_at_ms ASC',
    );
    final profileRows = await db.query(
      'sprint_calendar_profiles',
      where: 'deleted_at_ms IS NULL',
      orderBy: 'sort_order ASC, created_at_ms ASC',
    );
    final settingRows = await db.query('sprint_settings');
    final settings = <String, String>{
      for (final row in settingRows)
        if (row['setting_key'] != null && row['setting_value'] != null)
          row['setting_key'].toString(): row['setting_value'].toString(),
    };

    return SprintDatabaseSnapshot(
      projects: projectRows.map(_projectFromRow).toList(growable: false),
      tasks: taskRows.map(_taskFromRow).toList(growable: false),
      blocks: blockRows.map(_blockFromRow).toList(growable: false),
      externalEvents:
          externalRows.map(_externalEventFromRow).toList(growable: false),
      attentionItems:
          attentionRows.map(_attentionFromRow).toList(growable: false),
      projectReports:
          reportRows.map(_projectReportFromRow).toList(growable: false),
      activityEvents:
          activityRows.map(_activityEventFromRow).toList(growable: false),
      conflictResolutions:
          resolutionRows.map(_conflictResolutionFromRow).toList(growable: false),
      googleAccounts:
          accountRows.map(_googleAccountFromRow).toList(growable: false),
      calendarProfiles:
          profileRows.map(_calendarProfileFromRow).toList(growable: false),
      defaultCalendarProfileId:
          settings['default_calendar_profile_id']?.trim().isNotEmpty == true
              ? settings['default_calendar_profile_id']!.trim()
              : settings['active_calendar_profile_id']?.trim().isNotEmpty == true
                  ? settings['active_calendar_profile_id']!.trim()
                  : null,
      workspaceScope: SprintWorkspaceScope.fromStorageValue(
        settings['workspace_scope'],
      ),
      selectedDate: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(settings['selected_date_ms'] ?? '') ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      lastObservedToday: DateTime.fromMillisecondsSinceEpoch(
        int.tryParse(settings['last_observed_today_ms'] ?? '') ??
            DateTime.now().millisecondsSinceEpoch,
      ),
      weekMode: settings['week_mode'] == '1',
      googleCalendarId: settings['google_calendar_id']?.trim().isNotEmpty == true
          ? settings['google_calendar_id']!.trim()
          : 'primary',
      googleCalendarIdLocked:
          settings['google_calendar_id_locked'] == '1',
      legacyCalendarConfigured:
          settings[_calendarProfilesMigrationKey] != '1' &&
              settings['google_calendar_id']?.trim().isNotEmpty == true,
    );
  }

  Future<void> replaceSnapshot(SprintDatabaseSnapshot snapshot) async {
    final db = await database;
    final now = DateTime.now().millisecondsSinceEpoch;
    await db.transaction((transaction) async {
      for (final account in snapshot.googleAccounts) {
        await _upsert(
          transaction,
          table: 'sprint_google_accounts',
          id: account.id,
          insertValues: <String, Object?>{
            'id': account.id,
            'google_user_id': account.googleUserId,
            'email': account.email,
            'display_name': account.displayName,
            'requires_reauthentication':
                account.requiresReauthentication ? 1 : 0,
            'created_at_ms': account.createdAt.millisecondsSinceEpoch,
            'updated_at_ms': account.updatedAt.millisecondsSinceEpoch,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'google_user_id': account.googleUserId,
            'email': account.email,
            'display_name': account.displayName,
            'requires_reauthentication':
                account.requiresReauthentication ? 1 : 0,
            'updated_at_ms': account.updatedAt.millisecondsSinceEpoch,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_google_accounts',
        ids: snapshot.googleAccounts.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );
      for (final profile in snapshot.calendarProfiles) {
        await _upsert(
          transaction,
          table: 'sprint_calendar_profiles',
          id: profile.id,
          insertValues: <String, Object?>{
            'id': profile.id,
            'account_id': profile.accountId,
            'calendar_id': profile.calendarId,
            'label': profile.label,
            'profile_role': profile.role.name,
            'locked': profile.locked ? 1 : 0,
            'enabled': profile.enabled ? 1 : 0,
            'sort_order': profile.sortOrder,
            'last_synced_at_ms': profile.lastSyncedAt?.millisecondsSinceEpoch,
            'last_sync_error': profile.lastSyncError,
            'created_at_ms': profile.createdAt.millisecondsSinceEpoch,
            'updated_at_ms': profile.updatedAt.millisecondsSinceEpoch,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'account_id': profile.accountId,
            'calendar_id': profile.calendarId,
            'label': profile.label,
            'profile_role': profile.role.name,
            'locked': profile.locked ? 1 : 0,
            'enabled': profile.enabled ? 1 : 0,
            'sort_order': profile.sortOrder,
            'last_synced_at_ms': profile.lastSyncedAt?.millisecondsSinceEpoch,
            'last_sync_error': profile.lastSyncError,
            'updated_at_ms': profile.updatedAt.millisecondsSinceEpoch,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_calendar_profiles',
        ids: snapshot.calendarProfiles.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );
      for (final project in snapshot.projects) {
        await _upsert(
          transaction,
          table: 'sprint_projects',
          id: project.id,
          insertValues: <String, Object?>{
            'id': project.id,
            'name': project.name,
            'icon_key': project.iconKey,
            'target_start_at_ms':
                project.targetStartDate?.millisecondsSinceEpoch,
            'target_at_ms': project.targetDate?.millisecondsSinceEpoch,
            'status': project.status.name,
            'google_color_id': project.googleColorId,
            'calendar_sync_enabled': project.calendarSyncEnabled ? 1 : 0,
            'completed_at_ms': project.completedAt?.millisecondsSinceEpoch,
            'archived_at_ms': project.archivedAt?.millisecondsSinceEpoch,
            'reopened_at_ms': project.reopenedAt?.millisecondsSinceEpoch,
            'created_at_ms': project.createdAt.millisecondsSinceEpoch,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'name': project.name,
            'icon_key': project.iconKey,
            'target_start_at_ms':
                project.targetStartDate?.millisecondsSinceEpoch,
            'target_at_ms': project.targetDate?.millisecondsSinceEpoch,
            'status': project.status.name,
            'google_color_id': project.googleColorId,
            'calendar_sync_enabled': project.calendarSyncEnabled ? 1 : 0,
            'completed_at_ms': project.completedAt?.millisecondsSinceEpoch,
            'archived_at_ms': project.archivedAt?.millisecondsSinceEpoch,
            'reopened_at_ms': project.reopenedAt?.millisecondsSinceEpoch,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_projects',
        ids: snapshot.projects.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );

      for (final task in snapshot.tasks) {
        await _upsert(
          transaction,
          table: 'sprint_tasks',
          id: task.id,
          insertValues: <String, Object?>{
            'id': task.id,
            'project_id': task.projectId,
            'title': task.title,
            'description': task.description,
            'priority': task.priority.name,
            'start_date_ms': task.startDate.millisecondsSinceEpoch,
            'end_date_ms': task.endDate.millisecondsSinceEpoch,
            'estimated_minutes': 0,
            'actual_minutes': 0,
            'order_index': task.order,
            'state': task.state.name,
            'placement_mode': task.placementMode.name,
            'deadline_at_ms': task.endDate.millisecondsSinceEpoch,
            'google_event_id': task.googleEventId,
            'google_calendar_id': task.googleCalendarId,
            'google_calendar_profile_id': task.googleCalendarProfileId,
            'google_sync_state': task.googleSyncState.name,
            'google_sync_error': task.googleSyncError,
            'google_delete_after_sync': task.deleteAfterSync ? 1 : 0,
            'created_at_ms': now,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'project_id': task.projectId,
            'title': task.title,
            'description': task.description,
            'priority': task.priority.name,
            'start_date_ms': task.startDate.millisecondsSinceEpoch,
            'end_date_ms': task.endDate.millisecondsSinceEpoch,
            'estimated_minutes': 0,
            'actual_minutes': 0,
            'order_index': task.order,
            'state': task.state.name,
            'placement_mode': task.placementMode.name,
            'deadline_at_ms': task.endDate.millisecondsSinceEpoch,
            'google_event_id': task.googleEventId,
            'google_calendar_id': task.googleCalendarId,
            'google_calendar_profile_id': task.googleCalendarProfileId,
            'google_sync_state': task.googleSyncState.name,
            'google_sync_error': task.googleSyncError,
            'google_delete_after_sync': task.deleteAfterSync ? 1 : 0,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_tasks',
        ids: snapshot.tasks.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );

      for (final block in snapshot.blocks) {
        await _upsert(
          transaction,
          table: 'sprint_schedule_blocks',
          id: block.id,
          insertValues: <String, Object?>{
            'id': block.id,
            'task_id': block.taskId,
            'start_at_ms': block.start.millisecondsSinceEpoch,
            'end_at_ms': block.end.millisecondsSinceEpoch,
            'all_day': block.allDay ? 1 : 0,
            'completed': block.completed ? 1 : 0,
            'status': block.status.name,
            'executed_minutes': 0,
            'locked': block.locked ? 1 : 0,
            'created_at_ms': now,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'task_id': block.taskId,
            'start_at_ms': block.start.millisecondsSinceEpoch,
            'end_at_ms': block.end.millisecondsSinceEpoch,
            'all_day': block.allDay ? 1 : 0,
            'completed': block.completed ? 1 : 0,
            'status': block.status.name,
            'executed_minutes': 0,
            'locked': block.locked ? 1 : 0,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_schedule_blocks',
        ids: snapshot.blocks.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );


      await transaction.delete('sprint_external_events');
      for (final event in snapshot.externalEvents) {
        await transaction.insert(
          'sprint_external_events',
          <String, Object?>{
            'id': event.id,
            'title': event.title,
            'start_at_ms': event.start.millisecondsSinceEpoch,
            'end_at_ms': event.end.millisecondsSinceEpoch,
            'all_day': event.allDay ? 1 : 0,
            'blocks_time': event.blocksTime ? 1 : 0,
            'source_url': event.sourceUrl,
            'color_id': event.colorId,
            'managed_by_sprint': event.managedBySprint ? 1 : 0,
            'linked_task_id': event.linkedTaskId,
            'linked_project_id': event.linkedProjectId,
            'calendar_id': _calendarIdForProfile(
              snapshot.calendarProfiles,
              event.calendarProfileId,
            ),
            'calendar_profile_id': event.calendarProfileId,
            'google_event_id': event.googleEventId,
            'updated_at_ms': now,
          },
        );
      }

      await transaction.delete('sprint_attention_items');
      for (final item in snapshot.attentionItems) {
        await transaction.insert(
          'sprint_attention_items',
          <String, Object?>{
            'id': item.id,
            'title': item.title,
            'description': item.description,
            'project_id': item.projectId,
            'task_id': item.taskId,
            'block_id': item.blockId,
            'conflict_type': item.conflictType?.name,
            'suggested_at_ms': item.suggestedStart?.millisecondsSinceEpoch,
            'created_at_ms': now,
            'updated_at_ms': now,
          },
        );
      }

      for (final report in snapshot.projectReports) {
        await _upsert(
          transaction,
          table: 'sprint_project_reports',
          id: report.id,
          insertValues: <String, Object?>{
            'id': report.id,
            'project_id': report.projectId,
            'completed_at_ms': report.completedAt.millisecondsSinceEpoch,
            'total_task_count': report.totalTaskCount,
            'high_priority_completed_count': report.highPriorityCompletedCount,
            'on_time_completed_count': report.onTimeCompletedCount,
            'overdue_completed_count': report.overdueCompletedCount,
            'planned_minutes': 0,
            'actual_minutes': 0,
            'scheduled_minutes': 0,
            'completed_task_count': report.completedTaskCount,
            'cancelled_task_count': report.cancelledTaskCount,
            'postpone_count': report.postponeCount,
            'conflict_count': report.conflictCount,
            'resolved_conflict_count': report.resolvedConflictCount,
            'target_delta_days': report.targetDeltaDays,
            'review_note': report.reviewNote,
            'created_at_ms': now,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'project_id': report.projectId,
            'completed_at_ms': report.completedAt.millisecondsSinceEpoch,
            'total_task_count': report.totalTaskCount,
            'high_priority_completed_count': report.highPriorityCompletedCount,
            'on_time_completed_count': report.onTimeCompletedCount,
            'overdue_completed_count': report.overdueCompletedCount,
            'planned_minutes': 0,
            'actual_minutes': 0,
            'scheduled_minutes': 0,
            'completed_task_count': report.completedTaskCount,
            'cancelled_task_count': report.cancelledTaskCount,
            'postpone_count': report.postponeCount,
            'conflict_count': report.conflictCount,
            'resolved_conflict_count': report.resolvedConflictCount,
            'target_delta_days': report.targetDeltaDays,
            'review_note': report.reviewNote,
            'updated_at_ms': now,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_project_reports',
        ids: snapshot.projectReports.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );

      for (final event in snapshot.activityEvents) {
        await _upsert(
          transaction,
          table: 'sprint_activity_events',
          id: event.id,
          insertValues: <String, Object?>{
            'id': event.id,
            'project_id': event.projectId,
            'task_id': event.taskId,
            'block_id': event.blockId,
            'event_type': event.type.name,
            'occurred_at_ms': event.occurredAt.millisecondsSinceEpoch,
            'payload_json': jsonEncode(event.payload),
            'created_at_ms': now,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'project_id': event.projectId,
            'task_id': event.taskId,
            'block_id': event.blockId,
            'event_type': event.type.name,
            'occurred_at_ms': event.occurredAt.millisecondsSinceEpoch,
            'payload_json': jsonEncode(event.payload),
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_activity_events',
        ids: snapshot.activityEvents.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );

      for (final resolution in snapshot.conflictResolutions) {
        await _upsert(
          transaction,
          table: 'sprint_conflict_resolutions',
          id: resolution.id,
          insertValues: <String, Object?>{
            'id': resolution.id,
            'block_id': resolution.blockId,
            'conflict_key': resolution.conflictKey,
            'resolution_type': resolution.type.name,
            'resolved_at_ms': resolution.resolvedAt.millisecondsSinceEpoch,
            'created_at_ms': now,
            'deleted_at_ms': null,
          },
          updateValues: <String, Object?>{
            'block_id': resolution.blockId,
            'conflict_key': resolution.conflictKey,
            'resolution_type': resolution.type.name,
            'resolved_at_ms': resolution.resolvedAt.millisecondsSinceEpoch,
            'deleted_at_ms': null,
          },
        );
      }
      await _softDeleteMissing(
        transaction,
        table: 'sprint_conflict_resolutions',
        ids: snapshot.conflictResolutions.map((value) => value.id).toList(growable: false),
        deletedAt: now,
      );

      await _setSetting(
        transaction,
        'workspace_scope',
        snapshot.workspaceScope.storageValue,
        now,
      );
      await _setSetting(
        transaction,
        'selected_date_ms',
        snapshot.selectedDate.millisecondsSinceEpoch.toString(),
        now,
      );
      await _setSetting(
        transaction,
        'last_observed_today_ms',
        snapshot.lastObservedToday.millisecondsSinceEpoch.toString(),
        now,
      );
      await _setSetting(
        transaction,
        'week_mode',
        snapshot.weekMode ? '1' : '0',
        now,
      );
      await _setSetting(
        transaction,
        'default_calendar_profile_id',
        snapshot.defaultCalendarProfileId ?? '',
        now,
      );
      await _setSetting(
        transaction,
        'google_calendar_id',
        snapshot.googleCalendarId,
        now,
      );
      await _setSetting(
        transaction,
        'google_calendar_id_locked',
        snapshot.googleCalendarIdLocked ? '1' : '0',
        now,
      );
      await _setSetting(transaction, _legacyMigrationKey, '1', now);
      await _setSetting(
        transaction,
        _calendarProfilesMigrationKey,
        '1',
        now,
      );
    });
  }

  Future<void> _upsert(
    DatabaseExecutor executor, {
    required String table,
    required String id,
    required Map<String, Object?> insertValues,
    required Map<String, Object?> updateValues,
  }) async {
    final inserted = await executor.insert(
      table,
      insertValues,
      conflictAlgorithm: ConflictAlgorithm.ignore,
    );
    if (inserted != 0) return;
    await executor.update(
      table,
      updateValues,
      where: 'id = ?',
      whereArgs: <Object?>[id],
    );
  }

  Future<void> _softDeleteMissing(
    DatabaseExecutor executor, {
    required String table,
    required List<String> ids,
    required int deletedAt,
  }) async {
    if (ids.isEmpty) {
      await executor.update(
        table,
        <String, Object?>{'deleted_at_ms': deletedAt},
        where: 'deleted_at_ms IS NULL',
      );
      return;
    }
    final placeholders = List<String>.filled(ids.length, '?').join(',');
    await executor.update(
      table,
      <String, Object?>{'deleted_at_ms': deletedAt},
      where: 'deleted_at_ms IS NULL AND id NOT IN ($placeholders)',
      whereArgs: ids,
    );
  }


  SprintGoogleAccount _googleAccountFromRow(Map<String, Object?> row) {
    return SprintGoogleAccount(
      id: row['id'].toString(),
      googleUserId: row['google_user_id']?.toString(),
      email: row['email']?.toString() ?? '',
      displayName: row['display_name']?.toString() ?? '',
      requiresReauthentication:
          _int(row['requires_reauthentication']) != 0,
      createdAt: _date(row['created_at_ms']),
      updatedAt: _date(row['updated_at_ms']),
    );
  }

  SprintCalendarProfile _calendarProfileFromRow(Map<String, Object?> row) {
    return SprintCalendarProfile(
      id: row['id'].toString(),
      accountId: row['account_id'].toString(),
      calendarId: row['calendar_id'].toString(),
      label: row['label'].toString(),
      role: SprintCalendarProfileRole.values.firstWhere(
        (value) => value.name == row['profile_role']?.toString(),
        orElse: () => SprintCalendarProfileRole.secondary,
      ),
      locked: _int(row['locked']) != 0,
      enabled: _int(row['enabled']) != 0,
      sortOrder: _int(row['sort_order']),
      lastSyncedAt: _date(row['last_synced_at_ms']),
      lastSyncError: row['last_sync_error']?.toString(),
      createdAt: _date(row['created_at_ms']),
      updatedAt: _date(row['updated_at_ms']),
    );
  }

  String _calendarIdForProfile(
    List<SprintCalendarProfile> profiles,
    String profileId,
  ) {
    for (final profile in profiles) {
      if (profile.id == profileId) return profile.calendarId;
    }
    return '';
  }

  SprintProject _projectFromRow(Map<String, Object?> row) {
    return SprintProject(
      id: row['id'].toString(),
      name: row['name'].toString(),
      iconKey: row['icon_key'].toString(),
      targetStartDate: _date(row['target_start_at_ms']),
      targetDate: _date(row['target_at_ms']),
      custom: true,
      status: SprintProjectStatus.values.firstWhere(
        (value) => value.name == row['status']?.toString(),
        orElse: () => SprintProjectStatus.active,
      ),
      googleColorId: row['google_color_id']?.toString() ?? '',
      calendarSyncEnabled: _int(row['calendar_sync_enabled']) != 0,
      createdAt: _date(row['created_at_ms']),
      completedAt: _date(row['completed_at_ms']),
      archivedAt: _date(row['archived_at_ms']),
      reopenedAt: _date(row['reopened_at_ms']),
    );
  }

  SprintTask _taskFromRow(Map<String, Object?> row) {
    final storedState = row['state']?.toString();
    final state = storedState == 'active'
        ? SprintTaskState.scheduled
        : SprintTaskState.values.firstWhere(
            (value) => value.name == storedState,
            orElse: () => SprintTaskState.ready,
          );
    final legacyDeadline = _date(row['deadline_at_ms']);
    final startDate = _date(row['start_date_ms']) ?? legacyDeadline ?? DateTime.now();
    final endDate = _date(row['end_date_ms']) ?? legacyDeadline ?? startDate;
    return SprintTask(
      id: row['id'].toString(),
      title: row['title'].toString(),
      description: row['description']?.toString() ?? '',
      projectId: row['project_id']?.toString(),
      priority: SprintTaskPriority.values.firstWhere(
        (value) => value.name == row['priority']?.toString(),
        orElse: () => SprintTaskPriority.normal,
      ),
      startDate: DateTime(startDate.year, startDate.month, startDate.day),
      endDate: DateTime(endDate.year, endDate.month, endDate.day),
      order: _int(row['order_index']),
      state: state,
      placementMode: SprintPlacementMode.values.firstWhere(
        (value) => value.name == row['placement_mode']?.toString(),
        orElse: () => SprintPlacementMode.automatic,
      ),
      googleEventId: row['google_event_id']?.toString(),
      googleCalendarId: row['google_calendar_id']?.toString(),
      googleCalendarProfileId:
          row['google_calendar_profile_id']?.toString(),
      googleSyncState: SprintGoogleSyncState.values.firstWhere(
        (value) => value.name == row['google_sync_state']?.toString(),
        orElse: () => SprintGoogleSyncState.none,
      ),
      googleSyncError: row['google_sync_error']?.toString(),
      deleteAfterSync: _int(row['google_delete_after_sync']) != 0,
    );
  }

  SprintScheduleBlock _blockFromRow(Map<String, Object?> row) {
    return SprintScheduleBlock(
      id: row['id'].toString(),
      taskId: row['task_id'].toString(),
      start: _date(row['start_at_ms'])!,
      end: _date(row['end_at_ms'])!,
      allDay: _int(row['all_day']) != 0,
      completed: _int(row['completed']) == 1,
      status: SprintScheduleBlockStatus.values.firstWhere(
        (value) => value.name == row['status']?.toString(),
        orElse: () => _int(row['completed']) == 1
            ? SprintScheduleBlockStatus.executed
            : SprintScheduleBlockStatus.planned,
      ),
      locked: _int(row['locked']) == 1,
    );
  }

  SprintExternalEvent _externalEventFromRow(Map<String, Object?> row) {
    final profileId = row['calendar_profile_id']?.toString() ?? '';
    final googleEventId =
        row['google_event_id']?.toString().trim().isNotEmpty == true
            ? row['google_event_id']!.toString().trim()
            : row['id'].toString();
    return SprintExternalEvent(
      id: row['id'].toString(),
      googleEventId: googleEventId,
      calendarProfileId: profileId,
      title: row['title'].toString(),
      start: _date(row['start_at_ms'])!,
      end: _date(row['end_at_ms'])!,
      allDay: _int(row['all_day']) == 1,
      blocksTime: _int(row['blocks_time']) == 1,
      sourceUrl: row['source_url']?.toString(),
      colorId: row['color_id']?.toString(),
      managedBySprint: _int(row['managed_by_sprint']) == 1,
      linkedTaskId: row['linked_task_id']?.toString(),
      linkedProjectId: row['linked_project_id']?.toString(),
    );
  }

  SprintAttentionItem _attentionFromRow(Map<String, Object?> row) {
    return SprintAttentionItem(
      id: row['id'].toString(),
      title: row['title'].toString(),
      description: row['description'].toString(),
      projectId: row['project_id']?.toString(),
      taskId: row['task_id']?.toString(),
      blockId: row['block_id']?.toString(),
      conflictType: _conflictType(row['conflict_type']),
      suggestedStart: _date(row['suggested_at_ms']),
    );
  }

  SprintProjectReport _projectReportFromRow(Map<String, Object?> row) {
    final completed = _int(row['completed_task_count']);
    final cancelled = _int(row['cancelled_task_count']);
    final storedTotal = _int(row['total_task_count']);
    return SprintProjectReport(
      id: row['id'].toString(),
      projectId: row['project_id'].toString(),
      completedAt: _date(row['completed_at_ms'])!,
      totalTaskCount: storedTotal > 0 ? storedTotal : completed + cancelled,
      highPriorityCompletedCount: _int(row['high_priority_completed_count']),
      onTimeCompletedCount: _int(row['on_time_completed_count']),
      overdueCompletedCount: _int(row['overdue_completed_count']),
      completedTaskCount: completed,
      cancelledTaskCount: cancelled,
      postponeCount: _int(row['postpone_count']),
      conflictCount: _int(row['conflict_count']),
      resolvedConflictCount: _int(row['resolved_conflict_count']),
      targetDeltaDays: _int(row['target_delta_days']),
      reviewNote: row['review_note']?.toString(),
    );
  }

  SprintActivityEvent _activityEventFromRow(Map<String, Object?> row) {
    Map<String, String> payload = const <String, String>{};
    try {
      final decoded = jsonDecode(row['payload_json']?.toString() ?? '{}');
      if (decoded is Map) {
        payload = <String, String>{
          for (final entry in decoded.entries)
            entry.key.toString(): entry.value.toString(),
        };
      }
    } catch (_) {}
    return SprintActivityEvent(
      id: row['id'].toString(),
      projectId: row['project_id']?.toString(),
      taskId: row['task_id']?.toString(),
      blockId: row['block_id']?.toString(),
      type: SprintActivityEventType.values.firstWhere(
        (value) => value.name == row['event_type']?.toString(),
        orElse: () => SprintActivityEventType.taskUpdated,
      ),
      occurredAt: _date(row['occurred_at_ms'])!,
      payload: payload,
    );
  }

  SprintConflictResolution _conflictResolutionFromRow(
    Map<String, Object?> row,
  ) {
    return SprintConflictResolution(
      id: row['id'].toString(),
      blockId: row['block_id']?.toString(),
      conflictKey: row['conflict_key'].toString(),
      type: SprintConflictResolutionType.values.firstWhere(
        (value) => value.name == row['resolution_type']?.toString(),
        orElse: () => SprintConflictResolutionType.kept,
      ),
      resolvedAt: _date(row['resolved_at_ms'])!,
    );
  }

  SprintConflictType? _conflictType(Object? value) {
    final name = value?.toString();
    if (name == null || name.isEmpty) return null;
    for (final type in SprintConflictType.values) {
      if (type.name == name) return type;
    }
    return null;
  }

  DateTime? _date(Object? value) {
    if (value == null) return null;
    final milliseconds = value is int ? value : int.tryParse(value.toString());
    if (milliseconds == null) return null;
    return DateTime.fromMillisecondsSinceEpoch(milliseconds);
  }

  int _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }
}
