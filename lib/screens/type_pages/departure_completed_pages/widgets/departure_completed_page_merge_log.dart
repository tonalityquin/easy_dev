import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FontFeature; // 숫자 고정폭(탭형)

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/storage/v1.dart';
import 'package:googleapis_auth/auth_io.dart';

// ⬇️ 사진 다이얼로그(경로는 프로젝트 구조에 맞게 조정하세요)
import 'plate_image_dialog.dart';

/// === GCS 설정 ===
const String kBucketName = 'easydev-image';
const String kServiceAccountPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

/// === 내부 레이아웃 상수 ===
const double _kRowHeight = 56.0;
const double _kTimeColWidth = 84.0;  // HH:mm:ss 고정폭
const double _kChevronWidth = 28.0;  // 펼침 아이콘

/// === GCS 헬퍼 ===
class _GcsHelper {
  Future<List<String>> listObjects(String prefix) async {
    final credentialsJson = await rootBundle.loadString(kServiceAccountPath);
    final accountCredentials = ServiceAccountCredentials.fromJson(credentialsJson);
    final client = await clientViaServiceAccount(
      accountCredentials,
      [StorageApi.devstorageFullControlScope],
    );
    try {
      final storage = StorageApi(client);
      final res = await storage.objects.list(kBucketName, prefix: prefix);
      final items = res.items ?? const <Object>[];
      return items.where((o) => o.name != null).map((o) => o.name!).toList();
    } finally {
      client.close();
    }
  }

  Future<Map<String, dynamic>> loadJsonByObjectName(String objectName) async {
    final url = Uri.parse('https://storage.googleapis.com/$kBucketName/$objectName');
    final httpClient = HttpClient();
    try {
      final req = await httpClient.getUrl(url);
      final resp = await req.close();
      final text = await resp.transform(utf8.decoder).join();
      return jsonDecode(text) as Map<String, dynamic>;
    } finally {
      httpClient.close(force: true);
    }
  }
}

/// === 위젯 ===
class MergedLogSection extends StatefulWidget {
  final List<Map<String, dynamic>> mergedLogs; // 시그니처 호환용(내부 미사용)
  final String division;
  final String area;

  const MergedLogSection({
    super.key,
    this.mergedLogs = const <Map<String, dynamic>>[],
    required this.division,
    required this.area,
  });

  @override
  State<MergedLogSection> createState() => _MergedLogSectionState();
}

class _MergedLogSectionState extends State<MergedLogSection> {
  // 날짜 범위(기본: 최근 7일)
  DateTime _start = DateTime.now().subtract(const Duration(days: 6));
  DateTime _end = DateTime.now();

  // 상태
  bool _loading = false;
  String? _error;

  final List<_DayBundle> _days = [];
  final Set<String> _expandedDocIds = {};

  // 검색
  final _tailCtrl = TextEditingController();
  List<_SearchHit> _hits = [];
  _SearchHit? _selectedHit;

  // 내부 페이지(0: 목록, 1: 검색)
  final PageController _pageController = PageController(initialPage: 0);
  int _currentPage = 0;

  @override
  void dispose() {
    _tailCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  // ===== 유틸 =====
  DateTime _asDateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
  String _two(int n) => n.toString().padLeft(2, '0');
  String _yyyymmdd(DateTime d) => '${d.year}-${_two(d.month)}-${_two(d.day)}';
  String _mmdd(DateTime d) => '${_two(d.month)}-${_two(d.day)}';
  bool _validTail(String s) => RegExp(r'^\d{4}$').hasMatch(s);
  String _digitsOnly(String s) => s.replaceAll(RegExp(r'\D'), '');

  DateTime? _parseTs(dynamic ts) {
    if (ts == null) return null;
    if (ts is DateTime) return ts.toLocal();
    if (ts is Timestamp) return ts.toDate().toLocal();
    if (ts is int) {
      if (ts > 100000000000) return DateTime.fromMillisecondsSinceEpoch(ts).toLocal();
      return DateTime.fromMillisecondsSinceEpoch(ts * 1000).toLocal();
    }
    if (ts is String) return DateTime.tryParse(ts)?.toLocal();
    return null;
  }

  String _fmtDateTime(DateTime? dt) {
    if (dt == null) return '--';
    return '${dt.year}-${_two(dt.month)}-${_two(dt.day)} ${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '--';
    return '${_two(dt.hour)}:${_two(dt.minute)}:${_two(dt.second)}';
  }

  String _fmtWon(num? n) {
    if (n == null) return '—';
    final s = n.round().toString();
    final buf = StringBuffer();
    for (int i = 0; i < s.length; i++) {
      if (i != 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return '₩$buf';
  }

  IconData _actionIcon(String action) {
    if (action.contains('사전 정산')) return Icons.receipt_long;
    if (action.contains('입차 완료')) return Icons.local_parking;
    if (action.contains('출차')) return Icons.exit_to_app;
    if (action.contains('취소')) return Icons.undo;
    if (action.contains('생성')) return Icons.add_circle_outline;
    return Icons.history;
  }

  Color _actionColor(String action) {
    if (action.contains('사전 정산')) return Colors.teal;
    if (action.contains('출차')) return Colors.orange;
    if (action.contains('취소')) return Colors.redAccent;
    if (action.contains('생성')) return Colors.indigo;
    return Colors.blueGrey;
  }

  // ===== 날짜 선택 =====
  Future<void> _pickStart() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _asDateOnly(_start),
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null && !d.isAfter(_end)) setState(() => _start = _asDateOnly(d));
  }

  Future<void> _pickEnd() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _asDateOnly(_end),
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 1)),
    );
    if (d != null && !d.isBefore(_start)) setState(() => _end = _asDateOnly(d));
  }

  // ===== 사진 다이얼로그 열기 =====
  void _openPlateImageDialog(String plateNumber) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: "사진 보기",
      transitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => PlateImageDialog(plateNumber: plateNumber),
    );
  }

  // ===== GCS 로드 =====
  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _days.clear();
      _hits.clear();
      _selectedHit = null;
      _expandedDocIds.clear();
    });

    try {
      final gcs = _GcsHelper();
      final prefix = '${widget.division}/${widget.area}/logs/';
      final names = await gcs.listObjects(prefix);

      final wantedSuffix = <String>{};
      for (DateTime d = _start; !d.isAfter(_end); d = d.add(const Duration(days: 1))) {
        wantedSuffix.add('_ToDoLogs_${_yyyymmdd(d)}.json');
      }
      final inRange = names.where((n) => wantedSuffix.any((suf) => n.endsWith(suf))).toList()..sort();

      for (final objectName in inRange) {
        final m = RegExp(r'_ToDoLogs_(\d{4}-\d{2}-\d{2})\.json$').firstMatch(objectName);
        final dateStr = m?.group(1) ?? 'Unknown';

        final json = await gcs.loadJsonByObjectName(objectName);
        final List items = (json['items'] as List?) ?? (json['data'] as List?) ?? const [];

        final docs = <_DocBundle>[];
        for (final raw in items) {
          if (raw is! Map) continue;
          final map = Map<String, dynamic>.from(raw);

          final docId = (map['docId'] ?? '').toString();
          final plate = (map['plateNumber'] ?? docId.split('_').first).toString();

          final logs =
          ((map['logs'] as List?) ?? const []).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();

          // 로그는 오름차순(과거->최근)으로
          logs.sort((a, b) {
            final at = _parseTs(a['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            final bt = _parseTs(b['timestamp']) ?? DateTime.fromMillisecondsSinceEpoch(0);
            return at.compareTo(bt);
          });

          docs.add(_DocBundle(docId: docId, plateNumber: plate, logs: logs));
        }

        // 문서 정렬: 각 문서의 "마지막 로그 시간" 기준 **오름차순**
        docs.sort((a, b) {
          final at = a.logs.isNotEmpty ? _parseTs(a.logs.last['timestamp']) : null;
          final bt = b.logs.isNotEmpty ? _parseTs(b.logs.last['timestamp']) : null;
          return (at ?? DateTime.fromMillisecondsSinceEpoch(0))
              .compareTo(bt ?? DateTime.fromMillisecondsSinceEpoch(0));
        });

        _days.add(_DayBundle(dateStr: dateStr, docs: docs));
      }

      setState(() => _loading = false);
    } catch (e) {
      setState(() {
        _loading = false;
        _error = '로드 실패: $e';
      });
    }
  }

  // ===== 검색 =====
  Future<void> _search() async {
    final q = _tailCtrl.text.trim();
    if (!_validTail(q)) {
      setState(() {
        _error = '번호판 4자리를 입력하세요.';
        _hits = [];
        _selectedHit = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _hits = [];
      _selectedHit = null;
    });

    final hits = <_SearchHit>[];
    for (final day in _days) {
      for (final doc in day.docs) {
        final d = _digitsOnly(doc.plateNumber.isNotEmpty ? doc.plateNumber : doc.docId);
        if (d.length >= 4 && d.substring(d.length - 4) == q) {
          hits.add(_SearchHit(dateStr: day.dateStr, doc: doc));
        }
      }
    }
    setState(() => _hits = hits);

    if (_currentPage != 1) {
      _pageController.animateToPage(1, duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  // ===== UI =====
  @override
  Widget build(BuildContext context) {
    final hasData = !_loading && _days.isNotEmpty;
    final mono = const TextStyle(fontFeatures: [FontFeature.tabularFigures()]); // 시간 숫자 정렬

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 상단 컨트롤: 한 줄 고정
        LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 420;
            final startLabel = narrow ? '시작 ${_mmdd(_start)}' : '시작: ${_yyyymmdd(_start)}';
            final endLabel   = narrow ? '종료 ${_mmdd(_end)}'   : '종료: ${_yyyymmdd(_end)}';

            return SizedBox(
              height: 44,
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: OutlinedButton(
                      onPressed: _pickStart,
                      child: FittedBox(child: Text(startLabel, maxLines: 1)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 3,
                    child: OutlinedButton(
                      onPressed: _pickEnd,
                      child: FittedBox(child: Text(endLabel, maxLines: 1)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _loading ? null : _load,
                      icon: _loading
                          ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                          : const Icon(Icons.download),
                      label: const FittedBox(child: Text('불러오기', maxLines: 1)),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 44,
                    child: IconButton(
                      tooltip: _currentPage == 0 ? '검색 화면으로' : '목록 화면으로',
                      onPressed: () {
                        final next = (_currentPage == 0) ? 1 : 0;
                        _pageController.animateToPage(next,
                            duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
                      },
                      icon: Icon(_currentPage == 0 ? Icons.search : Icons.list),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
            );
          },
        ),

        if (_error != null) ...[
          const SizedBox(height: 8),
          Text(_error!, style: const TextStyle(color: Colors.red)),
        ],
        const SizedBox(height: 8),

        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : !hasData
              ? const Center(child: Text('기간을 설정하고 불러오기를 눌러주세요.'))
              : PageView(
            controller: _pageController,
            onPageChanged: (i) => setState(() => _currentPage = i),
            children: [
              // 페이지 0: 날짜/문서 목록 (시간 + 번호판만)
              Scrollbar(
                child: ListView.builder(
                  padding: const EdgeInsets.only(bottom: 12),
                  itemCount: _days.length,
                  itemBuilder: (_, i) {
                    final day = _days[i];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // 날짜 헤더 + 컬럼 헤더
                        Container(
                          color: Colors.grey.shade200,
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(day.dateStr,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              // 컬럼 라벨 (시간 | 번호판)
                              SizedBox(
                                height: 24,
                                child: Row(
                                  children: const [
                                    SizedBox(
                                      width: _kTimeColWidth,
                                      child: Text(
                                        '시간',
                                        style: TextStyle(fontSize: 12, color: Colors.black54),
                                      ),
                                    ),
                                    SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '번호판',
                                        style: TextStyle(fontSize: 12, color: Colors.black54),
                                        textAlign: TextAlign.center,
                                      ),
                                    ),
                                    SizedBox(width: _kChevronWidth),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),

                        // 데이터 행들 (시간 + 번호판)
                        ...day.docs.map((doc) {
                          final expanded = _expandedDocIds.contains(doc.docId);
                          final lastTs =
                          doc.logs.isNotEmpty ? _parseTs(doc.logs.last['timestamp']) : null;

                          return Column(
                            children: [
                              InkWell(
                                onTap: () {
                                  setState(() {
                                    if (expanded) {
                                      _expandedDocIds.remove(doc.docId);
                                    } else {
                                      _expandedDocIds.add(doc.docId);
                                    }
                                  });
                                },
                                child: Container(
                                  height: _kRowHeight,
                                  padding: const EdgeInsets.symmetric(horizontal: 12),
                                  decoration: const BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(color: Color(0xFFE0E0E0)),
                                    ),
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.center,
                                    children: [
                                      // 시간(고정폭)
                                      SizedBox(
                                        width: _kTimeColWidth,
                                        child: Text(
                                          _fmtTime(lastTs),
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.clip,
                                          textAlign: TextAlign.center,
                                          style: mono.copyWith(fontSize: 15),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      // 번호판
                                      Expanded(
                                        child: Text(
                                          doc.plateNumber.isNotEmpty
                                              ? doc.plateNumber
                                              : doc.docId,
                                          maxLines: 1,
                                          softWrap: false,
                                          overflow: TextOverflow.ellipsis,
                                          textAlign: TextAlign.center,
                                          style: const TextStyle(fontSize: 16),
                                        ),
                                      ),
                                      // 펼침 아이콘(상태 반영)
                                      SizedBox(
                                        width: _kChevronWidth,
                                        child: Icon(
                                          expanded ? Icons.expand_less : Icons.expand_more,
                                          size: 20,
                                          color: Colors.black54,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),

                              // 펼침부: 로그 상세(중첩 스크롤 방지 위해 비스크롤)
                              if (expanded)
                                _buildLogsDetail(
                                  doc.logs,
                                  plateNumber: doc.plateNumber,
                                  scrollable: false,
                                ),
                            ],
                          );
                        }),
                      ],
                    );
                  },
                ),
              ),

              // 페이지 1: 검색
              _buildSearchPage(),
            ],
          ),
        ),

        // 페이지 인디케이터
        Padding(
          padding: const EdgeInsets.only(top: 6.0),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _Dot(active: _currentPage == 0),
              const SizedBox(width: 6),
              _Dot(active: _currentPage == 1),
            ],
          ),
        ),
      ],
    );
  }

  // ===== 검색 페이지 구성 =====
  Widget _buildSearchPage() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 검색 입력줄
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _tailCtrl,
                maxLength: 4,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  counterText: '',
                  labelText: '번호판 4자리',
                  hintText: '예) 4444',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => _search(),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _loading || _days.isEmpty ? null : _search,
              icon: const Icon(Icons.search),
              label: const Text('검색'),
            ),
          ],
        ),
        const SizedBox(height: 8),

        // 결과/상세
        Expanded(
          child: _hits.isEmpty
              ? const Center(child: Text('검색 결과가 없습니다.'))
              : (_selectedHit == null
          // 결과 리스트 화면
              ? ListView.separated(
            itemCount: _hits.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (_, i) {
              final h = _hits[i];
              final lastTs = h.doc.logs.isNotEmpty ? _parseTs(h.doc.logs.last['timestamp']) : null;
              return ListTile(
                dense: true,
                title: Text(h.doc.docId),
                subtitle: Text('${h.dateStr} • ${h.doc.plateNumber}'),
                trailing: Text(_fmtTime(lastTs), style: const TextStyle(fontSize: 12)),
                onTap: () => setState(() => _selectedHit = h),
              );
            },
          )
          // 선택된 문서 상세 화면(전체 높이, 스크롤 가능, 해제 + 사진 버튼)
              : Column(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                color: Colors.grey.shade100,
                child: Row(
                  children: [
                    IconButton(
                      tooltip: '선택 해제',
                      onPressed: () => setState(() => _selectedHit = null),
                      icon: const Icon(Icons.close),
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _selectedHit!.doc.docId,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${_selectedHit!.dateStr} • ${_selectedHit!.doc.plateNumber}',
                            style: const TextStyle(fontSize: 12, color: Colors.black54),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // ⬇️ 사진 버튼 추가: 선택된 번호판의 사진 보기
                    ElevatedButton.icon(
                      onPressed: () {
                        final plate = _selectedHit!.doc.plateNumber.isNotEmpty
                            ? _selectedHit!.doc.plateNumber
                            : _selectedHit!.doc.docId.split('_').first;
                        _openPlateImageDialog(plate);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.grey.shade100,
                        foregroundColor: Colors.black87,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      icon: const Icon(Icons.photo, size: 18),
                      label: const Text('사진', style: TextStyle(fontSize: 13)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 6),
              // 전체 영역을 차지하면서 세로 스크롤 가능
              Expanded(
                child: _buildLogsDetail(
                  _selectedHit!.doc.logs,
                  plateNumber: _selectedHit!.doc.plateNumber,
                  scrollable: true, // ⬅️ 스크롤 활성화
                ),
              ),
            ],
          )),
        ),
      ],
    );
  }

  /// 로그 상세 리스트
  ///  - 일반 목록의 펼침부에서는 scrollable=false (중첩 스크롤 방지)
  ///  - 검색 상세 화면에서는 scrollable=true (세로 스크롤 허용)
  Widget _buildLogsDetail(
      List<Map<String, dynamic>> logs, {
        required String plateNumber,
        bool scrollable = false,
      }) {
    if (logs.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(12),
        child: Text('로그가 없습니다.'),
      );
    }

    final listView = ListView.separated(
      // 스크롤 옵션 분기
      physics: scrollable ? const AlwaysScrollableScrollPhysics() : const NeverScrollableScrollPhysics(),
      shrinkWrap: !scrollable,
      itemCount: logs.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final e = logs[i];
        final action = (e['action'] ?? '-').toString();
        final from = (e['from'] ?? '').toString();
        final to = (e['to'] ?? '').toString();
        final by = (e['performedBy'] ?? '').toString();
        final ts = _parseTs(e['timestamp']);
        final tsText = _fmtDateTime(ts);

        final feeNum = (e['lockedFee'] ?? e['lockedFeeAmount']);
        final fee = (feeNum is num) ? _fmtWon(feeNum) : null;
        final pay =
        (e['paymentMethod']?.toString().trim().isNotEmpty ?? false) ? e['paymentMethod'].toString() : null;
        final reason =
        (e['reason']?.toString().trim().isNotEmpty ?? false) ? e['reason'].toString() : null;

        final color = _actionColor(action);

        return ListTile(
          dense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          leading: Icon(_actionIcon(action), color: color),
          title: Text(action, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (from.isNotEmpty || to.isNotEmpty) Text('$from → $to'),
              if (by.isNotEmpty) const SizedBox(height: 2),
              if (by.isNotEmpty) const Text('담당자:', style: TextStyle(fontSize: 12)),
              if (by.isNotEmpty) Text(by, style: const TextStyle(fontSize: 12)),
              if (fee != null || pay != null || reason != null) const SizedBox(height: 2),
              if (fee != null) Text('확정요금: $fee', style: const TextStyle(fontSize: 12)),
              if (pay != null) Text('결제수단: $pay', style: const TextStyle(fontSize: 12)),
              if (reason != null) Text('사유: $reason', style: const TextStyle(fontSize: 12)),
            ],
          ),
          trailing: Text(tsText, style: const TextStyle(fontSize: 12)),
          isThreeLine: true,
        );
      },
    );

    return Container(
      color: Colors.grey.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      child: listView,
    );
  }
}

// ===== 내부 모델 =====
class _DayBundle {
  final String dateStr;
  final List<_DocBundle> docs;
  _DayBundle({required this.dateStr, required this.docs});
}

class _DocBundle {
  final String docId;
  final String plateNumber;
  final List<Map<String, dynamic>> logs; // 시간 오름차순
  _DocBundle({required this.docId, required this.plateNumber, required this.logs});
}

class _SearchHit {
  final String dateStr;
  final _DocBundle doc;
  _SearchHit({required this.dateStr, required this.doc});
}

class _Dot extends StatelessWidget {
  final bool active;
  const _Dot({required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: active ? 20 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: active ? Colors.black87 : Colors.black26,
        borderRadius: BorderRadius.circular(999),
      ),
    );
  }
}
