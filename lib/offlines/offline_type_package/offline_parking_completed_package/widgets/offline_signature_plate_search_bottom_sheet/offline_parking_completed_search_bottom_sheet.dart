import 'package:flutter/material.dart';

// ▼ SQLite
import '../../../../sql/offline_auth_db.dart';

import '../offline_parking_completed_status_bottom_sheet.dart';
import 'keypad/animated_keypad.dart';
import 'widgets/offline_parking_completed_plate_number_display.dart';
import 'widgets/offline_parking_completed_plate_search_header.dart';
import 'widgets/offline_parking_completed_search_button.dart';

// 상태 키 상수 (PlateType 의존 제거)
const String _kStatusParkingCompleted = 'parkingCompleted';
const String _kStatusParkingRequests  = 'parkingRequests';

class OfflineParkingCompletedSearchBottomSheet extends StatefulWidget {
  final void Function(String) onSearch;
  final String area;

  const OfflineParkingCompletedSearchBottomSheet({
    super.key,
    required this.onSearch,
    required this.area,
  });

  @override
  State<OfflineParkingCompletedSearchBottomSheet> createState() => _OfflineParkingCompletedSearchBottomSheetState();
}

class _OfflineParkingCompletedSearchBottomSheetState extends State<OfflineParkingCompletedSearchBottomSheet>
    with SingleTickerProviderStateMixin {
  final TextEditingController _controller = TextEditingController();

  bool _isLoading = false;
  bool _hasSearched = false;
  bool _navigating = false;

  late AnimationController _keypadController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  // SQLite 결과용 최소 모델
  final List<_PlateRow> _results = [];

  @override
  void initState() {
    super.initState();
    _keypadController = AnimationController(vsync: this, duration: const Duration(milliseconds: 500));
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _keypadController, curve: Curves.easeOut));
    _fadeAnimation = CurvedAnimation(parent: _keypadController, curve: Curves.easeIn);
    _keypadController.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    _keypadController.dispose();
    super.dispose();
  }

  bool isValidPlate(String value) {
    return RegExp(r'^\d{4}$').hasMatch(value);
  }

  Future<void> _refreshSearchResults() async {
    if (!mounted) return;
    final text = _controller.text.trim();

    setState(() {
      _isLoading = true;
    });

    try {
      final db = await OfflineAuthDb.instance.database;

      // plate_four_digit가 있으면 우선 매칭,
      // 없을 경우 plate_number의 끝 4자리로도 매칭
      final rows = await db.rawQuery(
        '''
        SELECT id, plate_number, area, location, plate_four_digit,
               COALESCE(updated_at, created_at) AS ts
          FROM ${OfflineAuthDb.tablePlates}
         WHERE area = ?
           AND COALESCE(status_type,'') = ?
           AND (
                COALESCE(plate_four_digit, '') = ?
             OR  substr(replace(plate_number,'-',''),
                        length(replace(plate_number,'-',''))-3, 4) = ?
           )
         ORDER BY ts DESC
         LIMIT 100
        ''',
        [widget.area, _kStatusParkingCompleted, text, text],
      );

      if (!mounted) return;
      setState(() {
        _results
          ..clear()
          ..addAll(rows.map((r) => _PlateRow(
            id: (r['id'] as int),
            plateNumber: (r['plate_number'] as String?)?.trim() ?? '',
            area: (r['area'] as String?)?.trim() ?? '',
            location: (r['location'] as String?)?.trim() ?? '',
            four: (r['plate_four_digit'] as String?)?.trim() ?? '',
          )));
        _hasSearched = true;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('검색 중 오류가 발생했습니다: $e')),
      );
    }
  }

  Future<void> _goBackToParkingRequestById(int plateId) async {
    final db = await OfflineAuthDb.instance.database;
    await db.update(
      OfflineAuthDb.tablePlates,
      {
        'status_type': _kStatusParkingRequests,
        'location': '미지정',
        'is_selected': 0,
        'updated_at': DateTime.now().millisecondsSinceEpoch,
      },
      where: 'id = ?',
      whereArgs: [plateId],
    );
  }

  Future<void> _deletePlateById(int plateId) async {
    final db = await OfflineAuthDb.instance.database;
    await db.delete(
      OfflineAuthDb.tablePlates,
      where: 'id = ?',
      whereArgs: [plateId],
    );
  }

  @override
  Widget build(BuildContext context) {
    final rootContext = Navigator.of(context, rootNavigator: true).context;

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: Material(
          color: Colors.transparent,
          child: DraggableScrollableSheet(
            initialChildSize: 0.7,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (context, scrollController) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey.shade300,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const ParkingCompletedPlateSearchHeader(),
                      const SizedBox(height: 24),
                      ParkingCompletedPlateNumberDisplay(controller: _controller, isValidPlate: isValidPlate),
                      const SizedBox(height: 24),

                      Builder(
                        builder: (_) {
                          final text = _controller.text;
                          final valid = isValidPlate(text);

                          if (!_hasSearched) {
                            return const SizedBox.shrink();
                          }

                          if (_isLoading) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 24),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }

                          if (!valid) {
                            return const _EmptyState(text: '유효하지 않은 번호 형식입니다. (숫자 4자리)');
                          }

                          if (_results.isEmpty) {
                            return const _EmptyState(text: '검색 결과가 없습니다.');
                          }

                          // ✅ 결과 리스트를 이 파일에서 직접 렌더링 (PlateModel 의존 제거)
                          return ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _results.length,
                            separatorBuilder: (_, __) => const Divider(height: 1),
                            itemBuilder: (_, i) {
                              final item = _results[i];
                              final title = item.plateNumber.isNotEmpty
                                  ? item.plateNumber
                                  : (item.four.isNotEmpty ? '****-${item.four}' : '미상');

                              return ListTile(
                                title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text('${item.area} • ${item.location}'),
                                trailing: const Icon(Icons.chevron_right),
                                onTap: () {
                                  if (_navigating) return;
                                  _navigating = true;

                                  Navigator.pop(context);

                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    showOfflineParkingCompletedStatusBottomSheet(
                                      context: rootContext,
                                      plateId: item.id, // ✅ plateId 전달
                                      onRequestEntry: () async {
                                        await _goBackToParkingRequestById(item.id);
                                        await _refreshSearchResults();
                                        _navigating = false;
                                      },
                                      onDelete: () async {
                                        await _deletePlateById(item.id);
                                        await _refreshSearchResults();
                                        _navigating = false;
                                      },
                                    );
                                  });
                                },
                              );
                            },
                          );
                        },
                      ),

                      Center(
                        child: TextButton(
                          onPressed: () => Navigator.pop(context),
                          child: const Text('닫기'),
                        ),
                      ),
                      const SizedBox(height: 16),

                      ValueListenableBuilder<TextEditingValue>(
                        valueListenable: _controller,
                        builder: (context, value, child) {
                          final valid = isValidPlate(value.text);
                          return ParkingCompletedSearchButton(
                            isValid: valid,
                            isLoading: _isLoading,
                            onPressed: valid
                                ? () async {
                              await _refreshSearchResults();
                              widget.onSearch(value.text);
                            }
                                : null,
                          );
                        },
                      ),

                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        bottomNavigationBar: _hasSearched
            ? const SizedBox.shrink()
            : AnimatedKeypad(
          slideAnimation: _slideAnimation,
          fadeAnimation: _fadeAnimation,
          controller: _controller,
          maxLength: 4,
          enableDigitModeSwitch: false,
          onComplete: () => setState(() {}),
          onReset: () => setState(() {
            _controller.clear();
            _hasSearched = false;
            _results.clear();
          }),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String text;
  const _EmptyState({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: Colors.redAccent, fontSize: 16),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _PlateRow {
  final int id;
  final String plateNumber;
  final String area;
  final String location;
  final String four;

  _PlateRow({
    required this.id,
    required this.plateNumber,
    required this.area,
    required this.location,
    required this.four,
  });
}
