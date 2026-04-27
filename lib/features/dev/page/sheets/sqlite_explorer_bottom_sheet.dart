import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';










class SQLiteExplorerBottomSheet extends StatefulWidget {
  const SQLiteExplorerBottomSheet({super.key});

  
  
  
  
  
  
  
  
  static Future<T?> showFullScreen<T>(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true, 
      isScrollControlled: true,
      useSafeArea: false, 
      showDragHandle: false, 
      backgroundColor: Colors.transparent, 
      
      constraints: BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
      ),
      builder: (ctx) {
        
        final base = Theme.of(context);
        final local = base.copyWith(
          bottomSheetTheme: const BottomSheetThemeData(
            constraints: BoxConstraints(), 
            backgroundColor: Colors.transparent, 
            shape: RoundedRectangleBorder(), 
            elevation: 0,
            showDragHandle: false,
          ),
        );

        return Theme(
          data: local,
          child: _FullHeightSheetShell(
            child: const SQLiteExplorerBottomSheet(),
          ),
        );
      },
    );
  }

  @override
  State<SQLiteExplorerBottomSheet> createState() =>
      _SQLiteExplorerBottomSheetState();
}


class _FullHeightSheetShell extends StatelessWidget {
  final Widget child;
  const _FullHeightSheetShell({required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    return Align(
      alignment: Alignment.topCenter,
      child: Material(
        color: Theme.of(context).canvasColor,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: size.width,
          height: size.height, 
          
          child: SafeArea(
            top: false,
            bottom: true,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _SQLiteExplorerBottomSheetState
    extends State<SQLiteExplorerBottomSheet> {
  late Future<_DbScanResult> _scanFuture;

  
  String? _selectedDbPath; 
  String? _selectedTable; 
  _TableMeta? _selectedTableMeta; 

  @override
  void initState() {
    super.initState();
    _scanFuture = _scanDatabases();
  }

  

  
  static final RegExp _dbExtPattern =
  RegExp(r'\.(db|sqlite|sqlite3|db3)$', caseSensitive: false);

  
  bool _isSidecar(String nameLower) {
    return nameLower.endsWith('-journal') ||
        nameLower.endsWith('-wal') ||
        nameLower.endsWith('-shm');
  }

  bool _hasDbLikeExt(String nameLower) => _dbExtPattern.hasMatch(nameLower);

  
  Future<bool> _isSQLiteFile(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      
      final raf = await f.open();
      try {
        final len = await raf.length();
        if (len < 16) return false;
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
        for (var i = 0; i < magic.length; i++) {
          if (bytes[i] != magic[i]) return false;
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
    final dir = Directory(dbDir);
    if (!await dir.exists()) {
      return _DbScanResult(dbDir, []);
    }

    final entities = await dir.list().toList();
    final dbFiles = <_DbFile>[];

    for (final e in entities) {
      if (e is! File) continue;
      final nameLower = p.basename(e.path).toLowerCase();

      
      if (_isSidecar(nameLower)) continue;

      
      if (!_hasDbLikeExt(nameLower)) continue;

      
      if (!await _isSQLiteFile(e.path)) continue;

      final size = await e.length();
      dbFiles.add(
        _DbFile(
          path: e.path,
          name: p.basename(e.path),
          size: size,
        ),
      );
    }

    
    dbFiles.sort((a, b) => a.name.compareTo(b.name));
    return _DbScanResult(dbDir, dbFiles);
  }

  Future<List<_TableMeta>> _loadTables(String dbPath) async {
    
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false, 
    );
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master "
            "WHERE type='table' "
            "AND name NOT LIKE 'sqlite_%' "
            "AND name != 'android_metadata' "
            "ORDER BY name",
      );

      final metas = <_TableMeta>[];
      for (final row in tables) {
        final name = (row['name'] ?? '') as String;
        if (name.isEmpty) continue;

        
        int count = 0;
        try {
          final c = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
          if (c.isNotEmpty) {
            final v = c.first['c'];
            if (v is int) count = v;
            if (v is num) count = v.toInt();
          }
        } catch (_) {
          
        }

        
        final cols = <_ColumnMeta>[];
        try {
          final colRows = await db.rawQuery("PRAGMA table_info('$name')");
          for (final r in colRows) {
            cols.add(
              _ColumnMeta(
                cid: (r['cid'] as int?) ?? 0,
                name: (r['name'] as String?) ?? '',
                type: (r['type'] as String?) ?? '',
                notnull: ((r['notnull'] as int?) ?? 0) == 1,
                dflt: r['dflt_value']?.toString(),
                pk: ((r['pk'] as int?) ?? 0) == 1,
              ),
            );
          }
        } catch (_) {}

        metas.add(
          _TableMeta(
            name: name,
            rowCount: count,
            columns: cols,
          ),
        );
      }
      return metas;
    } finally {
      await db.close();
    }
  }

  Future<List<Map<String, Object?>>> _loadPreviewRows(
      String dbPath,
      String table, {
        int limit = 100,
      }) async {
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false, 
    );
    try {
      return await db.rawQuery('SELECT * FROM "$table" LIMIT $limit');
    } finally {
      await db.close();
    }
  }

  

  Future<void> _refreshScan() async {
    setState(() {
      _scanFuture = _scanDatabases();
    });
  }

  Future<void> _confirmAndDeleteDb(String dbPath) async {
    final fileName = p.basename(dbPath);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('DB 삭제'),
        content: Text(
          '정말로 "$fileName" 파일을 삭제할까요?\n'
              '연결된 -wal/-shm/-journal 파일도 함께 제거됩니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final result = await _deleteDbFiles(dbPath);

    if (result.errorMessage != null) {
      _showSnack('삭제 실패: ${result.errorMessage}');
    } else {
      _showSnack('삭제 완료: ${p.basename(dbPath)}');
      
      if (_selectedDbPath == dbPath) {
        setState(() {
          _selectedDbPath = null;
          _selectedTable = null;
          _selectedTableMeta = null;
        });
      }
      await _refreshScan();
    }
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  
  
  
  Future<_DeleteResult> _deleteDbFiles(String dbPath) async {
    final dirPath = p.dirname(dbPath);
    final baseName = p.basename(dbPath);
    final baseLower = baseName.toLowerCase();

    try {
      
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}

      
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        final regJournalChain = RegExp(
            '^${RegExp.escape(baseLower)}(?:-journal)+\$'); 
        for (final ent in entities) {
          if (ent is! File) continue;
          final nameLower = p.basename(ent.path).toLowerCase();
          final bool isTarget = nameLower == baseLower ||
              nameLower == '$baseLower-wal' ||
              nameLower == '$baseLower-shm' ||
              regJournalChain.hasMatch(nameLower);

          if (isTarget) {
            try {
              await ent.delete();
            } catch (_) {
              
            }
          }
        }
      }

      
      final baseExists = await File(dbPath).exists();
      if (baseExists) {
        return const _DeleteResult(
          errorMessage:
          '파일이 사용 중일 수 있습니다(다른 핸들이 열려 있음). 앱을 재실행 후 다시 시도하세요.',
        );
      }
      return const _DeleteResult();
    } catch (e) {
      return _DeleteResult(errorMessage: e.toString());
    }
  }

  
  

  
  
  
  
  
  Object? _parseValue(String input) {
    final v = input.trim();
    if (v.isEmpty) return ''; 

    final lower = v.toLowerCase();
    if (lower == 'null') return null;
    if (lower == 'true') return true;
    if (lower == 'false') return false;

    final asInt = int.tryParse(v);
    if (asInt != null) return asInt;

    final asDouble = double.tryParse(v);
    if (asDouble != null) return asDouble;

    return v;
  }

  
  Future<void> _insertRow() async {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    final meta = _selectedTableMeta;
    if (dbPath == null || table == null || meta == null) {
      _showSnack('테이블 정보를 찾을 수 없습니다. 다시 시도해 주세요.');
      return;
    }

    final controllers = <String, TextEditingController>{};
    for (final col in meta.columns) {
      controllers[col.name] = TextEditingController();
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('새 행 추가\n$table'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: meta.columns
                  .map(
                    (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controllers[c.name],
                    decoration: InputDecoration(
                      labelText:
                      '${c.name} (${c.type.isEmpty ? 'TEXT' : c.type}${c.pk ? ', PK' : ''})',
                      helperText: c.pk
                          ? 'PK가 AUTOINCREMENT인 경우 비워두면 자동 생성됩니다.'
                          : null,
                    ),
                  ),
                ),
              )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('추가'),
          ),
        ],
      ),
    );

    if (ok != true) {
      for (final c in controllers.values) {
        c.dispose();
      }
    } else {
      final values = <String, Object?>{};
      for (final col in meta.columns) {
        final text = controllers[col.name]!.text.trim();
        if (text.isEmpty) continue; 
        values[col.name] = _parseValue(text);
      }
      for (final c in controllers.values) {
        c.dispose();
      }

      try {
        final db = await openDatabase(
          dbPath,
          readOnly: false,
          singleInstance: false,
        );
        try {
          await db.insert(table, values);
          _showSnack('새 행이 추가되었습니다.');
          setState(() {}); 
        } finally {
          await db.close();
        }
      } catch (e) {
        _showSnack('삽입 실패: $e');
      }
    }
  }

  
  
  
  
  Future<void> _editRow(Map<String, Object?> row) async {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    final meta = _selectedTableMeta;
    if (dbPath == null || table == null || meta == null) {
      _showSnack('편집 컨텍스트를 찾을 수 없습니다. 다시 시도해 주세요.');
      return;
    }

    final pkCols = meta.columns.where((c) => c.pk).toList();
    if (pkCols.isEmpty) {
      _showSnack('PK가 없는 테이블은 편집을 지원하지 않습니다.');
      return;
    }

    final controllers = <String, TextEditingController>{};
    for (final col in meta.columns) {
      controllers[col.name] = TextEditingController(
        text: row[col.name]?.toString() ?? '',
      );
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('행 편집\n$table'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: meta.columns
                  .map(
                    (c) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextField(
                    controller: controllers[c.name],
                    decoration: InputDecoration(
                      labelText:
                      '${c.name} (${c.type.isEmpty ? 'TEXT' : c.type}${c.pk ? ', PK' : ''})',
                    ),
                  ),
                ),
              )
                  .toList(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('저장'),
          ),
        ],
      ),
    );

    if (ok != true) {
      for (final c in controllers.values) {
        c.dispose();
      }
      return;
    }

    final newValues = <String, Object?>{};
    for (final col in meta.columns) {
      final text = controllers[col.name]!.text;
      newValues[col.name] = _parseValue(text);
    }
    for (final c in controllers.values) {
      c.dispose();
    }

    final where = pkCols.map((c) => '"${c.name}" = ?').join(' AND ');
    final whereArgs = pkCols.map((c) => row[c.name]).toList();

    try {
      final db = await openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      );
      try {
        final updated = await db.update(
          table,
          newValues,
          where: where,
          whereArgs: whereArgs,
        );
        if (updated == 0) {
          _showSnack('업데이트할 행을 찾지 못했습니다.');
        } else {
          _showSnack('행이 업데이트되었습니다.');
          setState(() {}); 
        }
      } finally {
        await db.close();
      }
    } catch (e) {
      _showSnack('업데이트 실패: $e');
    }
  }

  
  Future<void> _confirmDeleteRow(Map<String, Object?> row) async {
    final meta = _selectedTableMeta;
    final table = _selectedTable;
    if (meta == null || table == null) {
      _showSnack('삭제 컨텍스트를 찾을 수 없습니다.');
      return;
    }

    final pkCols = meta.columns.where((c) => c.pk).toList();
    String detail;
    if (pkCols.isEmpty) {
      detail =
      '이 테이블에는 PK가 정의되어 있지 않습니다.\n' '정말 이 행을 삭제할까요?';
    } else {
      final pkText = pkCols
          .map((c) => '${c.name} = ${row[c.name]}')
          .join(', ');
      detail = '다음 조건의 행을 삭제합니다.\n$pkText';
    }

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('행 삭제\n$table'),
        content: Text(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('취소'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _deleteRow(row);
    }
  }

  
  
  
  
  Future<void> _deleteRow(Map<String, Object?> row) async {
    final dbPath = _selectedDbPath;
    final table = _selectedTable;
    final meta = _selectedTableMeta;
    if (dbPath == null || table == null || meta == null) {
      _showSnack('삭제 컨텍스트를 찾을 수 없습니다. 다시 시도해 주세요.');
      return;
    }

    final pkCols = meta.columns.where((c) => c.pk).toList();
    if (pkCols.isEmpty) {
      _showSnack('PK가 없는 테이블은 행 삭제를 지원하지 않습니다.');
      return;
    }

    final where = pkCols.map((c) => '"${c.name}" = ?').join(' AND ');
    final whereArgs = pkCols.map((c) => row[c.name]).toList();

    try {
      final db = await openDatabase(
        dbPath,
        readOnly: false,
        singleInstance: false,
      );
      try {
        final deleted = await db.delete(
          table,
          where: where,
          whereArgs: whereArgs,
        );
        if (deleted == 0) {
          _showSnack('삭제할 행을 찾지 못했습니다.');
        } else {
          _showSnack('행이 삭제되었습니다.');
          setState(() {}); 
        }
      } finally {
        await db.close();
      }
    } catch (e) {
      _showSnack('삭제 실패: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    
    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          children: [
            
            Container(
              decoration: BoxDecoration(
                color: cs.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withOpacity(.08),
                  ),
                ),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
              child: Row(
                children: [
                  if (_selectedDbPath != null)
                    IconButton(
                      tooltip: '뒤로',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        setState(() {
                          if (_selectedTable != null) {
                            _selectedTable = null;
                            _selectedTableMeta = null;
                          } else {
                            _selectedDbPath = null;
                            _selectedTable = null;
                            _selectedTableMeta = null;
                          }
                        });
                      },
                    )
                  else
                    const SizedBox(width: 48),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _selectedDbPath == null
                          ? 'SQLite 탐색기'
                          : (_selectedTable == null
                          ? '테이블 목록'
                          : '미리보기: $_selectedTable'),
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  
                  if (_selectedDbPath != null) ...[
                    IconButton(
                      tooltip: '이 DB 삭제',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => _confirmAndDeleteDb(_selectedDbPath!),
                    ),
                    IconButton(
                      tooltip: '새로고침',
                      icon: const Icon(Icons.refresh),
                      onPressed: _refreshScan,
                    ),
                  ],

                  IconButton(
                    tooltip: '닫기',
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            
            Expanded(
              child: FutureBuilder<_DbScanResult>(
                future: _scanFuture,
                builder: (context, snap) {
                  if (!snap.hasData) {
                    if (snap.hasError) {
                      return _error('데이터베이스 스캔 실패: ${snap.error}');
                    }
                    return const Center(child: CircularProgressIndicator());
                  }

                  final scan = snap.data!;
                  if (_selectedDbPath == null) {
                    
                    if (scan.files.isEmpty) {
                      
                      return _info(
                        '발견된 SQLite DB 파일이 없습니다.\n'
                        '앱 사용 중 SQLite DB가 생성되면 이 화면에서 바로 내용을 조회할 수 있습니다.',
                      );
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 12,
                      ),
                      itemCount: scan.files.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final f = scan.files[i];
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: Colors.black.withOpacity(.08),
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            leading: const Icon(Icons.storage),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    f.name,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            subtitle: Text(
                              '${_fmtSize(f.size)}\n${f.path}',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            isThreeLine: true,
                            trailing: PopupMenuButton<String>(
                              tooltip: '메뉴',
                              onSelected: (v) {
                                switch (v) {
                                  case 'open':
                                    setState(() {
                                      _selectedDbPath = f.path;
                                      _selectedTable = null;
                                      _selectedTableMeta = null;
                                    });
                                    break;
                                  case 'delete':
                                    _confirmAndDeleteDb(f.path);
                                    break;
                                  case 'refresh':
                                    _refreshScan();
                                    break;
                                }
                              },
                              itemBuilder: (ctx) => const [
                                PopupMenuItem(
                                  value: 'open',
                                  child: ListTile(
                                    leading: Icon(Icons.folder_open),
                                    title: Text('열기'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(Icons.delete_outline),
                                    title: Text('삭제'),
                                  ),
                                ),
                                PopupMenuItem(
                                  value: 'refresh',
                                  child: ListTile(
                                    leading: Icon(Icons.refresh),
                                    title: Text('새로고침'),
                                  ),
                                ),
                              ],
                            ),
                            onTap: () {
                              setState(() {
                                _selectedDbPath = f.path;
                                _selectedTable = null;
                                _selectedTableMeta = null;
                              });
                            },
                          ),
                        );
                      },
                    );
                  }

                  
                  if (_selectedTable == null) {
                    return FutureBuilder<List<_TableMeta>>(
                      future: _loadTables(_selectedDbPath!),
                      builder: (context, tsnap) {
                        if (!tsnap.hasData) {
                          if (tsnap.hasError) {
                            return _error('테이블 로드 실패: ${tsnap.error}');
                          }
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final tables = tsnap.data!;
                        if (tables.isEmpty) {
                          return _info('테이블이 없습니다.');
                        }
                        return ListView.separated(
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 12,
                          ),
                          itemCount: tables.length,
                          separatorBuilder: (_, __) =>
                          const SizedBox(height: 8),
                          itemBuilder: (context, i) {
                            final t = tables[i];
                            return Card(
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                  color: Colors.black.withOpacity(.08),
                                ),
                              ),
                              child: ExpansionTile(
                                tilePadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                ),
                                title: Text(
                                  t.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                subtitle: Text(
                                  'rows: ${t.rowCount} • cols: ${t.columns.length}',
                                ),
                                childrenPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                children: [
                                  
                                  SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: DataTable(
                                      columns: const [
                                        DataColumn(label: Text('cid')),
                                        DataColumn(label: Text('name')),
                                        DataColumn(label: Text('type')),
                                        DataColumn(label: Text('notnull')),
                                        DataColumn(label: Text('pk')),
                                      ],
                                      rows: t.columns
                                          .map(
                                            (c) => DataRow(
                                          cells: [
                                            DataCell(Text('${c.cid}')),
                                            DataCell(Text(c.name)),
                                            DataCell(Text(c.type)),
                                            DataCell(
                                              Text(
                                                c.notnull ? 'Y' : '',
                                              ),
                                            ),
                                            DataCell(
                                              Text(c.pk ? 'Y' : ''),
                                            ),
                                          ],
                                        ),
                                      )
                                          .toList(),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: FilledButton.icon(
                                      onPressed: () {
                                        setState(() {
                                          _selectedTable = t.name;
                                          _selectedTableMeta = t;
                                        });
                                      },
                                      icon:
                                      const Icon(Icons.table_rows_rounded),
                                      label: const Text('상위 100행 미리보기'),
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    );
                  } else {
                    
                    return FutureBuilder<List<Map<String, Object?>>>(
                      future: _loadPreviewRows(
                        _selectedDbPath!,
                        _selectedTable!,
                        limit: 100,
                      ),
                      builder: (context, rsnap) {
                        if (!rsnap.hasData) {
                          if (rsnap.hasError) {
                            return _error('행 로드 실패: ${rsnap.error}');
                          }
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        final rows = rsnap.data!;
                        final meta = _selectedTableMeta;

                        if (rows.isEmpty) {
                          final cols = meta?.columns
                              .map((c) => c.name)
                              .toList(growable: false) ??
                              const <String>[];
                          return Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        '$_selectedTable (행 없음)',
                                        style: text.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                    ),
                                    if (cols.isNotEmpty)
                                      FilledButton.icon(
                                        onPressed: _insertRow,
                                        icon: const Icon(Icons.add_rounded),
                                        label: const Text('새 행 추가'),
                                      ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                                _info(
                                  '표시할 행이 없습니다.\n'
                                      '우측 상단의 "새 행 추가" 버튼으로 데이터를 추가해 보세요.',
                                ),
                              ],
                            ),
                          );
                        }

                        final columns = meta != null
                            ? meta.columns
                            .map((c) => c.name)
                            .where(
                              (name) => rows.first.containsKey(name),
                        )
                            .toList(growable: false)
                            : rows.first.keys.toList(growable: false);

                        
                        const double cellWidth = 160.0;
                        const double horizontalPaddingPerRow = 16.0; 
                        final double totalWidth =
                            columns.length * cellWidth +
                                horizontalPaddingPerRow;

                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      '$_selectedTable (상위 ${rows.length}행, 탭하면 편집 / 길게 누르면 삭제)',
                                      style: text.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  FilledButton.icon(
                                    onPressed: _insertRow,
                                    icon: const Icon(Icons.add_rounded),
                                    label: const Text('새 행 추가'),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Expanded(
                                child: Scrollbar(
                                  thumbVisibility: true,
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: SizedBox(
                                      width: totalWidth,
                                      child: ListView.builder(
                                        itemCount:
                                        rows.length + 1, 
                                        shrinkWrap:
                                        true, 
                                        physics:
                                        const ClampingScrollPhysics(),
                                        itemBuilder: (context, index) {
                                          if (index == 0) {
                                            
                                            return Container(
                                              padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 10,
                                              ),
                                              color: Colors.grey.shade200,
                                              child: Row(
                                                children: columns
                                                    .map(
                                                      (c) => SizedBox(
                                                    width: cellWidth,
                                                    child: Text(
                                                      c,
                                                      style:
                                                      const TextStyle(
                                                        fontWeight:
                                                        FontWeight.w700,
                                                      ),
                                                      maxLines: 1,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                    ),
                                                  ),
                                                )
                                                    .toList(),
                                              ),
                                            );
                                          }
                                          final row = rows[index - 1];
                                          return InkWell(
                                            onTap: () => _editRow(row),
                                            onLongPress: () =>
                                                _confirmDeleteRow(row),
                                            child: Container(
                                              padding:
                                              const EdgeInsets.symmetric(
                                                horizontal: 8,
                                                vertical: 8,
                                              ),
                                              decoration: BoxDecoration(
                                                border: Border(
                                                  bottom: BorderSide(
                                                    color: Colors.black
                                                        .withOpacity(.06),
                                                  ),
                                                ),
                                              ),
                                              child: Row(
                                                children: columns
                                                    .map(
                                                      (c) => SizedBox(
                                                    width: cellWidth,
                                                    child: Text(
                                                      '${row[c]}',
                                                      maxLines: 3,
                                                      overflow: TextOverflow
                                                          .ellipsis,
                                                    ),
                                                  ),
                                                )
                                                    .toList(),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    );
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _info(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        msg,
        textAlign: TextAlign.center,
      ),
    ),
  );

  Widget _error(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        msg,
        textAlign: TextAlign.center,
        style: const TextStyle(
          color: Colors.red,
          fontWeight: FontWeight.w600,
        ),
      ),
    ),
  );

  String _fmtSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
    final mb = kb / 1024;
    if (mb < 1024) return '${mb.toStringAsFixed(2)} MB';
    final gb = mb / 1024;
    return '${gb.toStringAsFixed(2)} GB';
  }
}


class _DbScanResult {
  final String dir;
  final List<_DbFile> files;
  _DbScanResult(this.dir, this.files);
}

class _DbFile {
  final String path;
  final String name;
  final int size;
  _DbFile({
    required this.path,
    required this.name,
    required this.size,
  });
}

class _TableMeta {
  final String name;
  final int rowCount;
  final List<_ColumnMeta> columns;
  _TableMeta({
    required this.name,
    required this.rowCount,
    required this.columns,
  });
}

class _ColumnMeta {
  final int cid;
  final String name;
  final String type;
  final bool notnull;
  final String? dflt;
  final bool pk;
  _ColumnMeta({
    required this.cid,
    required this.name,
    required this.type,
    required this.notnull,
    required this.dflt,
    required this.pk,
  });
}

class _DeleteResult {
  final String? errorMessage;
  const _DeleteResult({this.errorMessage});
}
