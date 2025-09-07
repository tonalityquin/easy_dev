// File: lib/screens/stub_package/debug_bottom_sheet.dart
//
// - tail/전체 로드 토글
// - 레벨 칩/태그 칩 필터 (가로 스크롤, 줄바꿈 없음)
// - 검색(레벨/메시지/시간)
// - 내보내기/복사/전체삭제(회전 포함)
// - 리스트 스크롤 성능 및 예외 처리

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import 'debug_firestore_logger.dart';

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

  // 태그 수집용
  final Set<String> _allTags = {};
  final Set<String> _selectedTags = {};

  // 레벨 필터
  final List<String> _levels = const ['success', 'error', 'called', 'warn', 'info'];
  final Set<String> _selectedLevels = {'success', 'error', 'called', 'warn', 'info'};

  // 로딩 상태/모드
  bool _loading = true;
  bool _fullLoaded = false; // true면 회전 포함 전체 로드 완료

  final DateFormat _fmt = DateFormat('yyyy-MM-dd HH:mm:ss');

  @override
  void initState() {
    super.initState();
    _loadTail(); // 기본: 빠른 테일 로드
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
    final lines = await DebugFirestoreLogger().readTailLines(
      maxLines: 1500,
      maxBytes: 1024 * 1024, // 1MB
    );
    _ingestLines(lines, newestFirst: true);
  }

  Future<void> _loadAll() async {
    setState(() {
      _loading = true;
      _fullLoaded = true;
    });
    final lines = await DebugFirestoreLogger().readAllLinesCombined();
    _ingestLines(lines, newestFirst: false); // oldest..newest → 최신 우선 정렬
  }

  void _ingestLines(List<String> lines, {required bool newestFirst}) {
    final entries = lines.map(_parseLine).whereType<_LogEntry>().toList();
    // 최신이 위로 오도록
    entries.sort((a, b) {
      final at = a.ts?.millisecondsSinceEpoch ?? 0;
      final bt = b.ts?.millisecondsSinceEpoch ?? 0;
      return bt.compareTo(at);
    });

    _allTags
      ..clear()
      ..addAll(entries.expand((e) => e.tags));

    setState(() {
      _all = entries;
      _applyFilter();
      _loading = false;
    });
  }

  // ------- 필터 로직 -------
  void _applyFilter() {
    final key = _searchCtrl.text.trim().toLowerCase();
    final hasTagFilter = _selectedTags.isNotEmpty;

    _filtered = _all.where((e) {
      // 레벨
      if (e.level != null && !_selectedLevels.contains(e.level)) return false;

      // 태그
      if (hasTagFilter && !_selectedTags.any((t) => e.tags.contains(t))) {
        return false;
      }

      // 검색
      if (key.isNotEmpty) {
        final s = StringBuffer();
        if (e.level != null) s.write('${e.level} ');
        if (e.message != null) s.write('${e.message} ');
        if (e.ts != null) s.write(_fmt.format(e.ts!));
        if (!s.toString().toLowerCase().contains(key)) return false;
      }

      return true;
    }).toList();
  }

  void _onSearchChanged(String _) => setState(_applyFilter);

  void _toggleLevel(String lv) {
    setState(() {
      if (_selectedLevels.contains(lv)) {
        _selectedLevels.remove(lv);
      } else {
        _selectedLevels.add(lv);
      }
      if (_selectedLevels.isEmpty) {
        _selectedLevels.add(lv); // 최소 1개는 유지
      }
      _applyFilter();
    });
  }

  void _toggleTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
      _applyFilter();
    });
  }

  void _clearTagFilter() {
    setState(() {
      _selectedTags.clear();
      _applyFilter();
    });
  }

  void _selectAllLevels() {
    setState(() {
      _selectedLevels
        ..clear()
        ..addAll(_levels);
      _applyFilter();
    });
  }

  void _selectNoLevels() {
    setState(() {
      _selectedLevels.clear();
      _applyFilter();
    });
  }

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
    setState(() {
      _loading = true;
    });

    try {
      await DebugFirestoreLogger().init();     // 안전장치
      await DebugFirestoreLogger().clearLog(); // 실제 삭제

      // 필터/검색 초기화 + info 보이게
      _searchCtrl.clear();
      _selectedTags.clear();
      _selectAllLevels();

      _all.clear();
      _filtered.clear();

      // 최신만(빠름) 재로드
      await _loadTail();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('로그가 삭제되었습니다.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('삭제 실패: $e')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _copy() async {
    final text = _filtered.reversed.map((e) => e.original ?? '').join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('클립보드에 복사되었습니다.')),
    );
  }

  Future<void> _export() async {
    final files = await DebugFirestoreLogger().getAllLogFilesExisting();
    if (files.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('내보낼 로그 파일이 없습니다.')),
      );
      return;
    }
    await Share.shareXFiles(
      files.map((f) => XFile(f.path)).toList(),
      text: 'Firestore 로그 묶음(회전 포함)',
      subject: 'Firestore 로그',
    );
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Icon(Icons.bug_report_rounded, color: cs.primary),
                      const SizedBox(width: 8),
                      Text('Firestore 로그', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                      const Spacer(),
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
                            hintText: '검색 (레벨/메시지/시간)',
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

                // 레벨 칩 (가로 스크롤, 줄바꿈 없음)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _chipButton(
                          label: '모두',
                          selected: _selectedLevels.length == _levels.length,
                          onTap: _selectAllLevels,
                          color: Colors.black87,
                        ),
                        const SizedBox(width: 8),
                        _chipButton(
                          label: '없음',
                          selected: _selectedLevels.isEmpty,
                          onTap: _selectNoLevels,
                          color: Colors.black54,
                        ),
                        const SizedBox(width: 8),
                        _levelChip('success', Colors.green),
                        const SizedBox(width: 8),
                        _levelChip('error', Colors.redAccent),
                        const SizedBox(width: 8),
                        _levelChip('called', Colors.blueAccent),
                        const SizedBox(width: 8),
                        _levelChip('warn', Colors.orange),
                        const SizedBox(width: 8),
                        _levelChip('info', cs.onSurface),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),

                // 태그 칩(이미 가로 스크롤)
                if (_allTags.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Row(
                      children: [
                        const Icon(Icons.tag, size: 16, color: Colors.black54),
                        const SizedBox(width: 6),
                        Expanded(
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              children: [
                                const SizedBox(width: 2),
                                FilterChip(
                                  label: const Text('태그 초기화'),
                                  selected: _selectedTags.isEmpty,
                                  onSelected: (_) => _clearTagFilter(),
                                ),
                                const SizedBox(width: 6),
                                ..._allTags.map(
                                      (t) => Padding(
                                    padding: const EdgeInsets.only(right: 6),
                                    child: FilterChip(
                                      label: Text('#$t'),
                                      selected: _selectedTags.contains(t),
                                      onSelected: (_) => _toggleTag(t),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 6),
                ],

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

  // UI helpers
  Widget _chipButton({
    required String label,
    required bool selected,
    required VoidCallback onTap,
    Color? color,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: (color ?? Colors.black87).withOpacity(.12),
    );
  }

  Widget _levelChip(String lv, Color color) {
    return FilterChip(
      label: Text(lv),
      selected: _selectedLevels.contains(lv),
      onSelected: (_) => _toggleLevel(lv),
      selectedColor: color.withOpacity(.12),
      checkmarkColor: color,
    );
  }

  // -------- 파서 --------
  _LogEntry? _parseLine(String line) {
    if (line.trim().isEmpty) return null;

    // JSON 우선
    try {
      final m = jsonDecode(line);
      if (m is Map<String, dynamic>) {
        final ts = (m['ts'] is String) ? DateTime.tryParse(m['ts'] as String) : null;
        final level = (m['level'] as String?)?.toLowerCase();
        final msg = (m['message'] as String?) ?? '';
        final tags = <String>{};
        final rawTags = m['tags'];
        if (rawTags is List) {
          for (final t in rawTags) {
            if (t is String && t.trim().isNotEmpty) tags.add(t.trim());
          }
        } else {
          // 메시지에서 #태그 추출(레거시 호환)
          tags.addAll(_extractHashTags(msg));
        }
        return _LogEntry(ts: ts, level: level ?? 'info', message: msg, tags: tags.toList(), original: line);
      }
    } catch (_) {
      /* not json */
    }

    // 레거시 "ISO: [LEVEL] message"
    DateTime? ts;
    String? level;
    String msg = line;
    final idx = line.indexOf(': ');
    if (idx > 0) {
      ts = DateTime.tryParse(line.substring(0, idx));
      final rest = line.substring(idx + 2);
      final l1 = rest.indexOf('['), l2 = rest.indexOf(']');
      if (l1 >= 0 && l2 > l1) {
        level = rest.substring(l1 + 1, l2).toLowerCase();
        msg = rest.substring(l2 + 1).trimLeft();
      } else {
        msg = rest;
      }
    }

    final low = msg.toLowerCase();
    level ??= low.contains('🔥') || low.contains('[error]')
        ? 'error'
        : low.contains('✅') || low.contains('[success]')
        ? 'success'
        : low.contains('[called]')
        ? 'called'
        : low.contains('warn')
        ? 'warn'
        : 'info';

    final tags = _extractHashTags(msg);

    return _LogEntry(ts: ts, level: level, message: msg, tags: tags.toList(), original: line);
  }

  Set<String> _extractHashTags(String text) {
    final re = RegExp(r'(^|\s)#([a-zA-Z0-9_\-]+)');
    return re.allMatches(text).map((m) => m.group(2)!).toSet();
  }
}

class _LogEntry {
  final DateTime? ts;
  final String? level;
  final String? message;
  final List<String> tags;
  final String? original;

  _LogEntry({this.ts, this.level, this.message, this.tags = const [], this.original});
}

class _LogTile extends StatelessWidget {
  final _LogEntry entry;
  final DateFormat fmt;

  const _LogTile({required this.entry, required this.fmt});

  @override
  Widget build(BuildContext context) {
    final color = _levelColor(context, entry.level);
    final icon = _levelIcon(entry.level);

    final date = entry.ts != null ? fmt.format(entry.ts!) : '';
    final datePart = date.split(' ');
    final d0 = datePart.isNotEmpty ? datePart.first : '';
    final d1 = datePart.length > 1 ? datePart[1] : '';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 18),
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
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (entry.tags.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          ...entry.tags.map((t) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _tagPill(t),
                          )),
                        ],
                      ),
                    ),
                  ),
                Text(
                  entry.message ?? '',
                  style: TextStyle(fontSize: 14, color: color, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tagPill(String t) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text('#$t', style: const TextStyle(fontSize: 11)),
    );
  }

  Color _levelColor(BuildContext context, String? level) {
    final cs = Theme.of(context).colorScheme;
    switch (level) {
      case 'success':
        return Colors.green;
      case 'error':
        return Colors.redAccent;
      case 'called':
        return Colors.blueAccent;
      case 'warn':
        return Colors.orange;
      default:
        return cs.onSurface;
    }
  }

  IconData _levelIcon(String? level) {
    switch (level) {
      case 'success':
        return Icons.check_circle;
      case 'error':
        return Icons.error;
      case 'called':
        return Icons.play_arrow;
      case 'warn':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info;
    }
  }
}
