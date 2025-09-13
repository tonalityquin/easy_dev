// lib/screens/type_pages/parking_completed_page.dart
//
// 변경 요약 👇
// - StatusMappingHelper에서 설정한 location별 리미트(컬렉션: location_limits)를 우선 적용,
//   없으면 전역 기본값(SharedPreferences: PlateLimitConfig.prefsKey) 사용
// - 위치 선택 시 plateList 화면으로 전환하지 않고,
//   ✅ 해당 "주차 구역(location)"의 입차 완료 번호판만 BottomSheet로 표시
// - 판별은 Firestore aggregate count() 1회로 처리(문서 목록 fetch 없이 개수만 확인)  ← location 단위
// - 개수 ≤ N 이면 그때만 실제 번호판 목록을 소량 조회해(BottomSheet 표시에 필요한 plateNumber만 사용) 렌더링
// - 기존 plateList 화면 로직은 보존(다른 경로에서 사용할 수 있도록), 기본 흐름에선 사용하지 않음
//
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';


// ✅ BottomSheet 표시 조건 판별(count) 및 목록 조회를 위해 Firestore 직접 사용
import 'package:cloud_firestore/cloud_firestore.dart';


// ✅ 전역 기본 한도(N) 로드용 (SharedPreferences)
import 'package:shared_preferences/shared_preferences.dart';


import '../../models/plate_model.dart';
import '../../enums/plate_type.dart';


import '../../states/area/area_state.dart';
import '../../states/plate/filter_plate.dart';
import '../../states/plate/plate_state.dart';
import '../../states/plate/movement_plate.dart';
import '../../states/user/user_state.dart';


import '../../utils/snackbar_helper.dart';
// 🔧 리미트 설정 단일 소스
import '../../utils/plate_limit/plate_limit_config.dart';


import 'parking_completed_package/widgets/signature_plate_search_bottom_sheet/parking_completed_search_bottom_sheet.dart';
import '../../widgets/navigation/top_navigation.dart';
import '../../widgets/container/plate_container.dart';


import 'parking_completed_package/parking_completed_control_buttons.dart';
import 'parking_completed_package/parking_completed_location_picker.dart';
import 'parking_completed_package/widgets/parking_status_page.dart';


enum ParkingViewMode { status, locationPicker, plateList }


class ParkingCompletedPage extends StatefulWidget {
  const ParkingCompletedPage({super.key});


  /// 홈 탭 재진입/재탭 시 내부 상태 초기화를 위한 entry point
  static void reset(GlobalKey key) {
    (key.currentState as _ParkingCompletedPageState?)?._resetInternalState();
  }


  @override
  State<ParkingCompletedPage> createState() => _ParkingCompletedPageState();
}


class _ParkingCompletedPageState extends State<ParkingCompletedPage> {
  ParkingViewMode _mode = ParkingViewMode.status; // 기본은 현황 화면
  String? _selectedParkingArea; // 선택된 주차 구역(location)
  bool _isSorted = true; // true=최신순
  bool _isLocked = true; // 화면 잠금


  /// 홈 재탭/진입 시 초기 상태로 되돌림
  void _resetInternalState() {
    setState(() {
      _mode = ParkingViewMode.status;
      _selectedParkingArea = null;
      _isSorted = true;
      _isLocked = true; // ✅ 요구사항: 홈에서 다시 시작할 때 잠금 ON
    });
  }


  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }


  void _showSearchDialog(BuildContext context) {
    final currentArea = context.read<AreaState>().currentArea;


    showDialog(
      context: context,
      builder: (context) {
        return ParkingCompletedSearchBottomSheet(
          onSearch: (_) {},
          area: currentArea,
        );
      },
    );
  }


  void _resetParkingAreaFilter(BuildContext context) {
    context.read<FilterPlate>().clearLocationSearchQuery();
    setState(() {
      _selectedParkingArea = null;
      _mode = ParkingViewMode.status;
    });
  }


  // ✅ 출차 요청 핸들러 (기존 로직 유지)
  void _handleDepartureRequested(BuildContext context) {
    final movementPlate = context.read<MovementPlate>();
    final userName = context.read<UserState>().name;
    final plateState = context.read<PlateState>();
    final selectedPlate = plateState.getSelectedPlate(PlateType.parkingCompleted, userName);


    if (selectedPlate != null) {
      movementPlate
          .setDepartureRequested(
        selectedPlate.plateNumber,
        selectedPlate.area,
        selectedPlate.location,
      )
          .then((_) {
        Future.delayed(const Duration(milliseconds: 300), () {
          if (context.mounted) {
            Navigator.pop(context);
            showSuccessSnackbar(context, "출차 요청이 완료되었습니다.");
          }
        });
      }).catchError((e) {
        if (context.mounted) {
          showFailedSnackbar(context, "출차 요청 중 오류: $e");
        }
      });
    }
  }


  // ✅ (빌드 에러 방지) 컨트롤 버튼에서 요구하는 입차 요청 콜백 스텁
  void handleEntryParkingRequest(BuildContext context, String plateNumber, String area) async {
    showSuccessSnackbar(context, "입차 요청 처리: $plateNumber ($area)");
  }


  // ---------------------------------------------------------------------------
  // ⛳ 새 로직: "구역 선택" 시 plateList 모드 대신, 조건 만족 시 번호판 BottomSheet 표시
  //   - 조건: 해당 구역(location)의 입차 완료 문서 count() ≤ N   ← location 단위 선가드
  //   - N: 먼저 서버 개별 리미트(location_limits: area+location 필드로 조회) → 없으면 SharedPreferences 전역 기본값
  //   - 만족 시: 해당 구역의 plateNumber 목록을 소량 조회하여 BottomSheet로 표시
  //   - 불만족 시: Snackbar로 잠금 안내
  // ---------------------------------------------------------------------------
  Future<void> _tryShowPlateNumbersBottomSheet(String locationName) async {
    // 🔒 잠금 상태면 즉시 차단
    if (_isLocked) {
      showFailedSnackbar(context, '잠금 상태입니다. 잠금을 해제한 뒤 이용해 주세요.');
      return;
    }


    final area = context.read<AreaState>().currentArea;


    // UI에서 '부모 - 자식' 형태로 오는 경우를 대비해 자식만 분리 후보 준비
    String raw = locationName.trim();
    String? child;
    final hyphenIdx = raw.indexOf(' - ');
    if (hyphenIdx != -1) {
      child = raw.substring(hyphenIdx + 3).trim();
    }


    try {
      final fs = FirebaseFirestore.instance;
      final coll = fs.collection('plates');


      // 1) location 단위 개수 선판별: raw → (없으면) child 순으로 count()
      Future<int> countAt(String loc) async {
        final snap = await coll
            .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
            .where('area', isEqualTo: area)
            .where('location', isEqualTo: loc)
            .count()
            .get();
        return snap.count ?? 0;
      }


      String selectedLoc = raw;
      int locCnt = await countAt(raw);
      if (locCnt == 0 && child != null && child.isNotEmpty) {
        selectedLoc = child;
        locCnt = await countAt(child);
      }


      if (locCnt == 0) {
        showSelectedSnackbar(context, '해당 구역에 입차 완료 차량이 없습니다.');
        return;
      }


      // 2) 리미트 결정: (A) 서버 개별 리미트 → (B) 전역 기본값(SharedPreferences)
      int limit;
      final qsLimit = await fs
          .collection('location_limits')
          .where('area', isEqualTo: area)
          .where('location', isEqualTo: selectedLoc)
          .limit(1)
          .get();


      if (qsLimit.docs.isNotEmpty && qsLimit.docs.first.data()['limit'] != null) {
        limit = (qsLimit.docs.first.data()['limit'] as int)
            .clamp(PlateLimitConfig.min, PlateLimitConfig.max);
      } else {
        final prefs = await SharedPreferences.getInstance();
        limit = (prefs.getInt(PlateLimitConfig.prefsKey) ?? PlateLimitConfig.defaultLimit)
            .clamp(PlateLimitConfig.min, PlateLimitConfig.max);
      }


      // 3) 기준 초과면 차단
      if (locCnt > limit) {
        showFailedSnackbar(context, '목록 잠금: "$selectedLoc"에 입차 완료 $locCnt대(>$limit) 입니다.');
        return;
      }


      // 4) 조건 만족 시: 선택된 location에서 실제 목록을 소량 조회 (번호판만 사용)
      Future<QuerySnapshot<Map<String, dynamic>>> fetchAt(String loc) {
        return coll
            .where('type', isEqualTo: PlateType.parkingCompleted.firestoreValue)
            .where('area', isEqualTo: area)
            .where('location', isEqualTo: loc)
        // .orderBy('request_time', descending: true) // 필요 시 인덱스 구성
            .limit(limit) // 안전하게 limit 적용
            .get();
      }


      final QuerySnapshot<Map<String, dynamic>> qs = await fetchAt(selectedLoc);


      // 5) 번호판만 뽑기 (스키마에 맞춰 plate_number 우선)
      final plateNumbers = <String>[];
      for (final d in qs.docs) {
        final data = d.data();
        final pn = (data['plate_number'] // ✅ 실제 스키마
            ??
            data['plateNumber'] // 호환
            ??
            data['plate'] // 호환
            ??
            data['number'] // 호환
            ??
            data['licensePlate'] // 호환
            ??
            data['carNumber']) // 호환
            ?.toString()
            .trim();
        if (pn != null && pn.isNotEmpty) {
          plateNumbers.add(pn);
        } else {
          final four = (data['plate_four_digit'] ?? '').toString().trim();
          if (four.isNotEmpty) plateNumbers.add('****-$four');
        }
      }


      if (plateNumbers.isEmpty) {
        showSelectedSnackbar(context, '해당 구역에 입차 완료 차량이 없습니다.');
        return;
      }


      if (!mounted) return;
      _showPlateNumberListSheet(locationName: locationName, plates: plateNumbers);
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '번호판 목록 표시 실패: $e');
    }
  }


  /// 번호판 목록을 간단히 보여주는 바텀시트 UI (plateNumber 텍스트만)
  void _showPlateNumberListSheet({
    required String locationName,
    required List<String> plates,
  }) {
    // ✅ 아이템 수에 따라 초기/최소 높이를 동적으로 설정
    //  - 1~3개: 45% 시작
    //  - 4~7개: 60% 시작
    //  - 8개 이상: 80% 시작
    final double initialFactor =
    plates.length <= 3 ? 0.45 : (plates.length <= 7 ? 0.60 : 0.80);


    showModalBottomSheet(
      context: context,
      isScrollControlled: true, // ← 전체 높이 제어를 위해 필요
      useSafeArea: true,
      backgroundColor: Colors.transparent, // ← 둥근 모서리 보이게
      builder: (_) {
        return DraggableScrollableSheet(
          initialChildSize: initialFactor, // 시작 높이 (화면 비율)
          minChildSize: initialFactor, // 최소 높이
          maxChildSize: 0.95, // 최대 높이 (거의 풀스크린)
          expand: false, // 시트가 전체를 강제 점유하지 않음
          builder: (context, scrollController) {
            return SafeArea(
              top: false,
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // 상단 핸들
                    Container(
                      width: 44,
                      height: 4,
                      margin: const EdgeInsets.only(top: 8, bottom: 12),
                      decoration: BoxDecoration(
                        color: Colors.black12,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // 헤더
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          const Icon(Icons.local_parking, color: Colors.teal),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '"$locationName" 번호판',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text('${plates.length}대',
                              style: const TextStyle(color: Colors.black54)),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),


                    // 목록
                    Expanded(
                      child: ListView.separated(
                        controller:
                        scrollController, // ✅ 드래그 시트와 스크롤 연동
                        itemCount: plates.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final pn = plates[i];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.directions_car,
                                color: Colors.black87),
                            title: Text(
                              pn,
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            // 요구사항: "번호판 명만" → 탭 액션 없음
                          );
                        },
                      ),
                    ),


                    // 하단 안전 여백
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }


  // ---------------------------------------------------------------------------


  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      // 시스템/뒤로가기 처리: 선택/모드 단계적으로 해제
      onWillPop: () async {
        final plateState = context.read<PlateState>();
        final userName = context.read<UserState>().name;
        final selectedPlate =
        plateState.getSelectedPlate(PlateType.parkingCompleted, userName);


        // 선택된 번호판이 있으면 선택 해제 먼저
        if (selectedPlate != null && selectedPlate.id.isNotEmpty) {
          await plateState.togglePlateIsSelected(
            collection: PlateType.parkingCompleted,
            plateNumber: selectedPlate.plateNumber,
            userName: userName,
            onError: (msg) => debugPrint(msg),
          );
          return false;
        }


        // plateList → locationPicker → status 순으로 한 단계씩 되돌기
        if (_mode == ParkingViewMode.plateList) {
          setState(() => _mode = ParkingViewMode.locationPicker);
          return false;
        } else if (_mode == ParkingViewMode.locationPicker) {
          setState(() => _mode = ParkingViewMode.status);
          return false;
        }


        // 최상위(status)면 pop 허용
        return true;
      },
      child: Scaffold(
        appBar: AppBar(
          title: const TopNavigation(),
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
        ),
        body: _buildBody(context),
        bottomNavigationBar: ParkingCompletedControlButtons(
          isParkingAreaMode: _mode == ParkingViewMode.plateList,
          isStatusMode: _mode == ParkingViewMode.status,
          isLocationPickerMode: _mode == ParkingViewMode.locationPicker,
          isSorted: _isSorted,
          isLocked: _isLocked,
          onToggleLock: () {
            setState(() {
              _isLocked = !_isLocked;
            });
          },
          showSearchDialog: () => _showSearchDialog(context),
          resetParkingAreaFilter: () => _resetParkingAreaFilter(context),
          toggleSortIcon: _toggleSortIcon,
          handleEntryParkingRequest: handleEntryParkingRequest,
          handleDepartureRequested: _handleDepartureRequested,
        ),
      ),
    );
  }


  Widget _buildBody(BuildContext context) {
    final plateState = context.watch<PlateState>();
    final userName = context.read<UserState>().name;


    switch (_mode) {
      case ParkingViewMode.status:
      // 🔹 현황 화면을 탭하면 위치 선택 화면으로 전환
        return GestureDetector(
          onTap: () => setState(() => _mode = ParkingViewMode.locationPicker),
          child: ParkingStatusPage(isLocked: _isLocked),
        );


      case ParkingViewMode.locationPicker:
      // 🔹 위치 선택 시: plateList 모드로 가지 않고, 번호판 BottomSheet 시도
        return ParkingCompletedLocationPicker(
          onLocationSelected: (locationName) {
            _selectedParkingArea = locationName; // 선택된 구역 저장(필요 시)
            _tryShowPlateNumbersBottomSheet(locationName);
          },
          isLocked: _isLocked,
        );


      case ParkingViewMode.plateList:
      // 🔹 기존 plateList 화면은 보존(다른 경로에서 필요할 수 있음). 현재 기본 흐름에선 사용 안 함.
        List<PlateModel> plates =
        plateState.getPlatesByCollection(PlateType.parkingCompleted);
        if (_selectedParkingArea != null) {
          plates =
              plates.where((p) => p.location == _selectedParkingArea).toList();
        }
        plates.sort(
              (a, b) => _isSorted
              ? b.requestTime.compareTo(a.requestTime)
              : a.requestTime.compareTo(b.requestTime),
        );


        return ListView(
          padding: const EdgeInsets.all(8.0),
          children: [
            PlateContainer(
              data: plates,
              collection: PlateType.parkingCompleted,
              filterCondition: (request) =>
              request.type == PlateType.parkingCompleted.firestoreValue,
              onPlateTap: (plateNumber, area) {
                context.read<PlateState>().togglePlateIsSelected(
                  collection: PlateType.parkingCompleted,
                  plateNumber: plateNumber,
                  userName: userName,
                  onError: (msg) => showFailedSnackbar(context, msg),
                );
              },
            ),
          ],
        );
    }
  }
}



