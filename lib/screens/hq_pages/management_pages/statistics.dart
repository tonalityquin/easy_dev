import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:provider/provider.dart';
import '../../../states/area/area_state.dart';

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<AreaState>().loadAllDivisionsAndAreas();
    });
  }

  @override
  Widget build(BuildContext context) {
    final areaState = context.watch<AreaState>();
    final division = areaState.currentDivision;
    final areaList = areaState.divisionAreaMap[division] ?? [];

    _selectedArea ??= areaState.currentArea;

    return Scaffold(
      appBar: AppBar(title: const Text('입·출차 통계')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('📁 Division: $division', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 20),
            const Text('🏷️ Area 선택'),
            DropdownButtonFormField<String>(
              value: _selectedArea,
              decoration: const InputDecoration(border: OutlineInputBorder()),
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
            ElevatedButton.icon(
              icon: const Icon(Icons.calendar_today),
              label: const Text('날짜 선택'),
              onPressed: (_selectedArea != null) ? _pickDate : null,
            ),
            const SizedBox(height: 20),
            if (_selectedDate != null)
              Text(
                '📅 선택 날짜: ${_selectedDate!.toIso8601String().split("T").first}',
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
              ),
            const SizedBox(height: 20),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_reportData != null)
              _buildReportCard(_reportData!)
            else if (_selectedDate != null)
              const Text(
                '📭 해당 날짜의 보고 내역이 없습니다.',
                style: TextStyle(color: Colors.grey),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildReportCard(Map<String, dynamic> report) {
    final vehicleCount = report['vehicleCount'] as Map<String, dynamic>?;
    final inCount = vehicleCount?['입차']?.toString() ?? '정보 없음';
    final outCount = vehicleCount?['출차']?.toString() ?? '정보 없음';

    // 선택된 날짜 문자열
    final dateStr = _selectedDate?.toIso8601String().split('T').first ?? '날짜 없음';

    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '📊 통계 결과',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              '📅 날짜: $dateStr',
              style: const TextStyle(color: Colors.grey),
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🚗 입차 차량 수', style: TextStyle(fontSize: 15)),
                Text(inCount, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('🚙 출차 차량 수', style: TextStyle(fontSize: 15)),
                Text(outCount, style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
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

      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _fetchReportData(DateTime date) async {
    final dateStr = date.toIso8601String().split('T').first;
    final division = context.read<AreaState>().currentDivision;
    final area = _selectedArea ?? context.read<AreaState>().currentArea;

    final url = 'https://storage.googleapis.com/easydev-image/$division/$area/reports/ToDoReports_$dateStr.json';

    try {
      final response = await http.get(Uri.parse(url));

      debugPrint('🌐 요청 URL: $url');
      debugPrint('📦 응답 상태: ${response.statusCode}');
      debugPrint('📥 응답 본문: ${response.body}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          _reportData = data;
        });
      } else {
        debugPrint("📭 보고서 없음: $dateStr");
        setState(() {
          _reportData = null;
        });
      }
    } catch (e) {
      debugPrint("❌ 오류: $e");
      setState(() {
        _reportData = null;
      });
    }
  }
}
