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
  toggleMasking,
  openAdvancedInfo,
}

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

  // Email masking (not persisted; defaults ON for safety)
  bool _maskSensitiveInEmail = true;

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

  // MIME base64 line length (RFC 2045 recommends 76 chars)
  static const int _mimeB64LineLength = 76;

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
    _loadApiLogs();

    _traceTickListener = () {
      if (!mounted) return;
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

      // 기본 정책: 회전 포함 전체 로드
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

  // ─────────────────────────────────────────────────────────────
  // Filter predicate (중복 제거)
  // ─────────────────────────────────────────────────────────────

  bool _isErrorEntry(_LogEntry e) => (e.level ?? '').toLowerCase() == 'error';

  bool _tagMatches(_LogEntry e, String selectedTag) {
    if (selectedTag == _tagAll) return true;
    if (selectedTag == _tagUntagged) return e.tags.isEmpty;
    return e.tags.contains(selectedTag);
  }

  bool _searchMatches(_LogEntry e, String keyLower) {
    if (keyLower.isEmpty) return true;

    final sb = StringBuffer();
    if (e.message != null && e.message!.isNotEmpty) {
      sb.write(e.message);
      sb.write(' ');
    }
    if (e.ts != null) {
      sb.write(_fmt.format(e.ts!));
    }
    return sb.toString().toLowerCase().contains(keyLower);
  }

  bool _matchesApiFilter(
      _LogEntry e, {
        required String keyLower,
        required String selectedTag,
      }) {
    if (!_isErrorEntry(e)) return false;
    if (!_tagMatches(e, selectedTag)) return false;
    if (!_searchMatches(e, keyLower)) return false;
    return true;
  }

  void _applyFilter() {
    final keyLower = _searchCtrl.text.trim().toLowerCase();
    final selectedTag = _selectedTag;

    _filtered = _allEntries
        .where((e) => _matchesApiFilter(e, keyLower: keyLower, selectedTag: selectedTag))
        .toList(growable: false);
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

  // ─────────────────────────────────────────────────────────────
  // MIME base64 wrap + Email masking
  // ─────────────────────────────────────────────────────────────

  String _wrapBase64Lines(String b64, {int lineLength = _mimeB64LineLength}) {
    if (b64.isEmpty) return '';
    final sb = StringBuffer();
    for (int i = 0; i < b64.length; i += lineLength) {
      final end = (i + lineLength < b64.length) ? (i + lineLength) : b64.length;
      sb.write(b64.substring(i, end));
      sb.write('\r\n');
    }
    return sb.toString();
  }

  String _sanitizeForEmail(String input) {
    var out = input;

    // 1) Bearer 토큰
    out = out.replaceAllMapped(
      RegExp(r'(Bearer\s+)[A-Za-z0-9\-\._~\+\/]+=*', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***',
    );

    // 2) JSON 형태 토큰 값
    out = out.replaceAllMapped(
      RegExp(r'("access_token"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("refresh_token"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("id_token"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("authorization"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );
    out = out.replaceAllMapped(
      RegExp(r'("x-api-key"\s*:\s*")[^"]+(")', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***${m[2]}',
    );

    // 3) 쿼리스트링/키=값 형태 토큰
    out = out.replaceAllMapped(
      RegExp(r'((?:access_token|refresh_token|id_token)=)[^&\s]+', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***',
    );
    out = out.replaceAllMapped(
      RegExp(r'((?:x-api-key|api_key|apikey)=)[^&\s]+', caseSensitive: false),
          (m) => '${m[1]}***REDACTED***',
    );

    // 4) 이메일 주소
    out = out.replaceAllMapped(
      RegExp(r'\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b', caseSensitive: false),
          (_) => '***@***',
    );

    // 5) 한국 휴대폰 번호(단순 패턴)
    out = out.replaceAllMapped(
      RegExp(r'\b01[016789]-?\d{3,4}-?\d{4}\b'),
          (_) => '***-****-****',
    );

    // 6) 주민등록번호(단순 패턴)
    out = out.replaceAllMapped(
      RegExp(r'\b\d{6}-?\d{7}\b'),
          (_) => '******-*******',
    );

    return out;
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

      final keyLower = _searchCtrl.text.trim().toLowerCase();
      final selectedTag = _selectedTag;

      final filteredToSend = entries
          .where((e) => _matchesApiFilter(e, keyLower: keyLower, selectedTag: selectedTag))
          .toList(growable: false);

      if (filteredToSend.isEmpty) {
        if (!mounted) return;
        showSelectedSnackbar(context, '보낼 에러 로그가 없습니다.');
        return;
      }

      final now = DateTime.now();
      final subjectTag = selectedTag == _tagAll ? 'ALL' : (selectedTag == _tagUntagged ? 'UNTAGGED' : selectedTag);
      final subject = 'Pelican API 디버그 에러 로그($subjectTag) (${_fmt.format(now)})';
      final filename = 'pelican_api_logs_${DateFormat('yyyyMMdd_HHmmss').format(now)}.md';

      final sb = StringBuffer()
        ..writeln('# Pelican 디버그 에러 로그 (API)')
        ..writeln()
        ..writeln('- 생성 시각: ${_fmt.format(now)}')
        ..writeln('- 필터(tag): $subjectTag')
        ..writeln('- 검색어: ${_searchCtrl.text.trim().isEmpty ? '-' : _searchCtrl.text.trim()}')
        ..writeln('- 총 에러 로그 수: ${filteredToSend.length}')
        ..writeln('- 민감정보 마스킹: ${_maskSensitiveInEmail ? "ON" : "OFF"}')
        ..writeln()
        ..writeln('```json');

      for (final e in filteredToSend.reversed) {
        final rawLine = e.original ?? e.message ?? '';
        sb.writeln(_maskSensitiveInEmail ? _sanitizeForEmail(rawLine) : rawLine);
      }
      sb.writeln('```');

      final attachmentText = sb.toString();
      final attachmentB64 = base64.encode(utf8.encode(attachmentText));
      final attachmentB64Wrapped = _wrapBase64Lines(attachmentB64);

      final boundary = 'pelican_logs_${now.millisecondsSinceEpoch}';
      const toAddress = 'pelicangnc1@gmail.com';
      const bodyText = '첨부된 Markdown 파일(API 에러 로그)을 확인해 주세요.';

      const crlf = '\r\n';
      final mime = StringBuffer()
        ..write('MIME-Version: 1.0$crlf')
        ..write('To: $toAddress$crlf')
        ..write('Subject: $subject$crlf')
        ..write('Content-Type: multipart/mixed; boundary="$boundary"$crlf')
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/plain; charset="utf-8"$crlf')
        ..write('Content-Transfer-Encoding: 7bit$crlf')
        ..write(crlf)
        ..write(bodyText)
        ..write(crlf)
        ..write('--$boundary$crlf')
        ..write('Content-Type: text/markdown; charset="utf-8"; name="$filename"$crlf')
        ..write('Content-Disposition: attachment; filename="$filename"$crlf')
        ..write('Content-Transfer-Encoding: base64$crlf')
        ..write(crlf)
        ..write(attachmentB64Wrapped)
        ..write('--$boundary--$crlf');

      final raw = base64Url.encode(utf8.encode(mime.toString()));

      final client = await GoogleAuthSession.instance.safeClient();
      final api = gmail.GmailApi(client);
      final message = gmail.Message()..raw = raw;

      await api.users.messages.send(message, 'me');

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

  // ─────────────────────────────────────────────────────────────
  // ✅ UX 개선: 로그 상세 BottomSheet "추론 기반 요약" + 구조화 표시
  // ─────────────────────────────────────────────────────────────

  _ParsedLog _parseForDetail(_LogEntry entry) {
    final rawLine = (entry.original ?? '').trim();
    Map<String, dynamic>? envelope;

    // 1) 원문 JSON 라인(표준) 파싱
    if (rawLine.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawLine);
        if (decoded is Map) {
          envelope = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        // ignore
      }
    }

    // 2) message 텍스트 확보 (entry.message가 우선)
    final messageText = (entry.message ?? envelope?['message']?.toString() ?? '').trim();

    // 3) message가 JSON 문자열(대개 pretty JSON)일 경우 payload로 파싱
    Map<String, dynamic>? payload;
    if (messageText.isNotEmpty) {
      final t = messageText.trimLeft();
      final looksJson = (t.startsWith('{') && t.contains('}')) || (t.startsWith('[') && t.contains(']'));
      if (looksJson) {
        try {
          final decoded = jsonDecode(messageText);
          if (decoded is Map) {
            payload = Map<String, dynamic>.from(decoded);
          } else if (decoded is List) {
            payload = <String, dynamic>{'items': decoded};
          }
        } catch (_) {
          // ignore
        }
      }
    }

    return _ParsedLog(
      entry: entry,
      envelope: envelope,
      payload: payload,
      messageText: messageText,
      rawLine: entry.original ?? entry.message ?? '',
    );
  }

  _LogInsight _inferInsight(_ParsedLog p) {
    final tags = p.entry.tags;
    final envelope = p.envelope;
    final payload = p.payload;

    String? tag = _pickFirstString(payload, const ['tag', 'scope', 'source', 'module']) ??
        _pickFirstString(envelope, const ['tag', 'scope', 'source', 'module']);

    // status / method / url 후보 키들
    final status = _pickFirstInt(payload, const ['status', 'statusCode', 'httpStatus', 'code']) ??
        _pickFirstInt(envelope, const ['status', 'statusCode', 'httpStatus', 'code']);
    final method = _pickFirstString(payload, const ['method', 'httpMethod']);
    final url = _pickFirstString(payload, const ['url', 'uri', 'endpoint', 'path']);
    final err = _pickFirstString(payload, const ['error', 'exception', 'err', 'stack', 'stackTrace']) ??
        _pickFirstString(envelope, const ['error', 'exception', 'err', 'stack', 'stackTrace']);

    final msg = p.messageText;
    final raw = p.rawLine;

    final hay = '${tag ?? ''}\n${tags.join(' ')}\n${method ?? ''} ${url ?? ''}\n'
        '${status ?? ''}\n$msg\n$err\n$raw'
        .toLowerCase();

    // 카테고리(휴리스틱)
    _IssueCategory cat;
    if (hay.contains('timeoutexception') || hay.contains('timed out') || hay.contains('timeout')) {
      cat = _IssueCategory.timeout;
    } else if (hay.contains('socketexception') ||
        hay.contains('failed host lookup') ||
        hay.contains('network is unreachable') ||
        hay.contains('connection refused') ||
        hay.contains('connection reset') ||
        hay.contains('dns') ||
        hay.contains('handshakeexception') ||
        hay.contains('certificate') ||
        hay.contains('tls')) {
      cat = _IssueCategory.network;
    } else if (hay.contains('401') ||
        hay.contains('unauthorized') ||
        hay.contains('invalid_grant') ||
        hay.contains('token') && (hay.contains('expired') || hay.contains('invalid')) ||
        hay.contains('authentication')) {
      cat = _IssueCategory.auth;
    } else if (hay.contains('403') || hay.contains('permission') || hay.contains('forbidden') || hay.contains('denied')) {
      cat = _IssueCategory.permission;
    } else if (hay.contains('firestore') ||
        hay.contains('firebase') ||
        hay.contains('cloud_firestore') ||
        hay.contains('fcm') ||
        hay.contains('gcs') ||
        hay.contains('storage')) {
      cat = _IssueCategory.firebase;
    } else if (hay.contains('formatexception') ||
        hay.contains('unexpected character') ||
        hay.contains('json') && hay.contains('decode') ||
        hay.contains('type') && hay.contains('is not a subtype')) {
      cat = _IssueCategory.parsing;
    } else if (status != null && status >= 500) {
      cat = _IssueCategory.server;
    } else if (status != null && status >= 400) {
      cat = _IssueCategory.client;
    } else if (hay.contains('nosuchmethoderror') || hay.contains('null check operator') || hay.contains('null')) {
      cat = _IssueCategory.appLogic;
    } else {
      cat = _IssueCategory.unknown;
    }

    // Headline(한 줄 진단)
    final headline = _buildHeadline(cat: cat, status: status, method: method, url: url);

    // 핵심 요약 필드 (우선순위 높은 것만)
    final fields = <_KeyValue>[
      if (tag != null && tag.trim().isNotEmpty) _KeyValue('tag', tag.trim()),
      if (tags.isNotEmpty) _KeyValue('tags', tags.join(', ')),
      if (method != null) _KeyValue('method', method),
      if (url != null) _KeyValue('url', url),
      if (status != null) _KeyValue('status', status.toString()),
      if (payload != null && payload.containsKey('message')) _KeyValue('message', payload['message']?.toString() ?? ''),
      if (payload != null && payload.containsKey('error')) _KeyValue('error', payload['error']?.toString() ?? ''),
      if (payload != null && payload.containsKey('exception')) _KeyValue('exception', payload['exception']?.toString() ?? ''),
    ];

    // 원인/조치(간단하지만 즉시 행동 가능한 수준)
    final cause = _probableCause(cat, status: status, hay: hay);
    final actions = _recommendedActions(cat, status: status);

    // 요약 텍스트(복사용)
    final summaryForCopy = _buildCopySummary(
      headline: headline,
      ts: p.entry.ts,
      fields: fields,
      cause: cause,
      actions: actions,
    );

    return _LogInsight(
      category: cat,
      headline: headline,
      probableCause: cause,
      actions: actions,
      fields: fields,
      summaryForCopy: summaryForCopy,
    );
  }

  String _buildHeadline({required _IssueCategory cat, int? status, String? method, String? url}) {
    final m = method?.toUpperCase();
    final u = (url ?? '').trim();
    final hasReq = (m != null && m.isNotEmpty) || u.isNotEmpty;

    String base;
    switch (cat) {
      case _IssueCategory.timeout:
        base = '요청 시간 초과(Timeout)';
        break;
      case _IssueCategory.network:
        base = '네트워크/연결 오류';
        break;
      case _IssueCategory.auth:
        base = '인증 오류(토큰/세션)';
        break;
      case _IssueCategory.permission:
        base = '권한 오류(Forbidden/Denied)';
        break;
      case _IssueCategory.server:
        base = '서버 오류(5xx)';
        break;
      case _IssueCategory.client:
        base = '요청 오류(4xx)';
        break;
      case _IssueCategory.firebase:
        base = 'Firebase/Firestore 오류';
        break;
      case _IssueCategory.parsing:
        base = '파싱/타입 오류(응답 처리)';
        break;
      case _IssueCategory.appLogic:
        base = '앱 로직 오류(Null/메서드)';
        break;
      case _IssueCategory.unknown:
        base = '알 수 없는 오류';
        break;
    }

    final statusPart = status != null ? ' (status=$status)' : '';
    if (!hasReq) return '$base$statusPart';

    final req = '${m ?? ''}${(m != null && u.isNotEmpty) ? ' ' : ''}$u'.trim();
    if (req.isEmpty) return '$base$statusPart';

    return '$base$statusPart · $req';
  }

  String? _probableCause(_IssueCategory cat, {required int? status, required String hay}) {
    switch (cat) {
      case _IssueCategory.timeout:
        return '서버 응답 지연, 네트워크 지연, 또는 클라이언트 타임아웃 설정이 짧을 가능성이 큽니다.';
      case _IssueCategory.network:
        if (hay.contains('certificate') || hay.contains('tls') || hay.contains('handshakeexception')) {
          return 'TLS/인증서 핸드셰이크 문제가 의심됩니다(기기 시간/인증서/프록시/중간자 환경).';
        }
        if (hay.contains('dns') || hay.contains('failed host lookup')) {
          return 'DNS/호스트 해석 실패가 의심됩니다(네트워크 환경 또는 도메인 문제).';
        }
        return '네트워크 연결 불가/불안정(오프라인, 방화벽, APN, 서버 접속 불가) 가능성이 큽니다.';
      case _IssueCategory.auth:
        return '토큰 만료/무효 또는 OAuth 세션 문제로 인증이 거절된 상황일 가능성이 큽니다.';
      case _IssueCategory.permission:
        return '권한(ACL/Role/Firestore Rules 등)이 부족하여 요청이 거절된 가능성이 큽니다.';
      case _IssueCategory.server:
        return '서버 내부 오류 또는 다운스트림 장애로 처리 실패(5xx) 가능성이 큽니다.';
      case _IssueCategory.client:
        if (status == 404) return '요청 경로/리소스가 존재하지 않거나 잘못된 endpoint일 수 있습니다.';
        if (status == 400) return '요청 파라미터/바디 형식 오류일 가능성이 큽니다.';
        return '클라이언트 요청이 유효하지 않거나 권한/상태 문제로 실패(4xx) 가능성이 큽니다.';
      case _IssueCategory.firebase:
        return 'Firestore Rules/네트워크/인덱스/권한 또는 Firebase SDK 호출 오류 가능성이 큽니다.';
      case _IssueCategory.parsing:
        return '서버 응답 포맷이 예상과 다르거나, JSON/타입 캐스팅 로직이 맞지 않을 가능성이 큽니다.';
      case _IssueCategory.appLogic:
        return 'Null 처리 누락 또는 객체 타입 가정이 깨져 런타임 예외가 발생했을 가능성이 큽니다.';
      case _IssueCategory.unknown:
        return null;
    }
  }

  List<String> _recommendedActions(_IssueCategory cat, {required int? status}) {
    switch (cat) {
      case _IssueCategory.timeout:
        return const [
          '네트워크 상태(와이파이/데이터) 확인 후 재시도',
          '서버 처리 시간/부하 확인(해당 API/Firestore/Cloud Function)',
          '클라이언트 타임아웃/재시도 정책 점검',
        ];
      case _IssueCategory.network:
        return const [
          '오프라인 여부/네트워크 전환 후 재시도',
          '도메인/DNS/프록시/방화벽 환경 확인',
          'TLS/인증서 오류 시 기기 시간 및 인증서 체인 확인',
        ];
      case _IssueCategory.auth:
        return const [
          '토큰 재발급(로그인 재시도) 또는 세션 초기화',
          'OAuth 스코프/클라이언트 설정 점검',
          '서버 측 인증 로직(401 원인) 확인',
        ];
      case _IssueCategory.permission:
        return const [
          'Firestore Rules/서버 ACL/역할(Role) 확인',
          '요청 계정/조직/권한 설정 점검',
          '관리자 권한으로 동일 요청 재현/비교',
        ];
      case _IssueCategory.server:
        return const [
          '서버 로그/모니터링에서 동일 시간대 에러 확인',
          '다운스트림(외부 API/DB) 장애 여부 확인',
          '재시도 정책 및 서킷브레이커/백오프 적용 검토',
        ];
      case _IssueCategory.client:
        return <String>[
          '요청 URL/파라미터/바디 스키마 점검',
          if (status == 404) 'endpoint/path 오타 또는 배포 버전 mismatch 확인',
          if (status == 400) '필수 필드 누락/타입 불일치 여부 확인',
          '서버의 4xx 응답 메시지(에러 코드) 확인',
        ];
      case _IssueCategory.firebase:
        return const [
          'Firestore Rules/인덱스 요구사항/권한 확인',
          '네트워크 상태 및 Firebase SDK 에러 메시지 확인',
          '동일 쿼리/쓰기 요청을 콘솔/테스트에서 재현',
        ];
      case _IssueCategory.parsing:
        return const [
          '서버 응답 JSON 스키마와 DTO/파서 로직 비교',
          'null/타입 변동에 대한 방어코드 추가',
          '에러 응답(비정상 케이스)도 동일 파서가 타는지 점검',
        ];
      case _IssueCategory.appLogic:
        return const [
          '스택트레이스 기준으로 Null/타입 가정 깨지는 지점 확인',
          'Guard clause(early return)/nullable 처리 강화',
          '실패 케이스 재현 후 unit/widget test 추가',
        ];
      case _IssueCategory.unknown:
        return const [
          '원문(특히 stackTrace/error) 확인',
          '동일 조건 재현 후 payload에 status/url/method/error를 포함하도록 로깅 강화',
        ];
    }
  }

  String _buildCopySummary({
    required String headline,
    required DateTime? ts,
    required List<_KeyValue> fields,
    required String? cause,
    required List<String> actions,
  }) {
    final b = StringBuffer();
    b.writeln('### 진단');
    b.writeln(headline);
    b.writeln();
    b.writeln('### 시간');
    b.writeln(ts?.toIso8601String() ?? '-');
    b.writeln();
    b.writeln('### 핵심 필드');
    for (final kv in fields.take(12)) {
      final v = kv.value.trim();
      if (v.isEmpty) continue;
      b.writeln('- ${kv.key}: ${_oneLine(v, max: 220)}');
    }
    b.writeln();
    b.writeln('### 추정 원인');
    b.writeln(cause ?? '-');
    b.writeln();
    b.writeln('### 권장 조치');
    for (final a in actions) {
      b.writeln('- $a');
    }
    return b.toString();
  }

  String _oneLine(String s, {int max = 180}) {
    final t = s.replaceAll('\r', ' ').replaceAll('\n', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    if (t.length <= max) return t;
    return '${t.substring(0, max)}…';
  }

  String? _pickFirstString(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      final s = v.toString().trim();
      if (s.isNotEmpty) return s;
    }
    return null;
  }

  int? _pickFirstInt(Map<String, dynamic>? m, List<String> keys) {
    if (m == null) return null;
    for (final k in keys) {
      final v = m[k];
      if (v == null) continue;
      if (v is int) return v;
      final s = v.toString().trim();
      final n = int.tryParse(s);
      if (n != null) return n;
    }
    return null;
  }

  Future<void> _showLogDetail(_LogEntry entry) async {
    final cs = Theme.of(context).colorScheme;

    final parsed = _parseForDetail(entry);
    final insight = _inferInsight(parsed);

    final tsText = entry.ts != null ? _fmt.format(entry.ts!) : '-';
    final raw = (entry.original ?? entry.message ?? '').trim();
    final rawPretty = _prettyJsonIfPossible(raw);

    // “핵심”으로 삼을 메시지(가독성 위해 원문 전체가 아니라 요약)
    final messagePreview = _extractPrimaryMessage(parsed);

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

                      // Header
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            _CategoryIcon(category: insight.category),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '문제 진단',
                                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                              ),
                            ),
                            IconButton(
                              tooltip: '요약 복사',
                              onPressed: () async {
                                await Clipboard.setData(ClipboardData(text: insight.summaryForCopy));
                                if (!mounted) return;
                                showSuccessSnackbar(context, '요약이 복사되었습니다.');
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
                      Divider(height: 1, color: cs.outlineVariant.withOpacity(0.6)),

                      Expanded(
                        child: ListView(
                          padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                          children: [
                            // Headline
                            Container(
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withOpacity(0.35),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    insight.headline,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w900, height: 1.25),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _InfoChip(icon: Icons.schedule_rounded, label: tsText),
                                      _CategoryChip(category: insight.category),
                                      if (entry.tags.isNotEmpty)
                                        _InfoChip(
                                          icon: Icons.sell_outlined,
                                          label: entry.tags.length == 1 ? entry.tags.first : '${entry.tags.length} tags',
                                        )
                                      else
                                        const _InfoChip(icon: Icons.sell_outlined, label: 'untagged'),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  if (messagePreview.isNotEmpty)
                                    _MonospaceCallout(
                                      title: '핵심 메시지',
                                      text: messagePreview,
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Key Fields
                            _DetailSection(
                              title: '추출된 핵심 필드',
                              icon: Icons.tune_rounded,
                              child: insight.fields.isEmpty
                                  ? Text(
                                '추출 가능한 구조화 필드가 없습니다(원문 확인 권장).',
                                style: TextStyle(color: cs.onSurfaceVariant),
                              )
                                  : _KeyValueGrid(items: insight.fields),
                            ),

                            const SizedBox(height: 12),

                            // Cause + Actions
                            _DetailSection(
                              title: '추정 원인 및 권장 조치',
                              icon: Icons.lightbulb_rounded,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    insight.probableCause ?? '추정 원인을 특정하기 어렵습니다. 원문(특히 stack/error)을 확인하세요.',
                                    style: TextStyle(color: cs.onSurface, height: 1.3),
                                  ),
                                  const SizedBox(height: 10),
                                  for (final a in insight.actions)
                                    Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: _Bullet(text: a),
                                    ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Raw
                            _DetailSection(
                              title: '원문(로그 라인)',
                              icon: Icons.article_rounded,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Expanded(
                                        child: Text(
                                          '필요 시 개발자 분석용으로 원문을 확인/복사하세요.',
                                          style: TextStyle(color: cs.onSurfaceVariant),
                                        ),
                                      ),
                                      TextButton.icon(
                                        onPressed: () async {
                                          await Clipboard.setData(ClipboardData(text: raw));
                                          if (!mounted) return;
                                          showSuccessSnackbar(context, '원문이 복사되었습니다.');
                                        },
                                        icon: const Icon(Icons.copy_rounded, size: 18),
                                        label: const Text('원문 복사'),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 8),
                                  ExpansionTile(
                                    tilePadding: EdgeInsets.zero,
                                    childrenPadding: EdgeInsets.zero,
                                    initiallyExpanded: false,
                                    title: Text(
                                      '원문 펼치기',
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: cs.onSurface,
                                      ),
                                    ),
                                    children: [
                                      const SizedBox(height: 8),
                                      Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: cs.surfaceContainerHighest.withOpacity(0.30),
                                          borderRadius: BorderRadius.circular(12),
                                          border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
                                        ),
                                        child: SelectableText(
                                          rawPretty,
                                          style: TextStyle(
                                            fontFamily: 'monospace',
                                            height: 1.25,
                                            color: cs.onSurface,
                                            fontSize: 12.5,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),

                            const SizedBox(height: 10),
                          ],
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

  String _prettyJsonIfPossible(String text) {
    final t = text.trim();
    if (t.isEmpty) return '';
    try {
      final decoded = jsonDecode(t);
      const enc = JsonEncoder.withIndent('  ');
      return enc.convert(decoded);
    } catch (_) {
      return t;
    }
  }

  String _extractPrimaryMessage(_ParsedLog p) {
    // 가장 사람이 읽기 쉬운 1~2줄 메시지 추출
    // payload에 'message'/'error'가 있으면 우선, 없으면 messageText 일부
    final payload = p.payload;

    String? best;
    if (payload != null) {
      best = _pickFirstString(payload, const ['message', 'error', 'exception', 'detail', 'reason']);
    }
    best ??= p.messageText;

    final cleaned = best.replaceAll('\r', '\n').trim();
    if (cleaned.isEmpty) return '';
    return _oneLine(cleaned, max: 280);
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

                        // More menu
                        PopupMenuButton<_MenuAction>(
                          tooltip: '더보기',
                          onSelected: (action) async {
                            switch (action) {
                              case _MenuAction.toggleGoogleBlock:
                                if (!_blockFlagLoaded) return;
                                await _setGoogleSessionBlock(!_blockGoogleSessionAttempts);
                                break;

                              case _MenuAction.toggleMasking:
                                setState(() => _maskSensitiveInEmail = !_maskSensitiveInEmail);
                                if (!mounted) return;
                                showSuccessSnackbar(
                                  context,
                                  _maskSensitiveInEmail ? '이메일 마스킹: ON' : '이메일 마스킹: OFF',
                                );
                                break;

                              case _MenuAction.openAdvancedInfo:
                                if (!mounted) return;
                                showSelectedSnackbar(
                                  context,
                                  '고급 설정: 구글 세션 차단(${_blockGoogleSessionAttempts ? "ON" : "OFF"}), '
                                      '이메일 마스킹(${_maskSensitiveInEmail ? "ON" : "OFF"})',
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
                            CheckedPopupMenuItem<_MenuAction>(
                              value: _MenuAction.toggleMasking,
                              checked: _maskSensitiveInEmail,
                              child: const Text('이메일 전송 시 민감정보 마스킹'),
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
                    final label = (t == _tagAll) ? '전체' : (t == _tagUntagged ? '(미지정)' : t);
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
          child: _loading ? const Center(child: CircularProgressIndicator()) : _buildApiList(context),
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
// Detail parsing / insight models (NEW)
// ─────────────────────────────────────────────────────────────

enum _IssueCategory {
  timeout,
  network,
  auth,
  permission,
  client,
  server,
  firebase,
  parsing,
  appLogic,
  unknown,
}

class _ParsedLog {
  final _LogEntry entry;
  final Map<String, dynamic>? envelope;
  final Map<String, dynamic>? payload;
  final String messageText;
  final String rawLine;

  _ParsedLog({
    required this.entry,
    required this.envelope,
    required this.payload,
    required this.messageText,
    required this.rawLine,
  });
}

class _KeyValue {
  final String key;
  final String value;

  _KeyValue(this.key, this.value);
}

class _LogInsight {
  final _IssueCategory category;
  final String headline;
  final String? probableCause;
  final List<String> actions;
  final List<_KeyValue> fields;
  final String summaryForCopy;

  _LogInsight({
    required this.category,
    required this.headline,
    required this.probableCause,
    required this.actions,
    required this.fields,
    required this.summaryForCopy,
  });
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

class _CategoryChip extends StatelessWidget {
  final _IssueCategory category;

  const _CategoryChip({required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    String label;
    IconData icon;
    Color tone;

    switch (category) {
      case _IssueCategory.timeout:
        label = 'Timeout';
        icon = Icons.timer_rounded;
        tone = cs.tertiary;
        break;
      case _IssueCategory.network:
        label = 'Network';
        icon = Icons.wifi_off_rounded;
        tone = cs.tertiary;
        break;
      case _IssueCategory.auth:
        label = 'Auth';
        icon = Icons.lock_outline_rounded;
        tone = cs.secondary;
        break;
      case _IssueCategory.permission:
        label = 'Permission';
        icon = Icons.block_rounded;
        tone = cs.secondary;
        break;
      case _IssueCategory.client:
        label = 'Client(4xx)';
        icon = Icons.report_problem_rounded;
        tone = cs.error;
        break;
      case _IssueCategory.server:
        label = 'Server(5xx)';
        icon = Icons.cloud_off_rounded;
        tone = cs.error;
        break;
      case _IssueCategory.firebase:
        label = 'Firebase';
        icon = Icons.cloud_rounded;
        tone = cs.primary;
        break;
      case _IssueCategory.parsing:
        label = 'Parsing';
        icon = Icons.data_object_rounded;
        tone = cs.primary;
        break;
      case _IssueCategory.appLogic:
        label = 'App';
        icon = Icons.code_rounded;
        tone = cs.primary;
        break;
      case _IssueCategory.unknown:
        label = 'Unknown';
        icon = Icons.help_outline_rounded;
        tone = cs.onSurfaceVariant;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tone.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: tone.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: tone),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: tone,
            ),
          ),
        ],
      ),
    );
  }
}

class _CategoryIcon extends StatelessWidget {
  final _IssueCategory category;

  const _CategoryIcon({required this.category});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    IconData icon;
    Color color;

    switch (category) {
      case _IssueCategory.timeout:
        icon = Icons.timer_rounded;
        color = cs.tertiary;
        break;
      case _IssueCategory.network:
        icon = Icons.wifi_off_rounded;
        color = cs.tertiary;
        break;
      case _IssueCategory.auth:
        icon = Icons.lock_outline_rounded;
        color = cs.secondary;
        break;
      case _IssueCategory.permission:
        icon = Icons.block_rounded;
        color = cs.secondary;
        break;
      case _IssueCategory.client:
      case _IssueCategory.server:
        icon = Icons.error_rounded;
        color = cs.error;
        break;
      case _IssueCategory.firebase:
        icon = Icons.cloud_rounded;
        color = cs.primary;
        break;
      case _IssueCategory.parsing:
        icon = Icons.data_object_rounded;
        color = cs.primary;
        break;
      case _IssueCategory.appLogic:
        icon = Icons.code_rounded;
        color = cs.primary;
        break;
      case _IssueCategory.unknown:
        icon = Icons.help_outline_rounded;
        color = cs.onSurfaceVariant;
        break;
    }

    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.22)),
      ),
      child: Icon(icon, color: color, size: 20),
    );
  }
}

class _DetailSection extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _DetailSection({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withOpacity(0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _Bullet extends StatelessWidget {
  final String text;

  const _Bullet({required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('• ', style: TextStyle(color: cs.onSurfaceVariant, fontWeight: FontWeight.w900)),
        Expanded(
          child: Text(
            text,
            style: TextStyle(color: cs.onSurface, height: 1.25),
          ),
        ),
      ],
    );
  }
}

class _KeyValueGrid extends StatelessWidget {
  final List<_KeyValue> items;

  const _KeyValueGrid({required this.items});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final shown = items.where((e) => e.value.trim().isNotEmpty).toList();

    return Column(
      children: [
        for (final kv in shown.take(14))
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              decoration: BoxDecoration(
                color: cs.surface.withOpacity(0.50),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      kv.key,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      kv.value,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12.5,
                        height: 1.25,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _MonospaceCallout extends StatelessWidget {
  final String title;
  final String text;

  const _MonospaceCallout({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.surface.withOpacity(0.50),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            style: TextStyle(
              fontFamily: 'monospace',
              color: cs.onSurface,
              height: 1.25,
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
