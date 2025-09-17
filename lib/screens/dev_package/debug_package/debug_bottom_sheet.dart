// File: lib/screens/stub_package/debug_bottom_sheet.dart
//
// - error 로그만 표시
// - Firestore / Local 소스 필터 칩
// - 검색(메시지/시간)
// - 내보내기/복사/전체삭제(회전 포함)
// - 리스트 스크롤 성능 및 예외 처리
// - 작은 화면에서도 안전하도록 타이틀/칩 영역 Row → Wrap 적용
//

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../utils/snackbar_helper.dart';
import 'debug_firestore_logger.dart';
import 'debug_local_logger.dart';
// ✅ snackbar_helper 경로는 프로젝트 구조에 맞게 조정하세요.

enum _LogSource { firestore, local }

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

  // 현재 소스
  _LogSource _source = _LogSource.firestore;

  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadTail();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _listCtrl.dispose();
    super.dispose();
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
    if (mounted) {
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
      // ✅ snackbar_helper 사용
      showSuccessSnackbar(context, '${_labelForSource()} 로그가 삭제되었습니다.');
    } catch (e) {
      if (!mounted) return;
      // ✅ snackbar_helper 사용
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
    // ✅ snackbar_helper 사용
    showSuccessSnackbar(context, '클립보드에 복사되었습니다.');
  }

  Future<void> _export() async {
    final files = await _getLogger().getAllLogFilesExisting();
    if (files.isEmpty) {
      if (!mounted) return;
      // ✅ snackbar_helper 사용
      showSelectedSnackbar(context, '내보낼 ${_labelForSource()} 로그 파일이 없습니다.');
      return;
    }
    await Share.shareXFiles(
      files.map((f) => XFile(f.path)).toList(),
      text: '${_labelForSource()} 로그 묶음(회전 포함)',
      subject: '${_labelForSource()} 로그',
    );
  }

  // ------- Helpers -------
  dynamic _getLogger() {
    switch (_source) {
      case _LogSource.local:
        return DebugLocalLogger();
      case _LogSource.firestore:
        return DebugFirestoreLogger();
    }
  }

  String _labelForSource() {
    return _source == _LogSource.local ? 'Local' : 'Firestore';
  }

  // ------- UI -------
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SafeArea(
      top: false,
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        child: Material(
          color: Colors.white,
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.92,
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

                // 타이틀 + 소스 선택 + 액션 (Wrap으로 오버플로우 방지)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      // 왼쪽: 아이콘 + 제목 (좁은 폭에서 말줄임)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.bug_report_rounded, color: cs.primary),
                          const SizedBox(width: 8),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 240),
                            child: Text(
                              '${_labelForSource()} 에러 로그',
                              overflow: TextOverflow.ellipsis,
                              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                            ),
                          ),
                        ],
                      ),

                      // 가운데: 소스 선택 칩(가로 스크롤 허용)
                      SizedBox(
                        height: 36,
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ChoiceChip(
                                label: const Text('Firestore'),
                                selected: _source == _LogSource.firestore,
                                onSelected: (_) => setState(() {
                                  _source = _LogSource.firestore;
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
                            ],
                          ),
                        ),
                      ),

                      // 오른쪽: 액션 버튼들
                      Row(
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
                            tooltip: '닫기',
                            onPressed: () => Navigator.of(context).maybePop(),
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                // 검색 + 액션
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
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
                        onPressed: _export,
                        icon: const Icon(Icons.upload_file, color: Colors.blueGrey),
                        tooltip: '파일 내보내기',
                      ),
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
                const SizedBox(height: 8),

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

  const _LogTile({required this.entry, required this.fmt});

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
              Text(d0, style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
              Text(d1, style: const TextStyle(fontSize: 11, color: Colors.grey, fontFamily: 'monospace')),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.message ?? '',
              style: const TextStyle(fontSize: 14, color: Colors.redAccent, fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}
