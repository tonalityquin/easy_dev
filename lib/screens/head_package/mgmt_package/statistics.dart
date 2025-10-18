// lib/screens/head_package/mgmt_package/statistics.dart
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';

// ✅ GCS 목록 조회용 (중앙 OAuth 세션 사용)
import 'package:googleapis/storage/v1.dart' as gcs;

// ✅ 중앙 인증 세션만 사용 (최초 1회 로그인 후 재사용)
import '../../../utils/google_auth_session.dart';

import '../../../states/area/area_state.dart';
import '../../../states/user/user_state.dart';
import 'statistics_chart_page.dart';
import '../../../utils/snackbar_helper.dart';

/// ===== GCS 설정 =====
const String _kBucketName = 'easydev-image';

/// 간단 GCS 헬퍼: prefix 하위 객체 목록 조회 (중앙 OAuth 기반)
class _GcsHelper {
  Future<List<gcs.Object>> listObjects(String prefix) async {
    // 중앙 세션에서 AuthClient 획득 → StorageApi 생성
    final client = await GoogleAuthSession.instance.client();
    final storage = gcs.StorageApi(client);

    // 페이지네이션 안전 처리
    final List<gcs.Object> all = [];
    String? pageToken;
    do {
      final res = await storage.objects.list(
        _kBucketName,
        prefix: prefix,
        pageToken: pageToken,
      );
      if (res.items != null) all.addAll(res.items!);
      pageToken = res.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);

    return all;
  }
}

class Statistics extends StatefulWidget {
  const Statistics({super.key});

  @override
  State<Statistics> createState() => _StatisticsState();
}

class _StatisticsState extends State<Statistics> {
  String? _selectedArea;
  DateTime? _selectedDate;
  Map<String, dynamic>? _reportData;
  bool _isLoading = false;
  final List<Map<String, dynamic>> _savedReports = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final userDivision = context.read<UserState>().user?.divisions.first ?? '';
      context.read<AreaState>().loadAreasForDivision(userDivision);
    });
  }

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final division = areaState.currentDivision;
    final areaList = areaState.divisionAreaMap[division] ?? [];

    return Scaffold(
      appBar: AppBar(
        title: const Text('입·출차 통계'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('📁 Division: $division',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 20),
              const Text('🏷️ Area 선택'),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                value: _selectedArea,
                hint: const Text('지역을 선택하세요'),
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                ),
                items: areaList.map((area) {
                  return DropdownMenuItem<String>(
                    value: area,
                    child: Text(area),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() {
                    _selectedArea = val;
                    _reportData = null;
                    _selectedDate = null;
                  });
                },
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  ElevatedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text(''),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onPressed: _savedReports.isNotEmpty
                        ? () {
                      setState(() {
                        _savedReports.clear();
                      });
                      showSuccessSnackbar(context, "🗑️ 보관된 통계가 초기화되었습니다.");
                    }
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.calendar_today),
                      label: const Text(''),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white,
                        foregroundColor: Colors.black87,
                        side: const BorderSide(color: Colors.grey),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                      onPressed: (_selectedArea != null) ? _pickDate : null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    icon: const Icon(Icons.bar_chart),
                    label: const Text(''),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.white,
                      foregroundColor: Colors.black87,
                      side: const BorderSide(color: Colors.grey),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    ),
                    onPressed: _savedReports.isNotEmpty ? _showGraph : null,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              if (_selectedDate != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '🗓 선택 날짜: ${_selectedDate!.toIso8601String().split("T").first}',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                    ),
                    if (_savedReports
                        .any((r) => r['date'] == _selectedDate!.toIso8601String().split("T").first))
                      const Padding(
                        padding: EdgeInsets.only(top: 6),
                        child: Text(
                          '📌 이 날짜의 통계는 이미 보관되었습니다.',
                          style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                        ),
                      ),
                  ],
                ),
              const SizedBox(height: 20),
              if (_isLoading)
                const Center(child: CircularProgressIndicator())
              else if (_reportData != null)
                _buildReportCard(_reportData!)
              else if (_selectedDate != null)
                  const Text('👭 해당 날짜의 보고 내용이 없습니다.', style: TextStyle(color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    int? asInt(dynamic v) {
      if (v is num) return v.toInt();
      if (v is String) return int.tryParse(v);
      return null;
    }

    final vc = (report['vehicleCount'] is Map)
        ? (report['vehicleCount'] as Map).cast<String, dynamic>()
        : null;
    final inCount = asInt(report['vehicleInput'] ?? vc?['vehicleInput']);
    final outCount = asInt(report['vehicleOutput'] ?? vc?['vehicleOutput']);
    final lockedFee = asInt(report['totalLockedFee'] ?? vc?['totalLockedFee']);

    final inText = inCount?.toString() ?? '정보 없음';
    final outText = outCount?.toString() ?? '정보 없음';
    final feeText = lockedFee?.toString() ?? '정보 없음';

    final dateStr = _selectedDate?.toIso8601String().split('T').first ?? '날짜 없음';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('📊 통계 결과', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('🗓 날짜: $dateStr', style: const TextStyle(color: Colors.grey)),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🚗 입차 차량 수', style: TextStyle(fontSize: 15)),
                Text(inText, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🚙 출차 차량 수', style: TextStyle(fontSize: 15)),
                Text(outText, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🔒 정산 금액', style: TextStyle(fontSize: 15)),
                Text('₩$feeText', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                icon: const Icon(Icons.save),
                label: const Text('보관'),
                onPressed: () {
                  if (_selectedDate != null) {
                    final dateStr =
                        _selectedDate!.toIso8601String().split('T').first;
                    final already =
                    _savedReports.any((r) => r['date'] == dateStr);
                    if (already) {
                      showSelectedSnackbar(context, "ℹ️ 이미 보관된 날짜입니다.");
                      return;
                    }
                    setState(() {
                      _savedReports.add({
                        'date': dateStr,
                        '입차': inCount ?? 0,
                        '출차': outCount ?? 0,
                        '정산금': lockedFee ?? 0,
                      });
                    });
                    showSuccessSnackbar(context, "✅ 통계가 보관되었습니다.");
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2023, 1, 1),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      setState(() {
        _selectedDate = picked;
        _reportData = null;
        _isLoading = true;
      });

      await _fetchReportData(picked);

      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// 업로드 포맷(랜덤 prefix + `_ToDoReports_YYYY-MM-DD.json`)에 맞춰
  /// 해당 날짜 파일명을 GCS 목록에서 찾아 공개 URL로 GET
  Future<void> _fetchReportData(DateTime date) async {
    final dateStr = date.toIso8601String().split('T').first;
    final division = context.read<AreaState>().currentDivision;
    final area = _selectedArea ?? context.read<AreaState>().currentArea;

    final prefix = '$division/$area/reports/';
    try {
      // 1) GCS 리스트에서 날짜 매칭 파일 찾기 (중앙 OAuth)
      final helper = _GcsHelper();
      final items = await helper.listObjects(prefix);

      // `_ToDoReports_YYYY-MM-DD.json`으로 끝나는 항목 필터
      final suffix = '_ToDoReports_$dateStr.json';
      final candidates =
      items.where((o) => (o.name ?? '').endsWith(suffix)).toList();

      if (candidates.isEmpty) {
        setState(() => _reportData = null);
        return;
      }

      // 최신(updated) 기준으로 정렬 후 마지막 선택
      candidates.sort((a, b) {
        final au = a.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bu = b.updated ?? DateTime.fromMillisecondsSinceEpoch(0);
        return au.compareTo(bu);
      });
      final target = candidates.last.name!;

      // 2) 공개 URL로 JSON 다운로드 (버킷이 퍼블릭인 경우)
      final bust = DateTime.now().millisecondsSinceEpoch;
      final url = 'https://storage.googleapis.com/$_kBucketName/$target?ts=$bust';

      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _reportData =
          (data is Map<String, dynamic>) ? data : <String, dynamic>{};
        });
      } else {
        setState(() => _reportData = null);
      }
    } catch (e) {
      setState(() => _reportData = null);
    }
  }

  void _showGraph() {
    final Map<DateTime, Map<String, int>> parsedData = {};
    for (final report in _savedReports) {
      final date = DateTime.tryParse(report['date']);
      if (date != null) {
        parsedData[date] = {
          'vehicleInput': (report['입차'] as int),
          'vehicleOutput': (report['출차'] as int),
          'totalLockedFee': (report['정산금'] as int),
        };
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StatisticsChartPage(reportDataMap: parsedData),
      ),
    );
  }
}
