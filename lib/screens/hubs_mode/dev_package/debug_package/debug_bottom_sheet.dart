import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:googleapis/gmail/v1.dart' as gmail;
import 'package:intl/intl.dart';

import '../../../../utils/google_auth_session.dart';
import '../../../../utils/snackbar_helper.dart';

import 'debug_action_recorder.dart';
import 'debug_api_logger.dart';

enum _Pane { api, trace }

enum _MenuAction {
  toggleGoogleBlock,
  openAdvancedInfo,
}

///
/// DebugBottomSheet (단일 창)
/// - (API) error 로그 뷰어 + 검색 + 태그(tags) 기반 "API 디버그 선택" + 이메일 전송 후 자동 삭제 + 복사/전체삭제
/// - (Trace) 사용자 버튼(액션) 순서 기록/저장 + 세션 리스트/상세/복사/삭제/전체삭제
///
/// ✅ 변경점:
/// - "최근/전체" 로딩 토글 완전 제거
/// - 대신 API 디버그 선택(= tags 필터) 제공
/// - debug_mode_bottom_sheet.dart 제거 가능 (더 이상 사용/참조하지 않음)
///
class DebugBottomSheet extends StatefulWidget {
  const DebugBottomSheet({super.key});

  @override
  State<DebugBottomSheet> createState() => _DebugBottomSheetState();
}

class _DebugBottomSheetState extends State<DebugBottomSheet> {
  // ─────────────────────────────────────────────────────────────
  // Common UI state
  // ─────────────────────────────────────────────────────────────
  _Pane _pane = _Pane.api;

  // Google session block flag (persisted)
  bool _blockGoogleSessionAttempts = false;
  bool _blockFlagLoaded = false;

  // ─────────────────────────────────────────────────────────────
  // API logger states
  // ─────────────────────────────────────────────────────────────
  final _searchCtrl = TextEditingController();
  final _listCtrl = ScrollController();

  bool _loading = true;
  bool _sendingEmail = false;

  List<_LogEntry> _allEntries = <_LogEntry>[];
  List<_LogEntry> _filtered = <_LogEntry>[];

  // "API 디버그 선택" (tags 필터)
  static const String _tagAll = '__ALL__';
  static const String _tagUntagged = '__UNTAGGED__';

  String _selectedTag = _tagAll;
  List<String> _availableTags = <String>[];

  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  // ─────────────────────────────────────────────────────────────
  // Trace(states): user action recorder
  // ─────────────────────────────────────────────────────────────
  final _traceTitleCtrl = TextEditingController();
  bool _traceLoading = true;
  bool _traceBusy = false;
  List<DebugActionSession> _traceSessions = <DebugActionSession>[];

  DebugActionRecorder get _rec => DebugActionRecorder.instance;

  late final VoidCallback _traceTickListener;

  @override
  void initState() {
    super.initState();

    _searchCtrl.addListener(_onSearchChanged);

    _loadGoogleSessionBlockFlag();
    _loadApiLogs(); // ✅ "최근/전체" 제거 → 항상 동일 로딩(회전 포함)

    // trace init
    _traceTickListener = () {
      if (!mounted) return;
      // 기록 중 변화(steps 증가 등)를 즉시 반영
      setState(() {});
    };
    _rec.tick.addListener(_traceTickListener);
    _initTrace();
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _listCtrl.dispose();
    _traceTitleCtrl.dispose();
    _rec.tick.removeListener(_traceTickListener);
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────
  // Google session block flag
  // ─────────────────────────────────────────────────────────────

  Future<void> _loadGoogleSessionBlockFlag() async {
    try {
      await GoogleAuthSession.instance.warmUpBlockFlag();
      if (!mounted) return;
      setState(() {
        _blockGoogleSessionAttempts = GoogleAuthSession.instance.isSessionBlocked;
        _blockFlagLoaded = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _blockGoogleSessionAttempts = false;
        _blockFlagLoaded = true;
      });
    }
  }

  Future<void> _setGoogleSessionBlock(bool v) async {
    setState(() => _blockGoogleSessionAttempts = v);
    try {
      await GoogleAuthSession.instance.setSessionBlocked(v);
      if (!mounted) return;
      showSuccessSnackbar(context, v ? '구글 세션 차단: ON' : '구글 세션 차단: OFF');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '구글 세션 차단 저장 실패: $e');
    }
  }

  // ─────────────────────────────────────────────────────────────
  // API logger: load/parse/filter
  // ─────────────────────────────────────────────────────────────

  Future<void> _loadApiLogs() async {
    setState(() {
      _loading = true;
    });

    try {
      final logger = DebugApiLogger();

      // ✅ "최근/전체" 토글 제거에 따라, 기본 정책을 회전 포함 전체 로드로 고정
      final lines = await logger.readAllLinesCombined();

      final entries = <_LogEntry>[];
      for (final line in lines) {
        final e = _parseLine(line);
        if (e != null) entries.add(e);
      }

      // 최신순 정렬
      entries.sort((a, b) {
        final at = a.ts?.millisecondsSinceEpoch ?? 0;
        final bt = b.ts?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      // tags 집계
      final tagSet = <String>{};
      var hasUntagged = false;
      for (final e in entries) {
        if (e.tags.isEmpty) {
          hasUntagged = true;
        } else {
          tagSet.addAll(e.tags);
        }
      }

      final tags = tagSet.toList()..sort();

      final available = <String>[_tagAll];
      if (hasUntagged) available.add(_tagUntagged);
      available.addAll(tags);

      // 선택된 태그가 더 이상 없으면 ALL로 fallback
      var selected = _selectedTag;
      if (!available.contains(selected)) {
        selected = _tagAll;
      }

      if (!mounted) return;
      setState(() {
        _allEntries = entries;
        _availableTags = available;
        _selectedTag = selected;
        _applyFilter();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _allEntries = <_LogEntry>[];
        _filtered = <_LogEntry>[];
        _availableTags = <String>[_tagAll];
        _selectedTag = _tagAll;
        _loading = false;
      });
      showFailedSnackbar(context, '로그 로딩 실패: $e');
    }
  }

  _LogEntry? _parseLine(String line) {
    if (line.trim().isEmpty) return null;

    // JSON 라인 우선 파싱
    try {
      final m = jsonDecode(line);
      if (m is Map<String, dynamic>) {
        final ts = (m['ts'] is String) ? DateTime.tryParse(m['ts'] as String) : null;
        final level = (m['level'] as String?)?.toLowerCase();
        final msg = (m['message'] as String?) ?? '';

        final tagsAny = m['tags'];
        final tags = <String>[];
        if (tagsAny is List) {
          for (final x in tagsAny) {
            final t = x?.toString().trim();
            if (t != null && t.isNotEmpty) tags.add(t);
          }
        }

        return _LogEntry(
          ts: ts,
          level: (level ?? 'error').toLowerCase(),
          message: msg,
          original: line,
          tags: tags,
        );
      }
    } catch (_) {
      // ignore
    }

    // fallback
    DateTime? ts;
    String msg = line;
    final idx = line.indexOf(': ');
    if (idx > 0) {
      ts = DateTime.tryParse(line.substring(0, idx));
      msg = line.substring(idx + 2);
    }

    return _LogEntry(
      ts: ts,
      level: 'error',
      message: msg,
      original: line,
      tags: const <String>[],
    );
  }

  void _applyFilter() {
    final key = _searchCtrl.text.trim().toLowerCase();

    // error만 표시
    Iterable<_LogEntry> it = _allEntries.where((e) => (e.level ?? '').toLowerCase() == 'error');

    // ✅ API 디버그 선택: tags 필터
    it = it.where((e) {
      if (_selectedTag == _tagAll) return true;
      if (_selectedTag == _tagUntagged) return e.tags.isEmpty;
      return e.tags.contains(_selectedTag);
    });

    if (key.isNotEmpty) {
      it = it.where((e) {
        final sb = StringBuffer();
        if (e.message != null && e.message!.isNotEmpty) {
          sb.write(e.message);
          sb.write(' ');
        }
        if (e.ts != null) {
          sb.write(_fmt.format(e.ts!));
        }
        return sb.toString().toLowerCase().contains(key);
      });
    }

    _filtered = it.toList(growable: false);
  }

  void _onSearchChanged() {
    if (!mounted) return;
    setState(() => _applyFilter());
  }

  Future<void> _refreshApi() async {
    await _loadApiLogs();
    if (!mounted) return;
    if (_listCtrl.hasClients) {
      try {
        _listCtrl.jumpTo(0);
      } catch (_) {}
    }
  }

  Future<void> _clearApiLogs() async {
    if (!mounted) return;
    setState(() => _loading = true);

    try {
      final logger = DebugApiLogger();
      await logger.init();
      await logger.clearLog();

      _searchCtrl.clear();
      _allEntries = <_LogEntry>[];
      _filtered = <_LogEntry>[];

      await _loadApiLogs();

      if (!mounted) return;
      showSuccessSnackbar(context, 'API 로그가 삭제되었습니다.');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '삭제 실패: $e');
      setState(() => _loading = false);
    }
  }

  Future<void> _copyFilteredApi() async {
    if (_filtered.isEmpty) {
      showSelectedSnackbar(context, '복사할 로그가 없습니다.');
      return;
    }
    final text = _filtered.reversed.map((e) => e.original ?? e.message ?? '').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessSnackbar(context, '클립보드에 복사되었습니다.');
  }

  Future<void> _sendLogsByEmail() async {
    if (_sendingEmail) return;

    if (_blockGoogleSessionAttempts) {
      if (!mounted) return;
      showSelectedSnackbar(context, '구글 세션 차단(ON) 상태입니다. 전송을 위해 OFF로 변경해 주세요.');
      return;
    }

    setState(() => _sendingEmail = true);

    try {
      // ✅ 화면 필터 기준(태그+검색)을 "전체(회전 포함)" 로그에 동일 적용하여 누락 최소화
      final logger = DebugApiLogger();
      final lines = await logger.readAllLinesCombined();

      final entries = <_LogEntry>[];
      for (final line in lines) {
        final e = _parseLine(line);
        if (e != null) entries.add(e);
      }
      entries.sort((a, b) {
        final at = a.ts?.millisecondsSinceEpoch ?? 0;
        final bt = b.ts?.millisecondsSinceEpoch ?? 0;
        return bt.compareTo(at);
      });

      // 동일 필터 적용
      final key = _searchCtrl.text.trim().toLowerCase();
      final filteredToSend = entries.where((e) {
        if ((e.level ?? '').toLowerCase() != 'error') return false;

        if (_selectedTag != _tagAll) {
          if (_selectedTag == _tagUntagged) {
            if (e.tags.isNotEmpty) return false;
          } else {
            if (!e.tags.contains(_selectedTag)) return false;
          }
        }

        if (key.isNotEmpty) {
          final sb = StringBuffer();
          if (e.message != null && e.message!.isNotEmpty) {
            sb.write(e.message);
            sb.write(' ');
          }
          if (e.ts != null) sb.write(_fmt.format(e.ts!));
          if (!sb.toString().toLowerCase().contains(key)) return false;
        }

        return true;
      }).toList(growable: false);

      if (filteredToSend.isEmpty) {
        if (!mounted) return;
        showSelectedSnackbar(context, '보낼 에러 로그가 없습니다.');
        return;
      }

      final now = DateTime.now();
      final subjectTag = _selectedTag == _tagAll
          ? 'ALL'
          : (_selectedTag == _tagUntagged ? 'UNTAGGED' : _selectedTag);
      final subject = 'Pelican API 디버그 에러 로그($subjectTag) (${_fmt.format(now)})';
      final filename = 'pelican_api_logs_${DateFormat('yyyyMMdd_HHmmss').format(now)}.md';

      final sb = StringBuffer()
        ..writeln('# Pelican 디버그 에러 로그 (API)')
        ..writeln()
        ..writeln('- 생성 시각: ${_fmt.format(now)}')
        ..writeln('- 필터(tag): $subjectTag')
        ..writeln('- 검색어: ${_searchCtrl.text.trim().isEmpty ? '-' : _searchCtrl.text.trim()}')
        ..writeln('- 총 에러 로그 수: ${filteredToSend.length}')
        ..writeln()
        ..writeln('```json');

      // 오래된→최신 순으로 넣어 가독성 확보
      for (final e in filteredToSend.reversed) {
        sb.writeln(e.original ?? e.message ?? '');
      }
      sb.writeln('```');

      final attachmentText = sb.toString();
      final attachmentB64 = base64.encode(utf8.encode(attachmentText));

      final boundary = 'pelican_logs_${now.millisecondsSinceEpoch}';
      const toAddress = 'pelicangnc1@gmail.com';
      const bodyText = '첨부된 Markdown 파일(API 에러 로그)을 확인해 주세요.';

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

      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

      // 전송 성공 후 전체 로그 삭제(요구 유지)
      try {
        await logger.init();
        await logger.clearLog();
      } catch (_) {}

      if (!mounted) return;
      showSuccessSnackbar(context, '로그를 이메일로 전송하고, 로그를 삭제했습니다.');
      await _loadApiLogs();
      if (!mounted) return;
      if (_listCtrl.hasClients) {
        try {
          _listCtrl.jumpTo(0);
        } catch (_) {}
      }
    } catch (e) {
      if (mounted) showFailedSnackbar(context, '로그 전송 실패: $e');

      // 전송 실패는 error로 남김(가능한 경우)
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
      } catch (_) {}
    } finally {
      if (mounted) setState(() => _sendingEmail = false);
    }
  }

  Future<void> _showLogDetail(_LogEntry entry) async {
    final cs = Theme.of(context).colorScheme;
    final ts = entry.ts != null ? _fmt.format(entry.ts!) : '-';
    final raw = entry.original ?? entry.message ?? '';

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              heightFactor: 0.62,
              widthFactor: 1,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
                child: Material(
                  color: cs.surface,
                  child: Column(
                    children: [
                      const SizedBox(height: 10),
                      Container(
                        width: 44,
                        height: 5,
                        decoration: BoxDecoration(
                          color: cs.onSurface.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.article_rounded, color: cs.primary),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '로그 상세',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                              ),
                            ),
                            IconButton(
                              tooltip: '복사',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: raw));
                                if (!mounted) return;
                                showSuccessSnackbar(context, '로그 원문이 복사되었습니다.');
                              },
                              icon: const Icon(Icons.copy_rounded),
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
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _InfoChip(icon: Icons.schedule_rounded, label: ts),
                            _InfoChip(icon: Icons.error_outline_rounded, label: 'error'),
                            if (entry.tags.isEmpty)
                              const _InfoChip(icon: Icons.sell_outlined, label: 'untagged')
                            else
                              for (final t in entry.tags) _InfoChip(icon: Icons.sell_outlined, label: t),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(16),
                          child: SelectableText(
                            raw,
                            style: TextStyle(
                              fontFamily: 'monospace',
                              height: 1.25,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ─────────────────────────────────────────────────────────────
  // Trace: init/actions
  // ─────────────────────────────────────────────────────────────

  Future<void> _initTrace() async {
    setState(() => _traceLoading = true);

    try {
      await _rec.init();
      await _reloadTraceSessions();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, 'Trace 초기화 실패: $e');
      setState(() {
        _traceSessions = <DebugActionSession>[];
        _traceLoading = false;
      });
    }
  }

  Future<void> _reloadTraceSessions() async {
    try {
      final sessions = await _rec.readSessions();
      if (!mounted) return;
      setState(() {
        _traceSessions = sessions;
        _traceLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '세션 로딩 실패: $e');
      setState(() {
        _traceSessions = <DebugActionSession>[];
        _traceLoading = false;
      });
    }
  }

  Future<void> _traceStart() async {
    if (_traceBusy) return;
    setState(() => _traceBusy = true);

    try {
      final title = _traceTitleCtrl.text.trim();
      await _rec.start(title: title.isEmpty ? null : title);

      if (!mounted) return;
      showSuccessSnackbar(context, '기록이 시작되었습니다.');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '기록 시작 실패: $e');
    } finally {
      if (mounted) setState(() => _traceBusy = false);
    }
  }

  Future<void> _traceStopAndSave() async {
    if (_traceBusy) return;
    setState(() => _traceBusy = true);

    try {
      final title = _traceTitleCtrl.text.trim();
      final saved = await _rec.stopAndSave(titleOverride: title.isEmpty ? null : title);

      if (!mounted) return;
      if (saved == null) {
        showSelectedSnackbar(context, '저장할 기록이 없습니다(기록 중이 아님).');
      } else {
        showSuccessSnackbar(context, '세션이 저장되었습니다. (${saved.actionCount} steps)');
      }

      _traceTitleCtrl.clear();
      await _reloadTraceSessions();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '저장 실패: $e');
    } finally {
      if (mounted) setState(() => _traceBusy = false);
    }
  }

  Future<void> _traceDiscard() async {
    if (_traceBusy) return;
    setState(() => _traceBusy = true);

    try {
      await _rec.discardCurrent();
      if (!mounted) return;
      showSelectedSnackbar(context, '현재 기록이 삭제(저장 안 함)되었습니다.');
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '삭제 실패: $e');
    } finally {
      if (mounted) setState(() => _traceBusy = false);
    }
  }

  Future<void> _traceCopyCurrent() async {
    final actions = _rec.currentActions;
    if (actions.isEmpty) {
      showSelectedSnackbar(context, '복사할 기록이 없습니다.');
      return;
    }

    final text = _formatTraceSessionText(
      title: _rec.currentTitle,
      startedAt: _rec.currentStartedAt,
      endedAt: null,
      actions: actions,
    );

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessSnackbar(context, '현재 기록이 복사되었습니다.');
  }

  Future<void> _traceCopySession(DebugActionSession s) async {
    final text = _formatTraceSessionText(
      title: s.title,
      startedAt: s.startedAt,
      endedAt: s.endedAt,
      actions: s.actions,
    );

    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    showSuccessSnackbar(context, '세션이 복사되었습니다.');
  }

  Future<void> _traceDeleteSession(DebugActionSession s) async {
    if (_traceBusy) return;
    setState(() => _traceBusy = true);

    try {
      final ok = await _rec.deleteSession(s.id);
      if (!mounted) return;
      if (ok) {
        showSuccessSnackbar(context, '세션이 삭제되었습니다.');
      } else {
        showSelectedSnackbar(context, '삭제할 세션을 찾지 못했습니다.');
      }
      await _reloadTraceSessions();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '세션 삭제 실패: $e');
    } finally {
      if (mounted) setState(() => _traceBusy = false);
    }
  }

  Future<void> _traceClearAll() async {
    if (_traceBusy) return;
    setState(() => _traceBusy = true);

    try {
      await _rec.clearAll();
      if (!mounted) return;
      showSuccessSnackbar(context, '모든 세션이 삭제되었습니다.');
      await _reloadTraceSessions();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '전체 삭제 실패: $e');
    } finally {
      if (mounted) setState(() => _traceBusy = false);
    }
  }

  Future<void> _openTraceSessionDetail(DebugActionSession s) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _TraceSessionDetailBottomSheet(
        session: s,
        onCopy: () => _traceCopySession(s),
      ),
    );
  }

  static String _formatTraceSessionText({
    required String? title,
    required DateTime? startedAt,
    required DateTime? endedAt,
    required List<DebugUserAction> actions,
  }) {
    final sb = StringBuffer()
      ..writeln('# Debug Button Trace')
      ..writeln()
      ..writeln('- title: ${title == null || title.trim().isEmpty ? '-' : title.trim()}')
      ..writeln('- startedAt: ${startedAt == null ? '-' : startedAt.toIso8601String()}')
      ..writeln('- endedAt: ${endedAt == null ? '-' : endedAt.toIso8601String()}')
      ..writeln('- steps: ${actions.length}')
      ..writeln()
      ..writeln('## Steps')
      ..writeln();

    for (int i = 0; i < actions.length; i++) {
      final a = actions[i];
      sb.writeln(
        '${(i + 1).toString().padLeft(3, '0')}. ${a.at.toIso8601String()}  |  ${a.name}'
            '${a.route != null ? '  |  route=${a.route}' : ''}',
      );
      if (a.meta != null && a.meta!.isNotEmpty) {
        sb.writeln('     meta: ${jsonEncode(a.meta)}');
      }
    }
    return sb.toString();
  }

  // ─────────────────────────────────────────────────────────────
  // UI
  // ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.92,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            child: Material(
              color: cs.surface,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 46,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Header
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.bug_report_rounded, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '디버그',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                _pane == _Pane.api
                                    ? 'API 에러 로그(태그 선택) / 전송 / 삭제'
                                    : '사용자 버튼(액션) 순서 기록 / 세션 저장',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),

                        // More menu (google block moved here)
                        PopupMenuButton<_MenuAction>(
                          tooltip: '더보기',
                          onSelected: (action) async {
                            switch (action) {
                              case _MenuAction.toggleGoogleBlock:
                                if (!_blockFlagLoaded) return;
                                await _setGoogleSessionBlock(!_blockGoogleSessionAttempts);
                                break;
                              case _MenuAction.openAdvancedInfo:
                                if (!mounted) return;
                                showSelectedSnackbar(
                                  context,
                                  '고급 설정: 구글 세션 차단(${_blockGoogleSessionAttempts ? "ON" : "OFF"})',
                                );
                                break;
                            }
                          },
                          itemBuilder: (ctx) => <PopupMenuEntry<_MenuAction>>[
                            CheckedPopupMenuItem<_MenuAction>(
                              value: _MenuAction.toggleGoogleBlock,
                              enabled: _blockFlagLoaded,
                              checked: _blockGoogleSessionAttempts,
                              child: const Text('구글 세션 차단'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem<_MenuAction>(
                              value: _MenuAction.openAdvancedInfo,
                              child: Text('고급 설정 상태 보기'),
                            ),
                          ],
                        ),

                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Pane toggle (one window)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _PaneToggle(
                      pane: _pane,
                      onChanged: (p) => setState(() => _pane = p),
                    ),
                  ),

                  const SizedBox(height: 10),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),

                  // Body
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 180),
                      child: _pane == _Pane.api
                          ? _buildApiPane(context, key: const ValueKey('api'))
                          : _buildTracePane(context, key: const ValueKey('trace')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildApiPane(BuildContext context, {required Key key}) {
    final cs = Theme.of(context).colorScheme;

    final totalCount = _filtered.length;
    final newestTs = _filtered.isNotEmpty ? _filtered.first.ts : null;
    final newestLabel = newestTs != null ? _fmt.format(newestTs) : '-';

    return Column(
      key: key,
      children: [
        // Tag selector + refresh
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  value: _selectedTag,
                  isExpanded: true,
                  decoration: InputDecoration(
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withOpacity(0.55),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: const Icon(Icons.sell_outlined),
                    labelText: 'API 디버그 선택(tag)',
                  ),
                  items: _availableTags.map((t) {
                    final label = (t == _tagAll)
                        ? '전체'
                        : (t == _tagUntagged ? '(미지정)' : t);
                    return DropdownMenuItem<String>(
                      value: t,
                      child: Text(label, overflow: TextOverflow.ellipsis),
                    );
                  }).toList(growable: false),
                  onChanged: _loading
                      ? null
                      : (v) {
                    if (v == null) return;
                    setState(() {
                      _selectedTag = v;
                      _applyFilter();
                    });
                  },
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '새로고침',
                onPressed: _loading ? null : _refreshApi,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
          ),
        ),

        // Search + copy
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  textInputAction: TextInputAction.search,
                  decoration: InputDecoration(
                    hintText: '검색 (메시지 또는 시간: yyyy-MM-dd HH:mm:ss)',
                    isDense: true,
                    filled: true,
                    fillColor: cs.surfaceContainerHighest.withOpacity(0.55),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                      tooltip: '검색어 지우기',
                      onPressed: () => _searchCtrl.clear(),
                      icon: const Icon(Icons.clear_rounded),
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filledTonal(
                tooltip: '복사',
                onPressed: (_loading || totalCount == 0) ? null : _copyFilteredApi,
                icon: const Icon(Icons.copy_rounded),
              ),
            ],
          ),
        ),

        // Info + send + clear
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(
            children: [
              _InfoChip(icon: Icons.error_outline_rounded, label: '에러 $totalCount'),
              const SizedBox(width: 8),
              _InfoChip(icon: Icons.schedule_rounded, label: '최신 $newestLabel'),
              const Spacer(),
              IconButton(
                tooltip: _sendingEmail ? '전송 중...' : '이메일로 전송(필터 적용) 후 로그 삭제',
                onPressed: (_loading || _sendingEmail) ? null : _sendLogsByEmail,
                icon: _sendingEmail
                    ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
                    : const Icon(Icons.send_rounded),
              ),
              IconButton(
                tooltip: '전체 삭제',
                onPressed: _loading ? null : _clearApiLogs,
                icon: Icon(Icons.delete_forever_rounded, color: cs.error),
              ),
            ],
          ),
        ),

        Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _buildApiList(context),
        ),
      ],
    );
  }

  Widget _buildApiList(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (_filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 44, color: cs.onSurfaceVariant.withOpacity(0.7)),
              const SizedBox(height: 10),
              Text(
                '표시할 에러 로그가 없습니다.',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                '태그/검색 조건을 확인하거나, 새로고침을 실행하세요.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshApi,
      child: Scrollbar(
        controller: _listCtrl,
        thumbVisibility: true,
        child: ListView.builder(
          controller: _listCtrl,
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          itemCount: _filtered.length,
          cacheExtent: 1200,
          itemBuilder: (ctx, i) {
            final e = _filtered[i];
            return _LogCard(
              entry: e,
              fmt: _fmt,
              onTap: () => _showLogDetail(e),
            );
          },
        ),
      ),
    );
  }

  Widget _buildTracePane(BuildContext context, {required Key key}) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final isRecording = _rec.isRecording;
    final currentCount = _rec.currentActions.length;
    final currentStarted = _rec.currentStartedAt;

    return CustomScrollView(
      key: key,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: _SectionCard(
              title: '버튼(액션) 기록',
              subtitle: '기록 시작 후 앱에서 버튼을 누르면 순서대로 steps가 쌓입니다.',
              trailing: _StatusPill(
                text: isRecording ? 'REC' : 'IDLE',
                color: isRecording ? cs.error : cs.onSurfaceVariant,
              ),
              child: Column(
                children: [
                  TextField(
                    controller: _traceTitleCtrl,
                    enabled: !_traceBusy,
                    decoration: InputDecoration(
                      hintText: '세션 이름(선택)',
                      isDense: true,
                      filled: true,
                      fillColor: cs.surfaceContainerHighest.withOpacity(0.55),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.edit_rounded),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: (_traceBusy || isRecording) ? null : _traceStart,
                          icon: const Icon(Icons.fiber_manual_record_rounded),
                          label: const Text('기록 시작'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_traceBusy || !isRecording) ? null : _traceStopAndSave,
                          icon: const Icon(Icons.save_rounded),
                          label: const Text('중지/저장'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (_traceBusy || !isRecording || currentCount == 0) ? null : _traceCopyCurrent,
                          icon: const Icon(Icons.copy_rounded),
                          label: const Text('현재 기록 복사'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextButton.icon(
                          onPressed: (_traceBusy || !isRecording) ? null : _traceDiscard,
                          icon: const Icon(Icons.delete_sweep_rounded),
                          label: const Text('버리기'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _InfoChip(icon: Icons.format_list_numbered_rounded, label: 'steps $currentCount'),
                      _InfoChip(
                        icon: Icons.schedule_rounded,
                        label: currentStarted == null ? 'start -' : 'start ${_fmt.format(currentStarted)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _CurrentPreview(actions: _rec.currentActions, maxItems: 6),
                ],
              ),
            ),
          ),
        ),

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              children: [
                Text('저장된 세션', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900)),
                const Spacer(),
                TextButton.icon(
                  onPressed: (_traceBusy || _traceLoading) ? null : _traceClearAll,
                  icon: const Icon(Icons.delete_forever_rounded),
                  label: const Text('전체 삭제'),
                ),
              ],
            ),
          ),
        ),

        if (_traceLoading)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_traceSessions.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyState(
              title: '저장된 세션이 없습니다.',
              subtitle: '“기록 시작” 후 버튼을 누르고 “중지/저장”으로 남기세요.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                    (ctx, i) {
                  final s = _traceSessions[i];
                  return _TraceSessionCard(
                    session: s,
                    busy: _traceBusy,
                    onOpen: () => _openTraceSessionDetail(s),
                    onCopy: () => _traceCopySession(s),
                    onDelete: () => _traceDeleteSession(s),
                  );
                },
                childCount: _traceSessions.length,
              ),
            ),
          ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Widgets / models
// ─────────────────────────────────────────────────────────────

class _PaneToggle extends StatelessWidget {
  final _Pane pane;
  final ValueChanged<_Pane> onChanged;

  const _PaneToggle({
    required this.pane,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final selected = <bool>[pane == _Pane.api, pane == _Pane.trace];

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ToggleButtons(
        isSelected: selected,
        onPressed: (idx) {
          if (idx == 0) onChanged(_Pane.api);
          if (idx == 1) onChanged(_Pane.trace);
        },
        borderRadius: BorderRadius.circular(12),
        constraints: const BoxConstraints(minHeight: 40),
        children: const [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.bug_report_rounded, size: 18),
                SizedBox(width: 8),
                Text('API'),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              children: [
                Icon(Icons.route_rounded, size: 18),
                SizedBox(width: 8),
                Text('Trace'),
              ],
            ),
          ),
        ],
        color: cs.onSurfaceVariant,
        selectedColor: cs.onPrimary,
        fillColor: cs.primary,
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _LogEntry {
  final DateTime? ts;
  final String? level;
  final String? message;
  final String? original;
  final List<String> tags;

  _LogEntry({
    required this.ts,
    required this.level,
    required this.message,
    required this.original,
    required this.tags,
  });
}

class _LogCard extends StatelessWidget {
  final _LogEntry entry;
  final DateFormat fmt;
  final VoidCallback onTap;

  const _LogCard({
    required this.entry,
    required this.fmt,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ts = entry.ts != null ? fmt.format(entry.ts!) : '';
    final msg = (entry.message ?? '').trim();

    final tagLabel = entry.tags.isEmpty ? 'untagged' : entry.tags.join(', ');

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 52,
                  decoration: BoxDecoration(
                    color: cs.error,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.error_rounded, color: cs.error, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ts.isEmpty ? '시간 정보 없음' : ts,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        msg.isEmpty ? '(메시지 없음)' : msg,
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.25,
                          color: cs.onSurface,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        tagLabel,
                        style: TextStyle(
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// Trace UI widgets
class _SectionCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget child;
  final Widget? trailing;

  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(title, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
                if (trailing != null) trailing!,
              ],
            ),
            const SizedBox(height: 4),
            Text(subtitle, style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontWeight: FontWeight.w900,
          color: color,
          letterSpacing: 0.4,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _CurrentPreview extends StatelessWidget {
  final List<DebugUserAction> actions;
  final int maxItems;

  const _CurrentPreview({
    required this.actions,
    required this.maxItems,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (actions.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: cs.surface.withOpacity(0.5),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
        ),
        child: Text(
          '현재 기록이 없습니다. 기록 시작 후 앱에서 버튼을 눌러보세요.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }

    final shown = actions.length <= maxItems ? actions : actions.sublist(actions.length - maxItems);
    final startIndex = actions.length - shown.length;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '최근 ${shown.length} step',
            style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
          ),
          const SizedBox(height: 8),
          for (int i = 0; i < shown.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(
                '${(startIndex + i + 1).toString().padLeft(3, '0')}. ${shown[i].name}'
                    '${shown[i].route != null ? '  (route=${shown[i].route})' : ''}',
                style: TextStyle(
                  fontFamily: 'monospace',
                  color: cs.onSurfaceVariant,
                  height: 1.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TraceSessionCard extends StatelessWidget {
  final DebugActionSession session;
  final VoidCallback onOpen;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final bool busy;

  const _TraceSessionCard({
    required this.session,
    required this.onOpen,
    required this.onCopy,
    required this.onDelete,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final title = (session.title == null || session.title!.trim().isEmpty) ? '세션' : session.title!.trim();
    final time = '${session.startedAt.toIso8601String()} → ${session.endedAt.toIso8601String()}';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Ink(
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest.withOpacity(0.35),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 4,
                  height: 44,
                  decoration: BoxDecoration(
                    color: cs.primary,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(width: 10),
                Icon(Icons.bookmark_rounded, color: cs.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(fontWeight: FontWeight.w900, color: cs.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        time,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 11.5,
                          color: cs.onSurfaceVariant,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'steps: ${session.actionCount}  |  duration: ${session.duration.inSeconds}s',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: '복사',
                  onPressed: busy ? null : onCopy,
                  icon: const Icon(Icons.copy_rounded),
                ),
                IconButton(
                  tooltip: '삭제',
                  onPressed: busy ? null : onDelete,
                  icon: Icon(Icons.delete_forever_rounded, color: cs.error),
                ),
                Icon(Icons.chevron_right_rounded, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.inbox_rounded, size: 46, color: cs.onSurfaceVariant.withOpacity(0.7)),
              const SizedBox(height: 10),
              Text(
                title,
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 6),
              Text(
                subtitle,
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TraceSessionDetailBottomSheet extends StatelessWidget {
  final DebugActionSession session;
  final VoidCallback onCopy;

  const _TraceSessionDetailBottomSheet({
    required this.session,
    required this.onCopy,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    final title = (session.title == null || session.title!.trim().isEmpty) ? '세션 상세' : session.title!.trim();

    return SafeArea(
      top: true,
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: 0.72,
          widthFactor: 1,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
            child: Material(
              color: cs.surface,
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: cs.onSurface.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        Icon(Icons.article_rounded, color: cs.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            title,
                            style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: '복사',
                          onPressed: onCopy,
                          icon: const Icon(Icons.copy_rounded),
                        ),
                        IconButton(
                          tooltip: '닫기',
                          onPressed: () => Navigator.of(context).maybePop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                  Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),
                  Expanded(
                    child: ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                      itemCount: session.actions.length,
                      itemBuilder: (ctx, i) {
                        final a = session.actions[i];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Container(
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest.withOpacity(0.35),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${(i + 1).toString().padLeft(3, '0')}. ${a.name}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      color: cs.onSurface,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    a.at.toIso8601String(),
                                    style: TextStyle(
                                      fontFamily: 'monospace',
                                      fontSize: 11.5,
                                      color: cs.onSurfaceVariant,
                                    ),
                                  ),
                                  if (a.route != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      'route: ${a.route}',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                  if (a.meta != null && a.meta!.isNotEmpty) ...[
                                    const SizedBox(height: 6),
                                    SelectableText(
                                      'meta: ${a.meta}',
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 11.5,
                                        color: cs.onSurfaceVariant,
                                        height: 1.25,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
