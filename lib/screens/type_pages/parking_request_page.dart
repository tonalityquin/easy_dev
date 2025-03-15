import 'package:easydev/states/plate/filter_state.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../states/plate/plate_state.dart'; // PlateState 상태 관리
import '../../states/area/area_state.dart'; // AreaState 상태 관리
import '../../states/user/user_state.dart';
import '../../widgets/container/plate_container.dart'; // 번호판 데이터를 표시하는 위젯
import '../../widgets/dialog/parking_request_delete_dialog.dart';
import '../../widgets/navigation/top_navigation.dart'; // 상단 내비게이션 바
import '../../widgets/dialog/plate_search_dialog.dart';
import '../../utils/show_snackbar.dart';
import '../../widgets/dialog/parking_location_dialog.dart';
import '../../repositories/plate/plate_repository.dart';

class ParkingRequestPage extends StatefulWidget {
  const ParkingRequestPage({super.key});

  @override
  State<ParkingRequestPage> createState() => _ParkingRequestPageState();
}

class _ParkingRequestPageState extends State<ParkingRequestPage> {
  bool _isSorted = true;
  bool _isSearchMode = false;

  void _toggleSortIcon() {
    setState(() {
      _isSorted = !_isSorted;
    });
  }

  void _showSearchDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) {
        return PlateSearchDialog(
          onSearch: (query) {
            _filterPlatesByNumber(context, query);
          },
        );
      },
    );
  }

  void _filterPlatesByNumber(BuildContext context, String query) {
    if (query.length == 4) {
      context.read<FilterState>().setPlateSearchQuery(query);
      setState(() {
        _isSearchMode = true;
      });
    }
  }

  void _resetSearch(BuildContext context) {
    context.read<FilterState>().clearPlateSearchQuery();
    setState(() {
      _isSearchMode = false;
    });
  }

  void _handlePlateTap(BuildContext context, String plateNumber, String area) {
    final userName = context.read<UserState>().name;
    context.read<PlateState>().toggleIsSelected(
          collection: 'parking_requests',
          plateNumber: plateNumber,
          area: area,
          userName: userName,
          onError: (errorMessage) {
            showSnackbar(context, errorMessage);
          },
        );
  }

  void _handleParkingCompleted(BuildContext context) {
    final plateState = context.read<PlateState>();
    final userName = context.read<UserState>().name;
    final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
    if (selectedPlate != null) {
      final TextEditingController locationController = TextEditingController();
      showDialog(
        context: context,
        builder: (context) {
          return ParkingLocationDialog(
            locationController: locationController,
            onLocationSelected: (String location) {
              if (location.isNotEmpty) {
                _completeParking(context, selectedPlate.plateNumber, selectedPlate.area, location);
              } else {
                showSnackbar(context, '주차 구역을 입력해주세요.');
              }
            },
          );
        },
      );
    }
  }

  void _completeParking(BuildContext context, String plateNumber, String area, String location) {
    final plateState = context.read<PlateState>();
    final plateRepository = context.read<PlateRepository>();
    try {
      plateRepository.addRequestOrCompleted(
        collection: 'parking_completed',
        plateNumber: plateNumber,
        location: location,
        area: area,
        userName: context.read<UserState>().name,
        type: '입차 완료',
        adjustmentType: null,
        statusList: [],
        basicStandard: 0,
        basicAmount: 0,
        addStandard: 0,
        addAmount: 0,
      );
      plateState.movePlateToCompleted(plateNumber, location);
      showSnackbar(context, "입차 완료: $plateNumber ($location)");
    } catch (e) {
      debugPrint("입차 완료 처리 실패: $e");
      showSnackbar(context, "입차 완료 처리 중 오류 발생: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const TopNavigation(),
      body: Consumer2<PlateState, AreaState>(
        builder: (context, plateState, areaState, child) {
          final currentArea = areaState.currentArea;
          var parkingRequests = plateState.getPlatesByArea('parking_requests', currentArea);
          parkingRequests.sort((a, b) {
            return _isSorted ? b.requestTime.compareTo(a.requestTime) : a.requestTime.compareTo(b.requestTime);
          });
          return ListView(
            padding: const EdgeInsets.all(8.0),
            children: [
              PlateContainer(
                data: parkingRequests,
                collection: 'parking_requests',
                filterCondition: (request) => request.type == '입차 요청' || request.type == '입차 중',
                onPlateTap: (plateNumber, area) {
                  _handlePlateTap(context, plateNumber, area);
                },
              ),
            ],
          );
        },
      ),
      bottomNavigationBar: Consumer<PlateState>(
        builder: (context, plateState, child) {
          final userName = context.read<UserState>().name;
          final selectedPlate = plateState.getSelectedPlate('parking_requests', userName);
          final isPlateSelected = selectedPlate != null && selectedPlate.isSelected;
          return BottomNavigationBar(
              items: [
                BottomNavigationBarItem(
                  icon: Icon(
                    isPlateSelected ? Icons.highlight_alt : (_isSearchMode ? Icons.cancel : Icons.search),
                  ),
                  label: isPlateSelected ? '정보 수정' : (_isSearchMode ? '검색 초기화' : '번호판 검색'),
                ),
                BottomNavigationBarItem(
                  icon: isPlateSelected
                      ? Icon(Icons.check_circle, color: Colors.green)
                      : Image.asset(
                          'assets/icons/icon_belivussnc.PNG',
                          width: 24.0,
                          height: 24.0,
                          fit: BoxFit.contain,
                        ),
                  label: isPlateSelected ? '입차 완료' : 'Belivus S&C',
                ),
                BottomNavigationBarItem(
                  icon: AnimatedRotation(
                    turns: _isSorted ? 0.5 : 0.0,
                    duration: const Duration(milliseconds: 300),
                    child: Transform.scale(
                      scaleX: _isSorted ? -1 : 1,
                      child: Icon(
                        isPlateSelected ? Icons.delete : Icons.sort,
                      ),
                    ),
                  ),
                  label: isPlateSelected ? '입차 취소' : (_isSorted ? '최신순' : '오래된순'),
                ),
              ],
              onTap: (index) {
                if (index == 0) {
                  if (_isSearchMode) {
                    _resetSearch(context);
                  } else {
                    _showSearchDialog(context);
                  }
                } else if (index == 1 && isPlateSelected) {
                  _handleParkingCompleted(context);
                } else if (index == 2) {
                  if (isPlateSelected) {
                    showDialog(
                      context: context,
                      builder: (context) {
                        return ParkingRequestDeleteDialog(
                          onConfirm: () {
                            context
                                .read<PlateState>()
                                .deletePlateFromParkingRequest(selectedPlate.plateNumber, selectedPlate.area);
                            showSnackbar(context, "삭제 완료: ${selectedPlate.plateNumber}");
                          },
                        );
                      },
                    );
                  } else {
                    _toggleSortIcon();
                  }
                }
              });
        },
      ),
    );
  }
}
