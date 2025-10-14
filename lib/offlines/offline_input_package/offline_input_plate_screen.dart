import 'package:flutter/material.dart';

import 'offline_input_plate_controller.dart';
import 'sections/offline_input_bill_section.dart';
import 'sections/offline_input_location_section.dart';
import 'sections/offline_input_photo_section.dart';
import 'sections/offline_input_plate_section.dart';
import 'sections/offline_input_bottom_action_section.dart';
import 'sections/offline_input_custom_status_section.dart';

import 'offline_keypad/num_keypad.dart';
import 'offline_keypad/kor_keypad.dart';
import 'widgets/offline_input_bottom_navigation.dart';

import 'offline_live_ocr_page.dart';

/// Offline Service Palette (오프라인 카드 계열)
class _Palette {
  static const base  = Color(0xFFF4511E); // primary
  static const dark  = Color(0xFFD84315); // 강조 텍스트/아이콘
  static const light = Color(0xFFFFAB91); // 톤 변형/보더
}

class OfflineInputPlateScreen extends StatefulWidget {
  const OfflineInputPlateScreen({super.key});

  @override
  State<OfflineInputPlateScreen> createState() => _OfflineInputPlateScreenState();
}

class _OfflineInputPlateScreenState extends State<OfflineInputPlateScreen> {
  final controller = OfflineInputPlateController();

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  String selectedBillType = '변동';

  bool _openedScannerOnce = false;

  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false; // 현재 열림 상태

  static const double _sheetClosed = 0.16; // 헤더만 살짝
  static const double _sheetOpened = 1.00; // ★ 최상단까지 (화면 높이 꽉 채움)

  Future<void> _animateSheet({required bool open}) async {
    final target = open ? _sheetOpened : _sheetClosed;
    try {
      await _sheetController.animateTo(
        target,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeInOutCubic,
      );
      if (mounted) setState(() => _sheetOpen = open);
    } catch (_) {
      // 컨트롤러가 아직 attach되지 않았을 수 있음 → 프레임 이후 재시도
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetController.jumpTo(target);
        if (mounted) setState(() => _sheetOpen = open);
      });
    }
  }

  void _toggleSheet() {
    _animateSheet(open: !_sheetOpen);
  }

  @override
  void initState() {
    super.initState();

    // ⬇️ 시트 사이즈 변화에 따라 _sheetOpen 동기화 (드래그로 여닫을 때도 반영)
    _sheetController.addListener(() {
      try {
        final s = _sheetController.size; // 0.0~1.0
        // 닫힘(0.16)과 열림(1.0) 중간값(≈0.58)을 기준으로 열림/닫힘 판정
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);
        if (openNow != _sheetOpen && mounted) {
          setState(() => _sheetOpen = openNow);
        }
      } catch (_) {
        // attach 전 접근 등은 무시
      }
    });

    controller.controllerBackDigit.addListener(() async {
      final text = controller.controllerBackDigit.text;
      if (text.length == 4 && controller.isInputValid()) {}
    });

    // 첫 빌드 직후 한 번만 자동으로 LiveOcrPage 열기
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_openedScannerOnce) return;
      _openedScannerOnce = true;
      await _openLiveScanner(); // 사용자가 닫으면 plate == null 로 처리
    });
  }

  @override
  void dispose() {
    _sheetController.dispose();
    controller.dispose();
    super.dispose();
  }

  // 스캐너로 이동 → 성공 시 입력칸 자동 채우기 (사용자가 닫으면 plate == null)
  Future<void> _openLiveScanner() async {
    final plate = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const OfflineLiveOcrPage()),
    );
    if (plate == null) return;

    final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(plate);
    if (m == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인식값 형식 확인 필요: $plate')),
      );
      return;
    }

    final front = m.group(1)!; // 2 or 3 digits
    final mid = m.group(2)!;   // 한글 1글자
    final back = m.group(3)!;  // 4 digits

    setState(() {
      controller.setFrontDigitMode(front.length == 3);
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;
      controller.controllerBackDigit.text = back;
      controller.showKeypad = false;
    });

    if (!mounted) return;
  }

  Widget _buildKeypad() {
    final active = controller.activeController;

    if (active == controller.controllerFrontDigit) {
      return NumKeypad(
        key: const ValueKey('frontKeypad'),
        controller: controller.controllerFrontDigit,
        maxLength: controller.isThreeDigit ? 3 : 2,
        onComplete: () => setState(() => controller.setActiveController(controller.controllerMidDigit)),
        onChangeFrontDigitMode: (defaultThree) {
          setState(() {
            controller.setFrontDigitMode(defaultThree);
          });
        },
        enableDigitModeSwitch: true,
      );
    }

    if (active == controller.controllerMidDigit) {
      return KorKeypad(
        key: const ValueKey('midKeypad'),
        controller: controller.controllerMidDigit,
        onComplete: () => setState(() => controller.setActiveController(controller.controllerBackDigit)),
      );
    }

    return NumKeypad(
      key: const ValueKey('backKeypad'),
      controller: controller.controllerBackDigit,
      maxLength: 4,
      onComplete: () => setState(() => controller.showKeypad = false),
      enableDigitModeSwitch: false,
      onReset: () {
        setState(() {
          controller.clearInput();
          controller.setActiveController(controller.controllerFrontDigit);
        });
      },
    );
  }

  // showKeypad일 때, 번호판 도크 + 키패드를 함께 표시
  Widget _buildDockAndKeypad() {
    if (!controller.showKeypad) return _buildKeypad();
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _PlateDock(
          controller: controller,
          onActivate: (target) {
            setState(() {
              controller.setActiveController(target);
              controller.showKeypad = true; // 도크 탭 시 키패드 유지
            });
          },
        ),
        const SizedBox(height: 8),
        _buildKeypad(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // 키보드/인셋 반영 하단 패딩
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafePadding = (controller.showKeypad ? 280.0 : 140.0) + viewInset;

    // 뒤로가기: 시트가 열려 있으면 먼저 닫고, 닫혀 있으면 pop 허용
    return PopScope(
      canPop: !_sheetOpen,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_sheetOpen) {
          await _animateSheet(open: false);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          title: Align(
            alignment: Alignment.centerRight,
            child: Text(
              controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          actions: [
            IconButton(
              tooltip: '실시간 OCR 스캔',
              onPressed: _openLiveScanner,
              icon: const Icon(Icons.auto_awesome_motion, color: _Palette.base),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // 상단(기본) 콘텐츠
                Positioned.fill(
                  child: SingleChildScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        OfflineInputPlateSection(
                          dropdownValue: controller.dropdownValue,
                          regions: controller.regions,
                          controllerFrontDigit: controller.controllerFrontDigit,
                          controllerMidDigit: controller.controllerMidDigit,
                          controllerBackDigit: controller.controllerBackDigit,
                          activeController: controller.activeController,
                          onKeypadStateChanged: (_) {
                            setState(() {
                              controller.clearInput();
                              controller.setActiveController(controller.controllerFrontDigit);
                            });
                          },
                          onRegionChanged: (region) {
                            setState(() {
                              controller.dropdownValue = region;
                            });
                          },
                          isThreeDigit: controller.isThreeDigit,
                        ),
                        const SizedBox(height: 16),
                        OfflineInputLocationSection(locationController: controller.locationController),
                        const SizedBox(height: 16),
                        OfflineInputPhotoSection(
                          capturedImages: controller.capturedImages,
                          plateNumber: controller.buildPlateNumber(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // 하단 DraggableScrollableSheet (불투명 처리)
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _sheetClosed,
                  minChildSize: _sheetClosed,
                  maxChildSize: _sheetOpened,
                  snap: true,
                  snapSizes: const [_sheetClosed, _sheetOpened],
                  builder: (context, scrollController) {
                    return Material(
                      // ❗ 완전 불투명 처리
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: _Palette.dark.withOpacity(.18),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      clipBehavior: Clip.antiAlias, // 라운드 상단 모서리 내 콘텐츠도 클립
                      child: SafeArea(
                        top: true,
                        bottom: false,
                        child: ListView(
                          controller: scrollController,
                          physics: const NeverScrollableScrollPhysics(), // 내부 스크롤 금지(요청 유지)
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            16 + (controller.showKeypad ? 260 : 100) + viewInset,
                          ),
                          children: [
                            // 헤더(탭으로 열고 닫기 + 애니메이션)
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleSheet,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 12),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 40,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text(
                                          '정산 유형 / 메모 카드',
                                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                                        ),
                                        Text(
                                          controller.buildPlateNumber(),
                                          style: const TextStyle(color: Colors.black54),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // ⬇️ 정산 영역
                            OfflineInputBillSection(
                              selectedBill: controller.selectedBill,
                              onChanged: (value) => setState(() => controller.selectedBill = value),
                              selectedBillType: selectedBillType,
                              onTypeChanged: (newType) => setState(() => selectedBillType = newType),
                              countTypeController: controller.countTypeController,
                            ),

                            const SizedBox(height: 24),

                            // 차량 상태 토글은 제거, 메모 섹션만 유지
                            OfflineInputCustomStatusSection(
                              controller: controller,
                              fetchedCustomStatus: controller.fetchedCustomStatus,
                              selectedStatusNames: selectedStatusNames,
                              statusSectionKey: statusSectionKey,
                              onDeleted: () {
                                setState(() {
                                  controller.fetchedCustomStatus = null;
                                  controller.customStatusController.clear();
                                });
                              },
                              onStatusCleared: () {
                                setState(() {
                                  selectedStatusNames = [];
                                  statusSectionKey = UniqueKey();
                                });
                              },
                            ),

                            const SizedBox(height: 8),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            OfflineInputBottomNavigation(
              showKeypad: controller.showKeypad,
              keypad: _buildDockAndKeypad(), // 도크 + 키패드 묶음
              actionButton: OfflineInputBottomActionSection(
                controller: controller,
                mountedContext: mounted,
                onStateRefresh: () => setState(() {}),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: SizedBox(
                height: 48,
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 하단 도크: 번호판 입력 3분할을 키패드 바로 위에 고정해 시선/손 집중을 돕는다.
class _PlateDock extends StatelessWidget {
  final OfflineInputPlateController controller;
  final void Function(TextEditingController target) onActivate;

  const _PlateDock({
    required this.controller,
    required this.onActivate,
  });

  InputDecoration _dec(BuildContext context, bool active) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      // 활성 시 아주 옅은 오렌지 톤
      fillColor: active ? _Palette.light.withOpacity(.22) : Colors.white,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: Colors.grey.shade300,
          width: 1,
        ),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: _Palette.base, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFrontActive = controller.activeController == controller.controllerFrontDigit;
    final isMidActive = controller.activeController == controller.controllerMidDigit;
    final isBackActive = controller.activeController == controller.controllerBackDigit;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [
          BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2)),
        ],
      ),
      child: Row(
        children: [
          // 앞자리 (2~3자리)
          Expanded(
            flex: 28,
            child: GestureDetector(
              onTap: () => onActivate(controller.controllerFrontDigit),
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.controllerFrontDigit,
                  readOnly: true,
                  maxLength: controller.isThreeDigit ? 3 : 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: _dec(context, isFrontActive),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 한글 (1글자)
          Expanded(
            flex: 18,
            child: GestureDetector(
              onTap: () => onActivate(controller.controllerMidDigit),
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.controllerMidDigit,
                  readOnly: true,
                  maxLength: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: _dec(context, isMidActive),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // 뒷자리 (4자리)
          Expanded(
            flex: 36,
            child: GestureDetector(
              onTap: () => onActivate(controller.controllerBackDigit),
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.controllerBackDigit,
                  readOnly: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: _dec(context, isBackActive),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
