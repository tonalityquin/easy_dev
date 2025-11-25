import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// 개발용 SQLite 탐색 바텀시트.
///
/// - DB 파일 스캔 시 사이드카 파일(-journal/-wal/-shm) 제외
/// - 확장자 화이트리스트(.db/.sqlite/.sqlite3/.db3)만 허용
/// - SQLite 헤더 검증으로 진짜 DB만 노출
/// - readOnly: true 로 열어 DB 생성/변조 방지
/// - 시스템 테이블(android_metadata, sqlite_*) 숨김
/// - time_record / work_time_record 같은 근무 기록 DB도 같이 조회 가능
class SQLiteExplorerBottomSheet extends StatefulWidget {
  const SQLiteExplorerBottomSheet({super.key});

  /// ✅ “진짜” 풀스크린(최상단까지) 모달 바텀시트 헬퍼
  ///
  /// 핵심:
  ///  1) useRootNavigator: true (루트에서 띄워 상위 제약 회피)
  ///  2) useSafeArea: false (상단 패딩 제거)
  ///  3) constraints: 장치 전체 크기로 강제(min/max)
  ///  4) 로컬 Theme으로 bottomSheetTheme.constraints/shape/background 무력화
  ///  5) 외곽 쉘에서 직접 Material/라운딩/클리핑 처리
  static Future<T?> showFullScreen<T>(BuildContext context) {
    final media = MediaQuery.of(context);
    final size = media.size;

    return showModalBottomSheet<T>(
      context: context,
      useRootNavigator: true, // ⬅️ 루트 네비게이터에 붙여 중첩 시트 제약 회피
      isScrollControlled: true,
      useSafeArea: false, // ⬅️ 상단 세이프에어리어 제거(최상단까지)
      showDragHandle: false, // 상단 여백 유발 방지
      backgroundColor: Colors.transparent, // 배경/모양은 내부에서 처리
      // 전역 테마 제약보다 강한 '타이트' 제약으로 전체 높이 강제
      constraints: BoxConstraints(
        minWidth: size.width,
        maxWidth: size.width,
        minHeight: size.height,
        maxHeight: size.height,
      ),
      builder: (ctx) {
        // ⬇️ 로컬 테마로 BottomSheetTheme의 전역 제약/모양/배경 무력화
        final base = Theme.of(context);
        final local = base.copyWith(
          bottomSheetTheme: const BottomSheetThemeData(
            constraints: BoxConstraints(), // 전역 constraints 캡 제거
            backgroundColor: Colors.transparent, // 배경은 우리가 처리
            shape: RoundedRectangleBorder(), // 모양도 내부에서 처리
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

/// 모달의 외곽 배경/라운딩/클리핑을 책임지는 쉘
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
          height: size.height, // ⬅️ 장치 전체 높이 강제
          // 상단은 붙이고, 하단 제스처 영역만 보호
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

  // 네비게이션 스택(시트 내부)
  String? _selectedDbPath; // null이면 DB 목록, 있으면 해당 DB의 테이블 목록
  String? _selectedTable; // null이면 테이블 목록, 있으면 해당 테이블의 로우 미리보기

  @override
  void initState() {
    super.initState();
    _scanFuture = _scanDatabases();
  }

  // ───────────────────────── 파일 스캔/검증 헬퍼 ─────────────────────────

  // 확장자 화이트리스트
  static final RegExp _dbExtPattern =
  RegExp(r'\.(db|sqlite|sqlite3|db3)$', caseSensitive: false);

  // 사이드카 파일(-journal/-wal/-shm) 여부
  bool _isSidecar(String nameLower) {
    return nameLower.endsWith('-journal') ||
        nameLower.endsWith('-wal') ||
        nameLower.endsWith('-shm');
  }

  bool _hasDbLikeExt(String nameLower) => _dbExtPattern.hasMatch(nameLower);

  /// SQLite 파일 매직 헤더 검사: 'SQLite format 3\0'
  Future<bool> _isSQLiteFile(String path) async {
    try {
      final f = File(path);
      if (!await f.exists()) return false;
      // SQLite 헤더는 최소 16바이트를 가짐
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
          0x00, // 'SQLite format 3\0'
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

      // 1) 사이드카 제외
      if (_isSidecar(nameLower)) continue;

      // 2) 확장자 필터(화이트리스트)
      if (!_hasDbLikeExt(nameLower)) continue;

      // 3) SQLite 헤더 검사(진짜 DB만)
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

    // 기본 정렬: 이름
    dbFiles.sort((a, b) => a.name.compareTo(b.name));
    return _DbScanResult(dbDir, dbFiles);
  }

  Future<List<_TableMeta>> _loadTables(String dbPath) async {
    // 읽기 전용 + 전역 DB와 분리된 인스턴스(중요)
    final db = await openDatabase(
      dbPath,
      readOnly: true,
      singleInstance: false, // ✅ 전역 DB 인스턴스와 분리
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
      singleInstance: false, // ✅ 전역 DB와 분리
    );
    try {
      return await db.rawQuery('SELECT * FROM "$table" LIMIT $limit');
    } finally {
      await db.close();
    }
  }

  // ───────────────────────── 삭제/새로고침 ─────────────────────────

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
      // 선택 상태 초기화 및 새로고침
      if (_selectedDbPath == dbPath) {
        setState(() {
          _selectedDbPath = null;
          _selectedTable = null;
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

  /// 실제 파일 삭제 처리
  /// - sqflite의 deleteDatabase(path) 시도
  /// - 같은 디렉토리에서 [basename], [basename]-wal, [basename]-shm, [basename]-journal(+반복) 매칭 후 모두 삭제
  Future<_DeleteResult> _deleteDbFiles(String dbPath) async {
    final dirPath = p.dirname(dbPath);
    final baseName = p.basename(dbPath);
    final baseLower = baseName.toLowerCase();

    try {
      // 1) sqflite helper
      try {
        await deleteDatabase(dbPath);
      } catch (_) {}

      // 2) 사이드카/저널 등 추가 정리
      final dir = Directory(dirPath);
      if (await dir.exists()) {
        final entities = await dir.list().toList();
        final regJournalChain =
        RegExp('^${RegExp.escape(baseLower)}(?:-journal)+\$'); // -journal, -journal-journal ...
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
              // 계속 시도는 하되 마지막에 메시지
            }
          }
        }
      }

      // 3) 최종 확인
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

  // time_record / work_time_record 같은 근무 기록 DB 식별자
  bool _isWorkTimeDbName(String name) {
    final lower = name.toLowerCase();
    return lower.contains('time_record') || lower.contains('work_time');
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final keyboard = MediaQuery.of(context).viewInsets.bottom;

    // 상단은 붙이고, 하단만 보호(제스처 네비) + 키보드 인셋 반영
    return SafeArea(
      top: false,
      bottom: true,
      child: Padding(
        padding: EdgeInsets.only(bottom: keyboard),
        child: Column(
          children: [
            // Header
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
                      style: text.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),

                  // ✅ 상세 화면에서는 바로 삭제/새로고침 버튼 제공
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
                      // ⬇️ 오프라인 로그인 언급 제거, time_record DB 안내로 변경
                      return _info(
                        '발견된 SQLite DB 파일이 없습니다.\n'
                            '앱을 어느 정도 사용하면 근무 기록용 DB(예: work_time_record.db)가 '
                            '자동으로 생성되며, 이 화면에서 바로 내용을 조회할 수 있습니다.',
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
                        final isWorkDb = _isWorkTimeDbName(f.name);
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
                                if (isWorkDb) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                      cs.primaryContainer.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(99),
                                    ),
                                    child: Text(
                                      '근무 기록 DB',
                                      style: TextStyle(
                                        fontSize: 10,
                                        color: cs.onPrimaryContainer,
                                      ),
                                    ),
                                  ),
                                ],
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
                                        setState(
                                              () => _selectedTable = t.name,
                                        );
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
                        if (rows.isEmpty) {
                          return _info('표시할 행이 없습니다.');
                        }
                        final columns = rows.first.keys.toList();

                        // ✅ 패딩(좌우 8px씩)까지 고려한 총 폭 계산으로 overflow 방지
                        const double cellWidth = 160.0;
                        const double horizontalPaddingPerRow = 16.0; // 8 + 8
                        final double totalWidth =
                            columns.length * cellWidth +
                                horizontalPaddingPerRow;

                        return Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                '$_selectedTable (상위 ${rows.length}행)',
                                style: text.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
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
                                        shrinkWrap:
                                        true, // ✅ 내부 스크롤 레이아웃 안정화
                                        physics:
                                        const ClampingScrollPhysics(),
                                        itemBuilder: (context, index) {
                                          if (index == 0) {
                                            // 헤더
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
                                          return Container(
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

// ──────────────────────────── 모델/유틸 ────────────────────────────
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
