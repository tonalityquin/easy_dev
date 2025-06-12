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
            Text('📁 Division: $division',
                style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            const Text('🏷️ Area 선택'),
            DropdownButton<String>(
              value: _selectedArea,
              hint: const Text('Area 선택'),
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
                });
              },
            ),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: (_selectedArea != null) ? _pickDate : null,
              child: const Text('날짜 선택'),
            ),
            const SizedBox(height: 16),
            if (_selectedDate != null)
              Text(
                '선택된 날짜: ${_selectedDate!.toIso8601String().split("T").first}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(child: CircularProgressIndicator())
            else if (_reportData != null)
              _buildReportSummary(_reportData!)
            else if (_selectedDate != null)
                const Text('📭 해당 날짜의 보고 내역이 없습니다.'),
          ],
        ),
      ),
    );
  }

  Widget _buildReportSummary(Map<String, dynamic> report) {
    final rawVehicleCount = report['vehicleCount'];
    final vehicleCount = rawVehicleCount is Map
        ? Map<String, dynamic>.from(rawVehicleCount)
        : null;

    final inCount = vehicleCount?['입차']?.toString() ?? '정보 없음';
    final outCount = vehicleCount?['출차']?.toString() ?? '정보 없음';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('입차 차량 수: $inCount'),
        Text('출차 차량 수: $outCount'),
      ],
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

    final url =
        'https://storage.googleapis.com/easydev-image/$division/$area/reports/ToDoReports_$dateStr.json';

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
