// File: lib/screens/field/field.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../enums/plate_type.dart';
import '../../../repositories/area_counts_repository.dart';
import '../../../states/user/user_state.dart';
import 'area_detail_screen.dart';

class Field extends StatefulWidget {
  const Field({super.key});

  @override
  State<Field> createState() => _FieldState();
}

class _FieldState extends State<Field> {
  bool _isLoading = true;
  String? _errorMessage;
  List<AreaCount> _areaCounts = [];
  late final AreaCountsRepository _repo;

  @override
  void initState() {
    super.initState();
    _repo = AreaCountsRepository();
    _fetchAreaCounts();
  }

  Future<void> _fetchAreaCounts() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final userState = context.read<UserState>();
      final division = userState.user?.divisions.first;

      if (division == null || division.isEmpty) {
        throw Exception('division 정보가 없습니다.');
      }

      final results = await _repo.fetchAreaCountsByDivision(division);

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('필드 별 업무/근퇴 현황'),
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
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
        showModalBottomSheet(
          backgroundColor: Colors.white,
          context: context,
          isScrollControlled: true,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (context) {
            final height = MediaQuery.of(context).size.height;
            return Container(
              height: height * 0.5,
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              child: AreaDetailScreen(areaName: areaCount.area),
            );
          },
        );
      },
      child: Card(
        color: Colors.white,
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
                      Text(type.label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
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
