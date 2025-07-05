import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../states/user/user_state.dart';
import '../../../utils/firestore_logger.dart';
import 'area_detail_screen.dart'; // 상세 페이지 import

class Field extends StatefulWidget {
  const Field({super.key});

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AreaCount> _areaCounts = [];

  @override
  void initState() {
    super.initState();
    _fetchAreaCounts();
  }

  Future<void> _fetchAreaCounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final firestore = FirebaseFirestore.instance;
      final userState = context.read<UserState>();
      final division = userState.user?.divisions.first;

      if (division == null || division.isEmpty) {
        await FirestoreLogger().log(
          '⚠️ division 정보 없음. _fetchAreaCounts() 중단',
          level: 'error',
        );
        throw Exception('division 정보가 없습니다.');
      }

      await FirestoreLogger().log(
        '✅ Firestore areas 쿼리 시작 division=$division',
        level: 'called',
      );

      final areaSnapshot = await firestore.collection('areas').where('division', isEqualTo: division).get();

      final areas = areaSnapshot.docs.map((doc) => doc['name'] as String).toList();

      await FirestoreLogger().log(
        '✅ Firestore areas 쿼리 완료 (총 ${areas.length}개)',
        level: 'success',
      );

      List<AreaCount> results = [];

      for (final area in areas) {
        if (area == division) continue;

        final counts = <PlateType, int>{};

        for (final type in PlateType.values) {
          final countSnapshot = await firestore
              .collection('plates')
              .where('area', isEqualTo: area)
              .where('type', isEqualTo: type.firestoreValue)
              .count()
              .get();

          counts[type] = countSnapshot.count ?? 0;

          await FirestoreLogger().log(
            '📊 area=$area type=${type.firestoreValue} count=${counts[type]}',
            level: 'info',
          );
        }

        results.add(AreaCount(area, counts));
      }

      results.sort((a, b) => a.area.compareTo(b.area));

      if (!mounted) return;
      setState(() {
        _areaCounts = results;
        _isLoading = false;
      });

      await FirestoreLogger().log(
        '✅ areaCounts 데이터 로드 및 정렬 완료 (${results.length}개)',
        level: 'success',
      );
    } catch (e) {
      await FirestoreLogger().log(
        '❌ _fetchAreaCounts() 오류: $e',
        level: 'error',
      );
      if (!mounted) return;
      setState(() {
        _errorMessage = '데이터를 불러오지 못했습니다.\n${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
          title: const Text('필드 별 업무/근퇴 현황'),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _errorMessage!,
                      style: const TextStyle(color: Colors.red, fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _fetchAreaCounts,
                  child: ListView.builder(
                    itemCount: _areaCounts.length,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    itemBuilder: (context, index) {
                      final areaCount = _areaCounts[index];
                      return _buildAreaCard(areaCount);
                    },
                  ),
                ),
    );
  }

  Widget _buildAreaCard(AreaCount areaCount) {
    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => AreaDetailScreen(areaName: areaCount.area),
          ),
        );
      },
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 3,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📍 ${areaCount.area}',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: PlateType.values.map((type) {
                  final count = areaCount.counts[type] ?? 0;
                  return Column(
                    children: [
                      Text(
                        type.label,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            count > 0 ? Icons.circle : Icons.remove_circle_outline,
                            color: _getColorByCount(count),
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$count건',
                            style: TextStyle(
                              fontSize: 14,
                              color: _getColorByCount(count),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ],
                  );
                }).toList(),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getColorByCount(int count) {
    if (count == 0) return Colors.grey;
    if (count < 3) return Colors.blue;
    if (count < 5) return Colors.orange;
    return Colors.redAccent;
  }
}

class AreaCount {
  final String area;
  final Map<PlateType, int> counts;

  AreaCount(this.area, this.counts);
}
