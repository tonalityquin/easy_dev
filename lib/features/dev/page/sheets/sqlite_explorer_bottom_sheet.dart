import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../../application/debug_session_controller.dart';
import '../../presentation/debug_tool_shell.dart';

class SQLiteExplorerBottomSheet extends StatefulWidget {
  const SQLiteExplorerBottomSheet({super.key});

  static Future<T?> showFullScreen<T>(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return Navigator.of(context, rootNavigator: true).push<T>(
      PageRouteBuilder<T>(
        opaque: true,
        transitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        reverseTransitionDuration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        pageBuilder: (_, __, ___) => const SQLiteExplorerBottomSheet(),
        transitionsBuilder: (_, animation, __, child) {
          final curved = CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
            reverseCurve: Curves.easeInCubic,
          );
          return FadeTransition(
            opacity: curved,
            child: SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0.025, 0),
                end: Offset.zero,
              ).animate(curved),
              child: child,
            ),
          );
        },
      ),
    );
  }

  @override
  State<SQLiteExplorerBottomSheet> createState() =>
      _SQLiteExplorerBottomSheetState();
}

enum _SQLitePane { rows, schema }

class _SQLiteExplorerBottomSheetState extends State<SQLiteExplorerBottomSheet> {
  static final RegExp _dbExtPattern =
      RegExp(r'\.(db|sqlite|sqlite3|db3)$', caseSensitive: false);

  late Future<_DbScanResult> _scanFuture;
  Future<List<_TableMeta>>? _tablesFuture;
  Future<List<Map<String, Object?>>>? _rowsFuture;

  String? _selectedDbPath;
  String? _selectedTable;
  _TableMeta? _selectedTableMeta;
  _SQLitePane _pane = _SQLitePane.rows;
  int _direction = 1;
  int _revision = 0;

  final TextEditingController _rowSearchController = TextEditingController();
  final ScrollController _wideHorizontalController = ScrollController();
  final ScrollController _wideVerticalController = ScrollController();

  bool get _reduceMotion => MediaQuery.of(context).disableAnimations;

  @override
  void initState() {
    super.initState();
    _scanFuture = _scanDatabases();
    DebugSessionController.record(
      'sqlite_explorer_open',
      source: 'sqlite',
    );
  }

  @override
  void dispose() {
    _rowSearchController.dispose();
    _wideHorizontalController.dispose();
    _wideVerticalController.dispose();
    super.dispose();
  }

  bool _isSidecar(String lower) {
    return lower.endsWith('-journal') ||
        lower.endsWith('-wal') ||
        lower.endsWith('-shm');
  }

  Future<bool> _isSQLiteFile(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) return false;
      final raf = await file.open();
      try {
        if (await raf.length() < 16) return false;
        final Uint8List bytes = await raf.read(16);
        const magic = <int>[
          0x53,
          0x51,
          0x4C,
          0x69,
          0x74,
          0x65,
          0x20,
          0x66,
          0x6F,
          0x72,
          0x6D,
          0x61,
          0x74,
          0x20,
          0x33,
          0x00,
        ];
        if (bytes.length < magic.length) return false;
        for (var index = 0; index < magic.length; index++) {
          if (bytes[index] != magic[index]) return false;
        }
        return true;
      } finally {
        await raf.close();
      }
    } catch (_) {
      return false;
    }
  }

  Future<_DbScanResult> _scanDatabases() async {
    final dbDir = await getDatabasesPath();
    final directory = Directory(dbDir);
    if (!await directory.exists()) {
      return _DbScanResult(dbDir, const <_DbFile>[]);
    }
    final files = <_DbFile>[];
    for (final entity in await directory.list().toList()) {
      if (entity is! File) continue;
      final lower = p.basename(entity.path).toLowerCase();
      if (_isSidecar(lower)) continue;
      if (!_dbExtPattern.hasMatch(lower)) continue;
      if (!await _isSQLiteFile(entity.path)) continue;
      files.add(
        _DbFile(
          path: entity.path,
          name: p.basename(entity.path),
          size: await entity.length(),
        ),
      );
    }
    files.sort((a, b) => a.name.compareTo(b.name));
    DebugSessionController.record(
      'sqlite_scan_complete',
      source: 'sqlite',
      meta: <String, Object?>{'databases': files.length, 'directory': dbDir},
    );
    return _DbScanResult(dbDir, files);
  }

  String _quoteIdentifier(String value) {
    return '"${value.replaceAll('"', '""')}"';
  }

  String _quotePragmaString(String value) {
    return value.replaceAll("'", "''");
  }

  Future<List<_TableMeta>> _loadTables(String dbPath) async {
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final rows = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' "
        "AND name NOT LIKE 'sqlite_%' AND name != 'android_metadata' ORDER BY name",
      );
      final tables = <_TableMeta>[];
      for (final row in rows) {
        final name = row['name']?.toString() ?? '';
        if (name.isEmpty) continue;
        var count = 0;
        try {
          final countRows = await db.rawQuery(
            'SELECT COUNT(*) AS c FROM ${_quoteIdentifier(name)}',
          );
          final value = countRows.isEmpty ? null : countRows.first['c'];
          if (value is num) count = value.toInt();
        } catch (_) {}
        final columns = <_ColumnMeta>[];
        try {
          final columnRows = await db.rawQuery(
            "PRAGMA table_info('${_quotePragmaString(name)}')",
          );
          for (final column in columnRows) {
            columns.add(
              _ColumnMeta(
                cid: (column['cid'] as num?)?.toInt() ?? 0,
                name: column['name']?.toString() ?? '',
                type: column['type']?.toString() ?? '',
                notnull: ((column['notnull'] as num?)?.toInt() ?? 0) == 1,
                dflt: column['dflt_value']?.toString(),
                pk: ((column['pk'] as num?)?.toInt() ?? 0) == 1,
              ),
            );
          }
        } catch (_) {}
        tables.add(
          _TableMeta(
            name: name,
            rowCount: count,
            columns: columns,
          ),
        );
      }
      DebugSessionController.record(
        'sqlite_tables_loaded',
        source: 'sqlite',
        meta: <String, Object?>{
          'database': p.basename(dbPath),
          'tables': tables.length,
        },
      );
      return tables;
    } finally {
      await db.close();
    }
  }

  Future<List<Map<String, Object?>>> _loadRows(
    String dbPath,
    String table,
  ) async {
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false,
    );
    try {
      final rows = await db.rawQuery(
        'SELECT * FROM ${_quoteIdentifier(table)} LIMIT 100',
      );
      DebugSessionController.record(
        'sqlite_rows_loaded',
        source: 'sqlite',
        meta: <String, Object?>{
          'database': p.basename(dbPath),
          'table': table,
          'rows': rows.length,
        },
      );
      return rows;
    } finally {
      await db.close();
    }
  }

  void _openDatabase(_DbFile file) {
    HapticFeedback.selectionClick();
    setState(() {
      _direction = 1;
      _selectedDbPath = file.path;
      _selectedTable = null;
      _selectedTableMeta = null;
      _pane = _SQLitePane.rows;
      _tablesFuture = _loadTables(file.path);
      _rowsFuture = null;
      _revision++;
    });
    DebugSessionController.record(
      'sqlite_database_open',
      source: 'sqlite',
      meta: <String, Object?>{'database': file.name},
    );
  }

  void _openTable(_TableMeta table) {
    final dbPath = _selectedDbPath;
    if (dbPath == null) return;
    HapticFeedback.selectionClick();
    setState(() {
      _direction = 1;
      _selectedTable = table.name;
      _selectedTableMeta = table;
      _pane = _SQLitePane.rows;
      _rowSearchController.clear();
      _rowsFuture = _loadRows(dbPath, table.name);
      _revision++;
    });
    DebugSessionController.record(
      'sqlite_table_open',
      source: 'sqlite',
      meta: <String, Object?>{
        'database': p.basename(dbPath),
        'table': table.name,
      },
    );
  }

  void _back() {
    HapticFeedback.selectionClick();
    setState(() {
      _direction = -1;
      if (_selectedTable != null) {
        _selectedTable = null;
        _selectedTableMeta = null;
        _rowsFuture = null;
        _rowSearchController.clear();
      } else if (_selectedDbPath != null) {
        _selectedDbPath = null;
        _tablesFuture = null;
      }
      _revision++;
    });
  }

  Future<void> _refreshCurrent() async {
    HapticFeedback.selectionClick();
    setState(() {
      if (_selectedDbPath == null) {
        _scanFuture = _scanDatabases();
      } else if (_selectedTable == null) {
        _tablesFuture = _loadTables(_selectedDbPath!);
      } else {
        _rowsFuture = _loadRows(_selectedDbPath!, _selectedTable!);
      }
      _revision++;
    });
    DebugSessionController.record(
      'sqlite_refresh',
      source: 'sqlite',
      meta: <String, Object?>{'route': _breadcrumb},
    );
  }

  Future<void> _confirmAndDeleteDb(String dbPath) async {
    final fileName = p.basename(dbPath);
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _SQLiteConfirmDialog(
            title: '데이터베이스 삭제',
            route: 'Developer / SQLite / $fileName',
            description: '$fileName 파일과 연결된 journal 데이터를 삭제합니다.',
            confirmLabel: '삭제',
          ),
        ) ??
        false;
    if (!ok) return;
    final result = await _deleteDbFiles(dbPath);
    DebugSessionController.record(
      result.errorMessage == null
          ? 'sqlite_database_delete'
          : 'sqlite_database_delete_failed',
      source: 'sqlite',
      meta: <String, Object?>{
        'database': fileName,
        if (result.errorMessage != null) 'error': result.errorMessage!,
      },
    );
    if (!mounted) return;
    if (result.errorMessage != null) {
      _showMessage('삭제하지 못했습니다: ${result.errorMessage}');
      return;
    }
    _showMessage('삭제했습니다: $fileName');
    setState(() {
      if (_selectedDbPath == dbPath) {
        _selectedDbPath = null;
        _selectedTable = null;
        _selectedTableMeta = null;
        _tablesFuture = null;
        _rowsFuture = null;
      }
      _scanFuture = _scanDatabases();
      _revision++;
    });
  }

  Future<_DeleteResult> _deleteDbFiles(String dbPath) async {
    final directory = Directory(p.dirname(dbPath));
    final base = p.basename(dbPath).toLowerCase();
    try {
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}
      if (await directory.exists()) {
        final journalPattern = RegExp('^${RegExp.escape(base)}(?:-journal)+\$');
        for (final entity in await directory.list().toList()) {
          if (entity is! File) continue;
          final lower = p.basename(entity.path).toLowerCase();
          final target = lower == base ||
              lower == '$base-wal' ||
              lower == '$base-shm' ||
              journalPattern.hasMatch(lower);
          if (!target) continue;
          try {
            await entity.delete();
          } catch (_) {}
        }
      }
      if (await File(dbPath).exists()) {
        return const _DeleteResult(errorMessage: '파일이 사용 중입니다.');
      }
      return const _DeleteResult();
    } catch (error) {
      return _DeleteResult(errorMessage: error.toString());
    }
  }

  Object? _parseValue(String input) {
    final value = input.trim();
    if (value.isEmpty) return '';
    final lower = value.toLowerCase();
    if (lower == 'null') return null;
    if (lower == 'true') return true;
    if (lower == 'false') return false;
    final integer = int.tryParse(value);
    if (integer != null) return integer;
    final decimal = double.tryParse(value);
    if (decimal != null) return decimal;
    return value;
  }

  Future<void> _insertRow() async {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    final meta = _selectedTableMeta;
    if (dbPath == null || table == null || meta == null) return;
    final controllers = <String, TextEditingController>{
      for (final column in meta.columns)
        column.name: TextEditingController(),
    };
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _SQLiteRowEditorDialog(
            title: '새 행 추가',
            route: 'Developer / SQLite / ${p.basename(dbPath)} / $table',
            columns: meta.columns,
            controllers: controllers,
            confirmLabel: '추가',
          ),
        ) ??
        false;
    if (!ok) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }
    final values = <String, Object?>{};
    for (final column in meta.columns) {
      final raw = controllers[column.name]!.text.trim();
      if (raw.isNotEmpty) values[column.name] = _parseValue(raw);
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
    try {
      final db = await openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      );
      try {
        await db.insert(table, values);
      } finally {
        await db.close();
      }
      DebugSessionController.record(
        'sqlite_row_insert',
        source: 'sqlite',
        meta: <String, Object?>{
          'database': p.basename(dbPath),
          'table': table,
          'columns': values.length,
        },
      );
      _showMessage('새 행을 추가했습니다.');
      _reloadRows();
    } catch (error) {
      DebugSessionController.record(
        'sqlite_row_insert_failed',
        source: 'sqlite',
        meta: <String, Object?>{'table': table, 'error': error.toString()},
      );
      _showMessage('행을 추가하지 못했습니다.');
    }
  }

  Future<void> _editRow(Map<String, Object?> row) async {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    final meta = _selectedTableMeta;
    if (dbPath == null || table == null || meta == null) return;
    final pkColumns = meta.columns.where((column) => column.pk).toList();
    if (pkColumns.isEmpty) {
      _showMessage('Primary Key가 없는 테이블은 편집할 수 없습니다.');
      return;
    }
    final controllers = <String, TextEditingController>{
      for (final column in meta.columns)
        column.name: TextEditingController(text: row[column.name]?.toString() ?? ''),
    };
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _SQLiteRowEditorDialog(
            title: '행 편집',
            route: 'Developer / SQLite / ${p.basename(dbPath)} / $table',
            columns: meta.columns,
            controllers: controllers,
            confirmLabel: '저장',
          ),
        ) ??
        false;
    if (!ok) {
      for (final controller in controllers.values) {
        controller.dispose();
      }
      return;
    }
    final values = <String, Object?>{};
    for (final column in meta.columns) {
      values[column.name] = _parseValue(controllers[column.name]!.text);
    }
    for (final controller in controllers.values) {
      controller.dispose();
    }
    final where = pkColumns
        .map((column) => '${_quoteIdentifier(column.name)} = ?')
        .join(' AND ');
    final args = pkColumns.map((column) => row[column.name]).toList();
    try {
      final db = await openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      );
      int updated;
      try {
        updated = await db.update(
          table,
          values,
          where: where,
          whereArgs: args,
        );
      } finally {
        await db.close();
      }
      DebugSessionController.record(
        'sqlite_row_update',
        source: 'sqlite',
        meta: <String, Object?>{'table': table, 'updated': updated},
      );
      _showMessage(updated > 0 ? '행을 저장했습니다.' : '변경할 행을 찾지 못했습니다.');
      _reloadRows();
    } catch (error) {
      DebugSessionController.record(
        'sqlite_row_update_failed',
        source: 'sqlite',
        meta: <String, Object?>{'table': table, 'error': error.toString()},
      );
      _showMessage('행을 저장하지 못했습니다.');
    }
  }

  Future<void> _confirmDeleteRow(Map<String, Object?> row) async {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    final meta = _selectedTableMeta;
    if (dbPath == null || table == null || meta == null) return;
    final pkColumns = meta.columns.where((column) => column.pk).toList();
    if (pkColumns.isEmpty) {
      _showMessage('Primary Key가 없는 테이블은 행을 삭제할 수 없습니다.');
      return;
    }
    final detail = pkColumns
        .map((column) => '${column.name} = ${row[column.name]}')
        .join(', ');
    final ok = await showDialog<bool>(
          context: context,
          builder: (_) => _SQLiteConfirmDialog(
            title: '행 삭제',
            route: 'Developer / SQLite / ${p.basename(dbPath)} / $table',
            description: detail,
            confirmLabel: '삭제',
          ),
        ) ??
        false;
    if (!ok) return;
    final where = pkColumns
        .map((column) => '${_quoteIdentifier(column.name)} = ?')
        .join(' AND ');
    final args = pkColumns.map((column) => row[column.name]).toList();
    try {
      final db = await openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      );
      int deleted;
      try {
        deleted = await db.delete(table, where: where, whereArgs: args);
      } finally {
        await db.close();
      }
      DebugSessionController.record(
        'sqlite_row_delete',
        source: 'sqlite',
        meta: <String, Object?>{'table': table, 'deleted': deleted},
      );
      _showMessage(deleted > 0 ? '행을 삭제했습니다.' : '삭제할 행을 찾지 못했습니다.');
      _reloadRows();
    } catch (error) {
      DebugSessionController.record(
        'sqlite_row_delete_failed',
        source: 'sqlite',
        meta: <String, Object?>{'table': table, 'error': error.toString()},
      );
      _showMessage('행을 삭제하지 못했습니다.');
    }
  }

  void _reloadRows() {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    if (dbPath == null || table == null) return;
    if (!mounted) return;
    setState(() {
      _rowsFuture = _loadRows(dbPath, table);
      _revision++;
    });
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(milliseconds: 1100),
      ),
    );
  }

  String get _breadcrumb {
    final parts = <String>['Developer', 'SQLite'];
    if (_selectedDbPath != null) parts.add(p.basename(_selectedDbPath!));
    if (_selectedTable != null) parts.add(_selectedTable!);
    return parts.join(' / ');
  }

  String get _title {
    if (_selectedTable != null) return _selectedTable!;
    if (_selectedDbPath != null) return p.basename(_selectedDbPath!);
    return 'SQLite Explorer';
  }

  Future<void> _showStatus() async {
    await DebugSessionController.showStatus(
      context,
      source: 'sqlite',
      description: <String>[
        'DEBUG session: ACTIVE',
        'Tool: SQLite Explorer',
        'Route: $_breadcrumb',
        'Pane: ${_pane.name}',
        'Search: ${_rowSearchController.text.trim().isEmpty ? '-' : _rowSearchController.text.trim()}',
      ].join('\n'),
    );
  }

  Future<void> _exitDebug() async {
    final reduceMotion = _reduceMotion;
    DebugSessionController.record(
      'debug_exit_from_tool',
      source: 'sqlite',
      meta: <String, Object?>{'route': _breadcrumb},
    );
    if (mounted) Navigator.of(context, rootNavigator: true).pop();
    if (!reduceMotion) {
      await Future<void>.delayed(const Duration(milliseconds: 160));
    }
    await DebugSessionController.disable(source: 'sqlite');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: cs.surface,
      body: Column(
        children: [
          DebugToolHeader(
            title: _title,
            breadcrumb: _breadcrumb,
            meta: _selectedTable == null
                ? 'Developer database inspector'
                : '${_selectedTableMeta?.rowCount ?? 0} rows · ${_selectedTableMeta?.columns.length ?? 0} columns',
            onBack: _selectedDbPath == null ? null : _back,
            onClose: () => Navigator.of(context, rootNavigator: true).pop(),
            onStatus: _showStatus,
            onDebugExit: _exitDebug,
            actions: [
              IconButton(
                tooltip: '새로고침',
                onPressed: _refreshCurrent,
                icon: const Icon(Icons.refresh_rounded),
              ),
              if (_selectedDbPath != null)
                PopupMenuButton<String>(
                  tooltip: '데이터베이스 메뉴',
                  onSelected: (value) {
                    if (value == 'delete_db') {
                      _confirmAndDeleteDb(_selectedDbPath!);
                    }
                  },
                  itemBuilder: (_) => const [
                    PopupMenuItem(
                      value: 'delete_db',
                      child: Text('데이터베이스 삭제'),
                    ),
                  ],
                  icon: const Icon(Icons.storage_rounded),
                ),
            ],
          ),
          Expanded(
            child: AnimatedSwitcher(
              duration: _reduceMotion
                  ? Duration.zero
                  : const Duration(milliseconds: 210),
              transitionBuilder: (child, animation) {
                final curved = CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                  reverseCurve: Curves.easeInCubic,
                );
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: Offset(0.035 * _direction, 0),
                      end: Offset.zero,
                    ).animate(curved),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(
                key: ValueKey<String>('$_breadcrumb-$_revision'),
                child: _buildRouteBody(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteBody() {
    if (_selectedDbPath == null) return _buildDatabaseList();
    if (_selectedTable == null) return _buildTableList();
    return _buildTableInspector();
  }

  Widget _buildDatabaseList() {
    return FutureBuilder<_DbScanResult>(
      future: _scanFuture,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StateMessage(
            icon: Icons.error_outline_rounded,
            title: '데이터베이스를 읽지 못했습니다.',
            detail: snapshot.error.toString(),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final result = snapshot.data!;
        if (result.files.isEmpty) {
          return _StateMessage(
            icon: Icons.storage_outlined,
            title: 'SQLite 데이터베이스가 없습니다.',
            detail: result.dir,
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          itemCount: result.files.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final file = result.files[index];
            return _DatabaseCard(
              file: file,
              sizeLabel: _formatSize(file.size),
              onOpen: () => _openDatabase(file),
              onDelete: () => _confirmAndDeleteDb(file.path),
            );
          },
        );
      },
    );
  }

  Widget _buildTableList() {
    final future = _tablesFuture ??= _loadTables(_selectedDbPath!);
    return FutureBuilder<List<_TableMeta>>(
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StateMessage(
            icon: Icons.error_outline_rounded,
            title: '테이블을 읽지 못했습니다.',
            detail: snapshot.error.toString(),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final tables = snapshot.data!;
        if (tables.isEmpty) {
          return const _StateMessage(
            icon: Icons.table_rows_outlined,
            title: '테이블이 없습니다.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 28),
          itemCount: tables.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final table = tables[index];
            return _TableCard(
              table: table,
              onOpen: () => _openTable(table),
            );
          },
        );
      },
    );
  }

  Widget _buildTableInspector() {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          child: Row(
            children: [
              ChoiceChip(
                label: const Text('Rows'),
                selected: _pane == _SQLitePane.rows,
                onSelected: (_) => setState(() => _pane = _SQLitePane.rows),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Schema'),
                selected: _pane == _SQLitePane.schema,
                onSelected: (_) => setState(() => _pane = _SQLitePane.schema),
              ),
              const Spacer(),
              if (_pane == _SQLitePane.rows)
                FilledButton.tonalIcon(
                  onPressed: _insertRow,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('새 행'),
                ),
            ],
          ),
        ),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(
          child: AnimatedSwitcher(
            duration: _reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 180),
            child: _pane == _SQLitePane.schema
                ? _buildSchema()
                : _buildRows(),
          ),
        ),
      ],
    );
  }

  Widget _buildSchema() {
    final meta = _selectedTableMeta;
    if (meta == null || meta.columns.isEmpty) {
      return const _StateMessage(
        icon: Icons.schema_outlined,
        title: '스키마 정보가 없습니다.',
      );
    }
    return ListView.separated(
      key: const ValueKey<String>('sqlite_schema'),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      itemCount: meta.columns.length,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        return _SchemaCard(column: meta.columns[index]);
      },
    );
  }

  Widget _buildRows() {
    final future = _rowsFuture ??=
        _loadRows(_selectedDbPath!, _selectedTable!);
    return FutureBuilder<List<Map<String, Object?>>>(
      key: const ValueKey<String>('sqlite_rows'),
      future: future,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _StateMessage(
            icon: Icons.error_outline_rounded,
            title: '행을 읽지 못했습니다.',
            detail: snapshot.error.toString(),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final allRows = snapshot.data!;
        return StatefulBuilder(
          builder: (context, setLocalState) {
            final query = _rowSearchController.text.trim().toLowerCase();
            final rows = query.isEmpty
                ? allRows
                : allRows.where((row) {
                    return row.entries.any(
                      (entry) =>
                          entry.key.toLowerCase().contains(query) ||
                          '${entry.value}'.toLowerCase().contains(query),
                    );
                  }).toList(growable: false);
            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: TextField(
                    controller: _rowSearchController,
                    onChanged: (_) => setLocalState(() {}),
                    decoration: InputDecoration(
                      labelText: '행 검색',
                      prefixIcon: const Icon(Icons.search_rounded),
                      suffixIcon: _rowSearchController.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: '검색 지우기',
                              onPressed: () {
                                _rowSearchController.clear();
                                setLocalState(() {});
                              },
                              icon: const Icon(Icons.clear_rounded),
                            ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                Expanded(
                  child: rows.isEmpty
                      ? const _StateMessage(
                          icon: Icons.table_rows_outlined,
                          title: '표시할 행이 없습니다.',
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            if (constraints.maxWidth >= 720) {
                              return _buildWideRows(rows);
                            }
                            return _buildCompactRows(rows);
                          },
                        ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildCompactRows(List<Map<String, Object?>> rows) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 28),
      itemCount: rows.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        return _RowInspectorCard(
          index: index,
          row: rows[index],
          onEdit: () => _editRow(rows[index]),
          onDelete: () => _confirmDeleteRow(rows[index]),
        );
      },
    );
  }

  Widget _buildWideRows(List<Map<String, Object?>> rows) {
    final meta = _selectedTableMeta;
    final columns = meta == null
        ? rows.first.keys.toList(growable: false)
        : meta.columns
            .map((column) => column.name)
            .where((name) => rows.first.containsKey(name))
            .toList(growable: false);
    return Scrollbar(
      controller: _wideVerticalController,
      thumbVisibility: true,
      notificationPredicate: (notification) =>
          notification.metrics.axis == Axis.vertical,
      child: SingleChildScrollView(
        controller: _wideVerticalController,
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
        child: Scrollbar(
          controller: _wideHorizontalController,
          thumbVisibility: true,
          notificationPredicate: (notification) =>
              notification.metrics.axis == Axis.horizontal,
          child: SingleChildScrollView(
            controller: _wideHorizontalController,
            scrollDirection: Axis.horizontal,
            child: DataTable(
              showCheckboxColumn: false,
              columns: [
                for (final column in columns) DataColumn(label: Text(column)),
                const DataColumn(label: Text('관리')),
              ],
              rows: [
                for (final row in rows)
                  DataRow(
                    onSelectChanged: (_) => _editRow(row),
                    cells: [
                      for (final column in columns)
                        DataCell(
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 220),
                            child: Text(
                              '${row[column]}',
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      DataCell(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: '편집',
                              onPressed: () => _editRow(row),
                              icon: const Icon(Icons.edit_outlined),
                            ),
                            IconButton(
                              tooltip: '삭제',
                              onPressed: () => _confirmDeleteRow(row),
                              icon: const Icon(Icons.delete_outline_rounded),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    return '${(mb / 1024).toStringAsFixed(2)} GB';
  }
}

class _DatabaseCard extends StatelessWidget {
  const _DatabaseCard({
    required this.file,
    required this.sizeLabel,
    required this.onOpen,
    required this.onDelete,
  });

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final _DbFile file;
  final String sizeLabel;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.8)),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: _debugAccent.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.storage_rounded, color: _debugAccent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '$sizeLabel · ${file.path}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontFamily: 'monospace',
                          ),
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                tooltip: '데이터베이스 메뉴',
                onSelected: (value) {
                  if (value == 'open') onOpen();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'open', child: Text('열기')),
                  PopupMenuItem(value: 'delete', child: Text('삭제')),
                ],
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _TableCard extends StatelessWidget {
  const _TableCard({required this.table, required this.onOpen});

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final _TableMeta table;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.75)),
          ),
          child: Row(
            children: [
              const Icon(Icons.table_rows_rounded, color: _debugAccent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      table.name,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${table.rowCount} rows · ${table.columns.length} columns',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _SchemaCard extends StatelessWidget {
  const _SchemaCard({required this.column});

  final _ColumnMeta column;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.72)),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              '${column.cid}',
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          Expanded(
            flex: 3,
            child: Text(
              column.name,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              column.type.isEmpty ? 'TEXT' : column.type,
              style: TextStyle(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
            ),
          ),
          if (column.pk)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Chip(label: Text('PK')),
            ),
          if (column.notnull)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Chip(label: Text('NOT NULL')),
            ),
          if (column.dflt != null && column.dflt!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Tooltip(
                message: 'Default: ${column.dflt}',
                child: const Chip(label: Text('DEFAULT')),
              ),
            ),
        ],
      ),
    );
  }
}

class _RowInspectorCard extends StatelessWidget {
  const _RowInspectorCard({
    required this.index,
    required this.row,
    required this.onEdit,
    required this.onDelete,
  });

  final int index;
  final Map<String, Object?> row;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 11),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.76)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text(
                'ROW ${index + 1}',
                style: TextStyle(
                  color: cs.onSurfaceVariant,
                  fontFamily: 'monospace',
                  fontSize: 10,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              IconButton(
                tooltip: '편집',
                onPressed: onEdit,
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: '삭제',
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          for (final entry in row.entries)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 116,
                    child: Text(
                      entry.key,
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${entry.value}',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SQLiteRowEditorDialog extends StatelessWidget {
  const _SQLiteRowEditorDialog({
    required this.title,
    required this.route,
    required this.columns,
    required this.controllers,
    required this.confirmLabel,
  });

  final String title;
  final String route;
  final List<_ColumnMeta> columns;
  final Map<String, TextEditingController> controllers;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _SQLiteDialogTitle(title: title, route: route),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final column in columns)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: TextField(
                    controller: controllers[column.name],
                    decoration: InputDecoration(
                      labelText:
                          '${column.name} · ${column.type.isEmpty ? 'TEXT' : column.type}${column.pk ? ' · PK' : ''}',
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

class _SQLiteConfirmDialog extends StatelessWidget {
  const _SQLiteConfirmDialog({
    required this.title,
    required this.route,
    required this.description,
    required this.confirmLabel,
  });

  final String title;
  final String route;
  final String description;
  final String confirmLabel;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: _SQLiteDialogTitle(title: title, route: route),
      content: Text(description),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(confirmLabel),
        ),
      ],
    );
  }
}

class _SQLiteDialogTitle extends StatelessWidget {
  const _SQLiteDialogTitle({required this.title, required this.route});

  static const Color _debugAccent = Color(0xFF6D5DFB);

  final String title;
  final String route;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'DEBUG',
          style: TextStyle(
            color: _debugAccent,
            fontFamily: 'monospace',
            fontSize: 10,
            fontWeight: FontWeight.w900,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 5),
        Text(title),
        const SizedBox(height: 3),
        Text(
          route,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'monospace',
              ),
        ),
      ],
    );
  }
}

class _StateMessage extends StatelessWidget {
  const _StateMessage({
    required this.icon,
    required this.title,
    this.detail,
  });

  final IconData icon;
  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 32, color: cs.onSurfaceVariant),
            const SizedBox(height: 10),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (detail != null && detail!.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                detail!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'monospace',
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _DbScanResult {
  const _DbScanResult(this.dir, this.files);

  final String dir;
  final List<_DbFile> files;
}

class _DbFile {
  const _DbFile({required this.path, required this.name, required this.size});

  final String path;
  final String name;
  final int size;
}

class _TableMeta {
  const _TableMeta({
    required this.name,
    required this.rowCount,
    required this.columns,
  });

  final String name;
  final int rowCount;
  final List<_ColumnMeta> columns;
}

class _ColumnMeta {
  const _ColumnMeta({
    required this.cid,
    required this.name,
    required this.type,
    required this.notnull,
    required this.dflt,
    required this.pk,
  });

  final int cid;
  final String name;
  final String type;
  final bool notnull;
  final String? dflt;
  final bool pk;
}

class _DeleteResult {
  const _DeleteResult({this.errorMessage});

  final String? errorMessage;
}
