// lib/screens/dev_package/sqlite_explorer_bottom_sheet.dart
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class SQLiteExplorerBottomSheet extends StatefulWidget {
  const SQLiteExplorerBottomSheet({super.key});

  @override
  State<SQLiteExplorerBottomSheet> createState() => _SQLiteExplorerBottomSheetState();
}

class _SQLiteExplorerBottomSheetState extends State<SQLiteExplorerBottomSheet> {
  late Future<_DbScanResult> _scanFuture;

  // 네비게이션 스택(시트 내부)
  String? _selectedDbPath; // null이면 DB 목록, 있으면 해당 DB의 테이블 목록
  String? _selectedTable;  // null이면 테이블 목록, 있으면 해당 테이블의 로우 미리보기

  @override
  void initState() {
    super.initState();
    _scanFuture = _scanDatabases();
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
      if (e is File) {
        final name = p.basename(e.path).toLowerCase();
        // 일반적으로 *.db 이거나 sqlite 내부 파일일 수 있음.
        // 우리 앱에서 만든 offlines.db 등을 우선 노출.
        final isLikelyDb = name.endsWith('.db') || name.contains('offlines');
        if (isLikelyDb) {
          final size = await e.length();
          dbFiles.add(_DbFile(path: e.path, name: p.basename(e.path), size: size));
        }
      }
    }

    // 기본 정렬: 이름
    dbFiles.sort((a, b) => a.name.compareTo(b.name));
    return _DbScanResult(dbDir, dbFiles);
  }

  Future<List<_TableMeta>> _loadTables(String dbPath) async {
    final db = await openDatabase(dbPath);
    try {
      final tables = await db.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      );

      final metas = <_TableMeta>[];
      for (final row in tables) {
        final name = (row['name'] ?? '') as String;
        if (name.isEmpty) continue;

        // row count
        int count = 0;
        try {
          final c = await db.rawQuery('SELECT COUNT(*) AS c FROM "$name"');
          if (c.isNotEmpty) {
            final v = c.first['c'];
            if (v is int) count = v;
            if (v is num) count = v.toInt();
          }
        } catch (_) {
          // 테이블이 크거나 view인 경우 실패할 수 있음 → 0으로 두고 계속
        }

        // columns
        final cols = <_ColumnMeta>[];
        try {
          final colRows = await db.rawQuery("PRAGMA table_info('$name')");
          for (final r in colRows) {
            cols.add(_ColumnMeta(
              cid: (r['cid'] as int?) ?? 0,
              name: (r['name'] as String?) ?? '',
              type: (r['type'] as String?) ?? '',
              notnull: ((r['notnull'] as int?) ?? 0) == 1,
              dflt: r['dflt_value']?.toString(),
              pk: ((r['pk'] as int?) ?? 0) == 1,
            ));
          }
        } catch (_) {}

        metas.add(_TableMeta(name: name, rowCount: count, columns: cols));
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
    final db = await openDatabase(dbPath);
    try {
      return await db.rawQuery('SELECT * FROM "$table" LIMIT $limit');
    } finally {
      await db.close();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Column(
      children: [
        // Header
        Container(
          decoration: BoxDecoration(
            color: cs.surface,
            border: Border(bottom: BorderSide(color: Colors.black.withOpacity(.08))),
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
                      } else {
                        _selectedDbPath = null;
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
                  style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
              IconButton(
                tooltip: '닫기',
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),

        // Body
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
                // DB 파일 목록
                if (scan.files.isEmpty) {
                  return _info('발견된 SQLite DB 파일이 없습니다.\n오프라인 로그인 후 offlines.db가 생성됩니다.');
                }
                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                  itemCount: scan.files.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final f = scan.files[i];
                    return Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                        side: BorderSide(color: Colors.black.withOpacity(.08)),
                      ),
                      child: ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                        leading: const Icon(Icons.storage),
                        title: Text(f.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${_fmtSize(f.size)}\n${f.path}',
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        isThreeLine: true,
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          setState(() {
                            _selectedDbPath = f.path;
                            _selectedTable = null;
                          });
                        },
                      ),
                    );
                  },
                );
              }

              // 선택된 DB → 테이블 목록 or 테이블 미리보기
              if (_selectedTable == null) {
                return FutureBuilder<List<_TableMeta>>(
                  future: _loadTables(_selectedDbPath!),
                  builder: (context, tsnap) {
                    if (!tsnap.hasData) {
                      if (tsnap.hasError) {
                        return _error('테이블 로드 실패: ${tsnap.error}');
                      }
                      return const Center(child: CircularProgressIndicator());
                    }
                    final tables = tsnap.data!;
                    if (tables.isEmpty) {
                      return _info('테이블이 없습니다.');
                    }
                    return ListView.separated(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
                      itemCount: tables.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, i) {
                        final t = tables[i];
                        return Card(
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(color: Colors.black.withOpacity(.08)),
                          ),
                          child: ExpansionTile(
                            tilePadding: const EdgeInsets.symmetric(horizontal: 16),
                            title: Text(t.name,
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('rows: ${t.rowCount} • cols: ${t.columns.length}'),
                            childrenPadding:
                            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            children: [
                              // 컬럼 정보
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
                                        DataCell(Text(c.notnull ? 'Y' : '')),
                                        DataCell(Text(c.pk ? 'Y' : '')),
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
                                    setState(() => _selectedTable = t.name);
                                  },
                                  icon: const Icon(Icons.table_rows),
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
                // 테이블 미리보기
                return FutureBuilder<List<Map<String, Object?>>>(
                  future: _loadPreviewRows(_selectedDbPath!, _selectedTable!, limit: 100),
                  builder: (context, rsnap) {
                    if (!rsnap.hasData) {
                      if (rsnap.hasError) {
                        return _error('행 로드 실패: ${rsnap.error}');
                      }
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = rsnap.data!;
                    if (rows.isEmpty) {
                      return _info('표시할 행이 없습니다.');
                    }
                    final columns = rows.first.keys.toList();

                    // ✅ 패딩(좌우 8px씩)까지 고려한 총 폭 계산으로 overflow 방지
                    const double cellWidth = 160.0;
                    const double horizontalPaddingPerRow = 16.0; // 8 + 8
                    final double totalWidth =
                        columns.length * cellWidth + horizontalPaddingPerRow;

                    return Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            '$_selectedTable (상위 ${rows.length}행)',
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700),
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
                                    itemCount: rows.length + 1, // 헤더 + 데이터
                                    shrinkWrap: true, // ✅ 내부 스크롤 레이아웃 안정화
                                    physics: const ClampingScrollPhysics(),
                                    itemBuilder: (context, index) {
                                      if (index == 0) {
                                        // 헤더
                                        return Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 8, vertical: 10),
                                          color: Colors.grey.shade200,
                                          child: Row(
                                            children: columns
                                                .map(
                                                  (c) => SizedBox(
                                                width: cellWidth,
                                                child: Text(
                                                  c,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            )
                                                .toList(),
                                          ),
                                        );
                                      }
                                      final row = rows[index - 1];
                                      return Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 8, vertical: 8),
                                        decoration: BoxDecoration(
                                          border: Border(
                                            bottom: BorderSide(
                                                color: Colors.black.withOpacity(.06)),
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
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          )
                                              .toList(),
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
    );
  }

  Widget _info(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(msg, textAlign: TextAlign.center),
    ),
  );

  Widget _error(String msg) => Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(msg,
          textAlign: TextAlign.center,
          style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
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

// ──────────────────────────── 모델들 ────────────────────────────
class _DbScanResult {
  final String dir;
  final List<_DbFile> files;
  _DbScanResult(this.dir, this.files);
}

class _DbFile {
  final String path;
  final String name;
  final int size;
  _DbFile({required this.path, required this.name, required this.size});
}

class _TableMeta {
  final String name;
  final int rowCount;
  final List<_ColumnMeta> columns;
  _TableMeta({required this.name, required this.rowCount, required this.columns});
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
