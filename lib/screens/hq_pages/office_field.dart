import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';

import '../../../widgets/navigation/hq_mini_navigation.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../../enums/plate_type.dart';
import '../../../states/user/user_state.dart';

class OfficeField extends StatefulWidget {
  const OfficeField({super.key});

  @override
  State<OfficeField> createState() => _OfficeFieldState();
}

class _OfficeFieldState extends State<OfficeField> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AreaCount> _areaCounts = [];
  int _selectedIndex = 0;

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
        throw Exception('division 정보가 없습니다.');
      }

      final areaSnapshot = await firestore
          .collection('areas')
          .where('division', isEqualTo: division)
          .get();

      final areas = areaSnapshot.docs.map((doc) => doc['name'] as String).toList();

      List<AreaCount> results = [];

      for (final area in areas) {
        if (area == division) continue; // ✅ 본사 지역은 제외

        final counts = <PlateType, int>{};

        for (final type in PlateType.values) {
          final countSnapshot = await firestore
              .collection('plates')
              .where('area', isEqualTo: area)
              .where('type', isEqualTo: type.firestoreValue)
              .count()
              .get();

          counts[type] = countSnapshot.count ?? 0;
        }

        results.add(AreaCount(area, counts));
      }

      results.sort((a, b) => a.area.compareTo(b.area)); // 가나다순 정렬

      if (!mounted) return;
      setState(() {
        _areaCounts = results;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '데이터를 불러오지 못했습니다.\n${e.toString()}';
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async => false,
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          actions: _selectedIndex == 0
              ? [
            IconButton(
              icon: const Icon(Icons.refresh),
              tooltip: '다시 불러오기',
              onPressed: _isLoading ? null : _fetchAreaCounts,
            ),
          ]
              : null,
        ),
        body: _selectedIndex == 0
            ? _buildTodayFieldBody()
            : const Center(child: Text('해당 탭의 콘텐츠는 준비 중입니다.')),
        bottomNavigationBar: HqMiniNavigation(
          height: 56,
          iconSize: 22,
          icons: const [
            Icons.today,
            Icons.input,
            Icons.account_box,
          ],
          labels: const [
            'Today Field',
            'In&Out Doc.',
            'Account Doc.',
          ],
          onIconTapped: (index) {
            setState(() {
              _selectedIndex = index;
            });
          },
        ),
      ),
    );
  }

  Widget _buildTodayFieldBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _errorMessage!,
            style: const TextStyle(color: Colors.red, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _areaCounts.length,
      padding: const EdgeInsets.symmetric(vertical: 16),
      itemBuilder: (context, index) {
        final areaCount = _areaCounts[index];
        return _buildAreaCard(areaCount);
      },
    );
  }

  Widget _buildAreaCard(AreaCount areaCount) {
    return Card(
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
