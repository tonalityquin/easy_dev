// lib/screens/type_pages/parking_completed_pages/widgets/parking_status_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../states/location/location_state.dart';
import '../../../../repositories/location_repo_services/location_repository.dart';
import 'package:shared_preferences/shared_preferences.dart'; // ✅ 한도 저장/로딩

class ParkingStatusPage extends StatefulWidget {
  final bool isLocked;

  const ParkingStatusPage({super.key, required this.isLocked});

  @override
  State<ParkingStatusPage> createState() => _ParkingStatusPageState();
}

class _ParkingStatusPageState extends State<ParkingStatusPage> {
  // ✅ plateList 한도 (기본 5)
  static const _prefsKey = 'plateListLimit';
  static const int _minLimit = 0;
  static const int _maxLimit = 50;
  int _plateListLimit = 5;
  bool _prefsLoading = true;

  @override
  void initState() {
    super.initState();

    // 위치 집계 갱신
    Future.microtask(() {
      final locationRepo = context.read<LocationRepository>();
      context.read<LocationState>().updatePlateCountsFromRepository(locationRepo);
    });

    // ✅ 한도 로딩
    _loadLimitFromPrefs();
  }

  Future<void> _loadLimitFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getInt(_prefsKey) ?? 5;
      if (mounted) {
        setState(() {
          _plateListLimit = v.clamp(_minLimit, _maxLimit);
          _prefsLoading = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ plateListLimit 로딩 실패: $e');
      if (mounted) setState(() => _prefsLoading = false);
    }
  }

  Future<void> _saveLimitToPrefs(int value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_prefsKey, value);
    } catch (e) {
      debugPrint('⚠️ plateListLimit 저장 실패: $e');
    }
  }

  void _setLimit(int value) {
    final v = value.clamp(_minLimit, _maxLimit);
    if (v == _plateListLimit) return;
    setState(() => _plateListLimit = v);
    _saveLimitToPrefs(v);
  }

  void _inc() => _setLimit(_plateListLimit + 1);
  void _dec() => _setLimit(_plateListLimit - 1);

  // 🔒 시스템 뒤로가기를 가로채서 앱 종료(pop) 방지
  Future<bool> _onWillPop() async {
    // 안내 스낵바 (원치 않으면 제거 가능)
    if (mounted) {
      final messenger = ScaffoldMessenger.of(context);
      messenger.hideCurrentSnackBar();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('뒤로가기로 앱이 종료되지 않습니다. 화면 내 네비게이션을 사용하세요.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
    return false; // ✅ pop 방지 → 앱이 꺼지지 않음
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope( // ✅ 여기서 뒤로가기 차단
      onWillPop: _onWillPop,
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            Consumer<LocationState>(
              builder: (context, locationState, _) {
                if (locationState.isLoading || _prefsLoading) {
                  return const Center(child: CircularProgressIndicator());
                }

                final totalCapacity =
                locationState.locations.fold<int>(0, (sum, loc) => sum + loc.capacity);
                final occupiedCount =
                locationState.locations.fold<int>(0, (sum, loc) => sum + loc.plateCount);
                final double usageRatio =
                totalCapacity == 0 ? 0 : occupiedCount / totalCapacity;
                final String usagePercent = (usageRatio * 100).toStringAsFixed(1);

                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    const Text(
                      '📊 현재 주차 현황',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '총 $totalCapacity대 중 $occupiedCount대 주차됨',
                      style: const TextStyle(fontSize: 16),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    LinearProgressIndicator(
                      value: usageRatio,
                      backgroundColor: Colors.grey[300],
                      valueColor: AlwaysStoppedAnimation<Color>(
                        usageRatio >= 0.8 ? Colors.red : Colors.blueAccent,
                      ),
                      minHeight: 8,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '$usagePercent% 사용 중',
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.black87,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 24),

                    // ✅ plateList 진입 한도 조절 UI
                    AbsorbPointer(
                      absorbing: widget.isLocked, // 잠금 시 조작 불가
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _LimitControlCard(
                            limit: _plateListLimit,
                            min: _minLimit,
                            max: _maxLimit,
                            onMinus: _dec,
                            onPlus: _inc,
                          ),
                          const SizedBox(height: 8),
                          _LimitSlider(
                            value: _plateListLimit,
                            min: _minLimit,
                            max: _maxLimit,
                            onChanged: _setLimit,
                          ),
                          const SizedBox(height: 4),
                          const Text(
                            '※ plateList는 "입차 완료 문서 수 ≤ N"일 때만 열립니다. '
                                '설정값은 각 로컬 폰의 SharedPreferences에 저장됩니다.',
                            style: TextStyle(fontSize: 12, color: Colors.black54),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),

            // 잠금 오버레이 (터치 차단)
            if (widget.isLocked)
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {}, // 아무 반응 없음
                  child: const SizedBox.expand(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _LimitControlCard extends StatelessWidget {
  final int limit;
  final int min;
  final int max;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  const _LimitControlCard({
    required this.limit,
    required this.min,
    required this.max,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.grey[50],
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey[300]!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            const Icon(Icons.filter_list, color: Colors.black87),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('plateList 열림 기준 (문서 수 ≤ N)',
                      style: TextStyle(fontSize: 12, color: Colors.black54)),
                  const SizedBox(height: 4),
                  Text('현재 N = $limit',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
            IconButton(
              tooltip: '감소',
              onPressed: limit <= min ? null : onMinus,
              icon: const Icon(Icons.remove_circle_outline),
            ),
            IconButton(
              tooltip: '증가',
              onPressed: limit >= max ? null : onPlus,
              icon: const Icon(Icons.add_circle_outline),
            ),
          ],
        ),
      ),
    );
  }
}

class _LimitSlider extends StatelessWidget {
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  const _LimitSlider({
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Slider(
      value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
      min: min.toDouble(),
      max: max.toDouble(),
      divisions: (max - min),
      label: '$value',
      onChanged: (v) => onChanged(v.round()),
    );
  }
}
