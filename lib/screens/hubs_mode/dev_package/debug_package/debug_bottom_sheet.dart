// File: lib/screens/stub_package/debug_bottom_sheet.dart
//
// - error 로그만 표시
// - 검색(메시지/시간)
// - 로그 전송(Gmail 첨부) 후 자동 삭제
// - 복사/전체삭제(회전 포함)
// - 리스트 스크롤 성능 및 예외 처리
// - 헤더는 UpdateBottomSheet 스타일(아이콘 + 제목 + 닫기)
// - 헤더 같은 행 우측: 구글 세션 시도 차단 On/Off (SharedPreferences 영구 저장)
// - 소스 선택 칩/액션 버튼은 2줄로 세로 배치 & 중앙 정렬
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

// 파일 내보내기 제거 → share_plus 사용 안 함
// import 'package:share_plus/share_plus.dart';

import 'package:googleapis/gmail/v1.dart' as gmail;

import '../../../../utils/snackbar_helper.dart';
import '../../../../utils/google_auth_session.dart';

import 'debug_api_logger.dart';
import 'debug_database_logger.dart';
import 'debug_local_logger.dart';

enum _LogSource { database, local, api }

class DebugBottomSheet extends StatefulWidget {
  const DebugBottomSheet({super.key});

  @override
  State<DebugBottomSheet> createState() => _DebugBottomSheetState();
}

class _DebugBottomSheetState extends State<DebugBottomSheet> {
  final _searchCtrl = TextEditingController();
  final _listCtrl = ScrollController();

  // 데이터
  List<_LogEntry> _all = [];
  List<_LogEntry> _filtered = [];

  // 로딩 상태/모드
  bool _loading = true;
  bool _fullLoaded = false; // true면 회전 포함 전체 로드 완료

  // 이메일 전송 중 여부
  bool _sendingEmail = false;

  // 현재 소스 (UI 필터용)
  _LogSource _source = _LogSource.database;

  // 구글 세션(로그인) 시도 차단 여부 (SharedPreferences로 영구 저장)
  bool _blockGoogleSessionAttempts = false;
  bool _blockFlagLoaded = false;

  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadGoogleSessionBlockFlag();
    _loadTail();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadGoogleSessionBlockFlag() async {
    try {
      await GoogleAuthSession.instance.warmUpBlockFlag();
      if (!mounted) return;
      setState(() {
        _blockGoogleSessionAttempts = GoogleAuthSession.instance.isSessionBlocked;
        _blockFlagLoaded = true;
      });
    } catch (_) {
      // prefs 로딩 실패 시에도 기본값(OFF)으로 동작
      if (!mounted) return;
      setState(() {
        _blockGoogleSessionAttempts = false;
        _blockFlagLoaded = true;
      });
    }
  }

  Future<void> _setGoogleSessionBlock(bool v) async {
    setState(() {
      _blockGoogleSessionAttempts = v;
    });

    try {
      await GoogleAuthSession.instance.setSessionBlocked(v);
      if (!mounted) return;

      // UX: 상태 변경 안내 (원치 않으면 제거 가능)
      showSuccessSnackbar(
        context,
        v ? '구글 세션 시도 차단: ON' : '구글 세션 시도 차단: OFF',
      );
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '구글 세션 차단 설정 저장 실패: $e');
    }
  }

  // ------- 로딩 -------

  Future<void> _loadTail() async {
    setState(() {
      _loading = true;
      _fullLoaded = false;
    });

    final lines = await _getLogger().readTailLines(
      maxLines: 1500,
      maxBytes: 1024 * 1024,
    );
    _ingestLines(lines);
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _fullLoaded = true;
    });
    final lines = await _getLogger().readAllLinesCombined();
    _ingestLines(lines);
  }

  void _ingestLines(List<String> lines) {
    final entries = lines.map(_parseLine).whereType<_LogEntry>().toList();
    entries.sort((a, b) {
      final at = a.ts?.millisecondsSinceEpoch ?? 0;
      final bt = b.ts?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    setState(() {
      _all = entries;
      _applyFilter();
      _loading = false;
    });
  }

  // ------- 필터 로직 -------

  void _applyFilter() {
    final key = _searchCtrl.text.trim().toLowerCase();

    _filtered = _all.where((e) {
      if (e.level != 'error') return false;

      if (key.isNotEmpty) {
        final s = StringBuffer();
        if (e.message != null) s.write('${e.message} ');
        if (e.ts != null) s.write(_fmt.format(e.ts!));
        if (!s.toString().toLowerCase().contains(key)) return false;
      }

      return true;
    }).toList();
  }

  void _onSearchChanged(String _) => setState(_applyFilter);

  // ------- 기타 액션 -------

  Future<void> _refresh() async {
    if (_fullLoaded) {
      await _loadAll();
    } else {
      await _loadTail();
    }
    if (mounted && _listCtrl.hasClients) {
      _listCtrl.jumpTo(0);
    }
  }

  Future<void> _clear() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      await _getLogger().init();
      await _getLogger().clearLog();

      _searchCtrl.clear();
      _all.clear();
      _filtered.clear();

      await _loadTail();

      if (!mounted) return;
      showSuccessSnackbar(context, '${_labelForSource()} 로그가 삭제되었습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '삭제 실패: $e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _copy() async {
    final text = _filtered.reversed.map((e) => e.original ?? '').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessSnackbar(context, '클립보드에 복사되었습니다.');
  }

  // 🚨 3개 소스(Database/Local/API) 에러 로그를 모아
  // pelicangnc1@gmail.com 으로 .md 첨부 이메일 전송 후, 로그 자동 삭제
  Future<void> _sendLogsByEmail() async {
    if (_sendingEmail) return;

    // 구글 세션 차단(ON) 상태에서는 Gmail API를 사용할 수 없으므로 즉시 차단
    if (_blockGoogleSessionAttempts) {
      if (!mounted) return;
      showSelectedSnackbar(context, '구글 세션 시도 차단(ON) 상태입니다. 전송을 위해 OFF로 변경해 주세요.');
      return;
    }

    setState(() => _sendingEmail = true);

    try {
      // 1) 각 로거에서 전체(회전 포함) 라인 가져와서 error만 필터링
      final dbErrors = await _loadErrorEntries(DebugDatabaseLogger());
      final localErrors = await _loadErrorEntries(DebugLocalLogger());
      final apiErrors = await _loadErrorEntries(DebugApiLogger());

      final totalCount = dbErrors.length + localErrors.length + apiErrors.length;

      if (totalCount == 0) {
        if (!mounted) return;
        showSelectedSnackbar(context, '보낼 에러 로그가 없습니다.');
        return;
      }

      // 2) Markdown 본문 생성
      final now = DateTime.now();
      final subject = 'Pelican 디버그 에러 로그 (${_fmt.format(now)})';
      final filename = 'pelican_logs_${DateFormat('yyyyMMdd_HHmmss').format(now)}.md';

      final sb = StringBuffer()
        ..writeln('# Pelican 디버그 에러 로그')
        ..writeln()
        ..writeln('- 생성 시각: ${_fmt.format(now)}')
        ..writeln('- 총 에러 로그 수: $totalCount')
        ..writeln();

      void writeSection(String title, List<_LogEntry> list) {
        sb
          ..writeln('## $title')
          ..writeln();
        if (list.isEmpty) {
          sb
            ..writeln('_에러 로그가 없습니다._')
            ..writeln();
          return;
        }
        sb
          ..writeln('- 로그 수: ${list.length}')
          ..writeln()
          ..writeln('```json');
        for (final e in list) {
          sb.writeln(e.original ?? e.message ?? '');
        }
        sb
          ..writeln('```')
          ..writeln();
      }

      writeSection('Database', dbErrors);
      writeSection('Local', localErrors);
      writeSection('API', apiErrors);

      final attachmentText = sb.toString();
      final attachmentB64 = base64.encode(utf8.encode(attachmentText));

      // 3) MIME 메시지 구성 (본문 + 첨부)
      final boundary = 'pelican_logs_${now.millisecondsSinceEpoch}';
      const toAddress = 'pelicangnc1@gmail.com';
      const bodyText = '첨부된 Markdown 파일(pelican 에러 로그)을 확인해 주세요.';

      final mime = StringBuffer()
        ..writeln('MIME-Version: 1.0')
        ..writeln('To: $toAddress')
        ..writeln('Subject: $subject')
        ..writeln('Content-Type: multipart/mixed; boundary="$boundary"')
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/plain; charset="utf-8"')
        ..writeln('Content-Transfer-Encoding: 7bit')
        ..writeln()
        ..writeln(bodyText)
        ..writeln()
        ..writeln('--$boundary')
        ..writeln('Content-Type: text/markdown; charset="utf-8"; name="$filename"')
        ..writeln('Content-Disposition: attachment; filename="$filename"')
        ..writeln('Content-Transfer-Encoding: base64')
        ..writeln()
        ..writeln(attachmentB64)
        ..writeln('--$boundary--');

      final raw = base64Url.encode(utf8.encode(mime.toString()));

      // 4) Gmail API로 전송
      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

      // 5) 전송 성공 후, 세 소스(Database/Local/API) 로그 전체 삭제
      try {
        final dbLogger = DebugDatabaseLogger();
        final localLogger = DebugLocalLogger();
        final apiLogger = DebugApiLogger();

        await dbLogger.init();
        await dbLogger.clearLog();

        await localLogger.init();
        await localLogger.clearLog();

        await apiLogger.init();
        await apiLogger.clearLog();

        // 메모리에 들고 있던 리스트도 비우고, 화면 갱신
        _all.clear();
        _filtered.clear();
        if (mounted) {
          setState(() {});
        }
      } catch (e) {
        // 삭제 실패는 치명적이지 않으니 콘솔/로그 정도만
        try {
          await DebugApiLogger().log(
            {
              'tag': 'DebugBottomSheet._sendLogsByEmail',
              'message': '이메일 전송 후 로그 삭제 실패',
              'error': e.toString(),
            },
            level: 'error',
            tags: const ['logs', 'cleanup'],
          );
        } catch (_) {}
      }

      if (!mounted) return;
      showSuccessSnackbar(context, '디버그 로그를 이메일로 전송하고, 로그를 삭제했습니다.');
    } catch (e) {
      if (mounted) {
        showFailedSnackbar(context, '로그 전송 실패: $e');
      }
      try {
        await DebugApiLogger().log(
          {
            'tag': 'DebugBottomSheet._sendLogsByEmail',
            'message': '디버그 로그 이메일 전송 실패',
            'error': e.toString(),
          },
          level: 'error',
          tags: const ['logs', 'email'],
        );
      } catch (_) {
        // 로깅 자체 실패는 조용히 무시
      }
    } finally {
      if (mounted) {
        setState(() => _sendingEmail = false);
      }
    }
  }

  // 특정 로거에서 전체 라인 읽고 error 레벨만 추출
  Future<List<_LogEntry>> _loadErrorEntries(dynamic logger) async {
    try {
      final lines = await logger.readAllLinesCombined();
      final result = <_LogEntry>[];
      for (final line in lines) {
        final entry = _parseLine(line);
        if (entry != null && entry.level == 'error') {
          result.add(entry);
        }
      }
      return result;
    } catch (_) {
      return const <_LogEntry>[];
    }
  }

  // ------- Helpers -------

  dynamic _getLogger() {
    switch (_source) {
      case _LogSource.local:
        return DebugLocalLogger();
      case _LogSource.database:
        return DebugDatabaseLogger();
      case _LogSource.api:
        return DebugApiLogger();
    }
  }

  String _labelForSource() {
    switch (_source) {
      case _LogSource.local:
        return 'Local';
      case _LogSource.database:
        return 'Database';
      case _LogSource.api:
        return 'API';
    }
  }

  // ------- UI -------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: true,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Material(
          color: Colors.white,
          child: SizedBox(
            height: MediaQuery.of(context).size.height,
            child: Column(
              children: [
                const SizedBox(height: 8),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 10),

                // ───── UpdateBottomSheet 스타일 헤더 ─────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.bug_report_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '디버그 로그',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),

                      // ✅ 같은 행 우측: 구글 세션 차단 On/Off
                      Tooltip(
                        message: '에뮬레이터 테스트 시 구글 로그인/세션 시도를 앱 전체에서 차단합니다.',
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '구글 세션 차단',
                              style: (text.labelMedium ?? const TextStyle()).copyWith(
                                color: Colors.black87,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Transform.scale(
                              scale: 0.9,
                              child: Switch.adaptive(
                                value: _blockGoogleSessionAttempts,
                                onChanged: _blockFlagLoaded ? _setGoogleSessionBlock : null,
                              ),
                            ),
                          ],
                        ),
                      ),

                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // ───── 칩 + 액션 버튼 (2줄 · 모두 중앙 정렬) ─────
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // 1줄차: 소스 선택 칩들
                      Center(
                        child: SizedBox(
                          height: 36,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ChoiceChip(
                                  label: const Text('Database'),
                                  selected: _source == _LogSource.database,
                                  onSelected: (_) => setState(() {
                                    _source = _LogSource.database;
                                    _loadTail();
                                  }),
                                ),
                                const SizedBox(width: 6),
                                ChoiceChip(
                                  label: const Text('Local'),
                                  selected: _source == _LogSource.local,
                                  onSelected: (_) => setState(() {
                                    _source = _LogSource.local;
                                    _loadTail();
                                  }),
                                ),
                                const SizedBox(width: 6),
                                ChoiceChip(
                                  label: const Text('API'),
                                  selected: _source == _LogSource.api,
                                  onSelected: (_) => setState(() {
                                    _source = _LogSource.api;
                                    _loadTail();
                                  }),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      // 2줄차: 액션 버튼들
                      Center(
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Tooltip(
                              message: _fullLoaded ? '최근만 보기(빠름)' : '전체 불러오기(회전 포함)',
                              child: TextButton.icon(
                                onPressed: _fullLoaded ? _loadTail : _loadAll,
                                icon: Icon(_fullLoaded ? Icons.bolt : Icons.unfold_more),
                                label: Text(_fullLoaded ? '최근만' : '전체'),
                              ),
                            ),
                            IconButton(
                              tooltip: '새로고침',
                              onPressed: _refresh,
                              icon: const Icon(Icons.refresh),
                            ),
                            IconButton(
                              tooltip: _sendingEmail ? '로그 전송 중...' : '로그 전송',
                              onPressed: _sendingEmail ? null : _sendLogsByEmail,
                              icon: _sendingEmail
                                  ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                                  : const Icon(Icons.send_rounded, color: Colors.blueGrey),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                const Divider(height: 1),

                // 검색 + 복사/삭제
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onChanged: _onSearchChanged,
                          decoration: InputDecoration(
                            hintText: '검색 (메시지/시간)',
                            isDense: true,
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchCtrl.text.isEmpty
                                ? null
                                : IconButton(
                              onPressed: () {
                                _searchCtrl.clear();
                                _onSearchChanged('');
                              },
                              icon: const Icon(Icons.clear_rounded),
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        onPressed: _copy,
                        icon: const Icon(Icons.copy, color: Colors.teal),
                        tooltip: '복사',
                      ),
                      IconButton(
                        onPressed: _clear,
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        tooltip: '전체 삭제',
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1),

                Expanded(
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : Scrollbar(
                    controller: _listCtrl,
                    thumbVisibility: true,
                    child: ListView.builder(
                      controller: _listCtrl,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) => _LogTile(entry: _filtered[i], fmt: _fmt),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // -------- 파서 --------

  _LogEntry? _parseLine(String line) {
    if (line.trim().isEmpty) return null;

    try {
      final m = jsonDecode(line);
      if (m is Map<String, dynamic>) {
        final ts = (m['ts'] is String) ? DateTime.tryParse(m['ts'] as String) : null;
        final level = (m['level'] as String?)?.toLowerCase();
        final msg = (m['message'] as String?) ?? '';
        return _LogEntry(ts: ts, level: level ?? 'error', message: msg, original: line);
      }
    } catch (_) {}

    DateTime? ts;
    String msg = line;
    final idx = line.indexOf(': ');
    if (idx > 0) {
      ts = DateTime.tryParse(line.substring(0, idx));
      msg = line.substring(idx + 2);
    }

    return _LogEntry(ts: ts, level: 'error', message: msg, original: line);
  }
}

class _LogEntry {
  final DateTime? ts;
  final String? level;
  final String? message;
  final String? original;

  _LogEntry({this.ts, this.level, this.message, this.original});
}

class _LogTile extends StatelessWidget {
  final _LogEntry entry;
  final DateFormat fmt;

  const _LogTile({
    required this.entry,
    required this.fmt,
  });

  @override
  Widget build(BuildContext context) {
    final date = entry.ts != null ? fmt.format(entry.ts!) : '';
    final datePart = date.split(' ');
    final d0 = datePart.isNotEmpty ? datePart.first : '';
    final d1 = datePart.length > 1 ? datePart[1] : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error, color: Colors.redAccent, size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                d0,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontFamily: 'monospace',
                ),
              ),
              Text(
                d1,
                style: const TextStyle(
                  fontSize: 11,
                  color: Colors.grey,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.message ?? '',
              style: const TextStyle(
                fontSize: 14,
                color: Colors.redAccent,
                fontFamily: 'monospace',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
