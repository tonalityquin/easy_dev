// lib/screens/input_package/offline_input_plate_screen.dart
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
  bool _sheetOpen = false;

  static const double _sheetClosed = 0.16;
  static const double _sheetOpened = 1.00;

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
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _sheetController.jumpTo(target);
        if (mounted) setState(() => _sheetOpen = open);
      });
    }
  }

  void _toggleSheet() => _animateSheet(open: !_sheetOpen);

  @override
  void initState() {
    super.initState();

    _sheetController.addListener(() {
      try {
        final s = _sheetController.size;
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);
        if (openNow != _sheetOpen && mounted) setState(() => _sheetOpen = openNow);
      } catch (_) {}
    });

    controller.controllerBackDigit.addListener(() async {
      final text = controller.controllerBackDigit.text;
      if (text.length == 4 && controller.isInputValid()) {}
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_openedScannerOnce) return;
      _openedScannerOnce = true;
      await _openLiveScanner();
    });
  }

  @override
  void dispose() {
    _sheetController.dispose();
    controller.dispose();
    super.dispose();
  }

  // 스캐너 → plate 수신 → 칸 분배 (가운데 임의문자/누락 허용)
  Future<void> _openLiveScanner() async {
    final plate = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const OfflineLiveOcrPage()),
    );
    if (plate == null) return;

    final normalized = plate.replaceAll(RegExp(r'\s+'), '');

    // 1) 완전형: 앞(2~3) + 임의문자(1) + 뒤(4)
    RegExpMatch? m = RegExp(r'^(\d{2,3})(.)(\d{4})$').firstMatch(normalized);

    // 2) 누락형: digits-only (6 또는 7)
    final m2 = m ?? RegExp(r'^(\d{2,3})(\d{4})$').firstMatch(normalized);

    if (m != null) {
      final front = m.group(1)!;
      final mid   = m.group(2)!;  // 임의문자 허용(+, 4, 영문 등)
      final back  = m.group(3)!;

      setState(() {
        controller.setFrontDigitMode(front.length == 3);
        controller.controllerFrontDigit.text = front;
        controller.controllerMidDigit.text   = mid;
        controller.controllerBackDigit.text  = back;
        controller.showKeypad = false;
      });
      return;
    } else if (m2 != null) {
      final front = m2.group(1)!; // 2 또는 3
      final back  = m2.group(2)!; // 4

      setState(() {
        controller.setFrontDigitMode(front.length == 3);
        controller.controllerFrontDigit.text = front;
        controller.controllerMidDigit.text   = '';  // 누락
        controller.controllerBackDigit.text  = back;
        controller.setActiveController(controller.controllerMidDigit); // 중간칸 보정 유도
        controller.showKeypad = true;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('가운데 문자가 누락되었습니다. 중간 칸을 입력해 주세요. (원본: $plate)')),
      );
      return;
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('인식값 형식 확인 필요: $plate')),
      );
    }
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
          setState(() => controller.setFrontDigitMode(defaultThree));
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
    // 키보드/인셋 + 시스템 하단 안전영역 반영
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final sysBottom = MediaQuery.of(context).padding.bottom;
    final bottomSafePadding = (controller.showKeypad ? 280.0 : 140.0) + viewInset + sysBottom;

    return PopScope(
      canPop: !_sheetOpen,
      onPopInvoked: (didPop) async {
        if (didPop) return;
        if (_sheetOpen) await _animateSheet(open: false);
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
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: _Palette.dark.withOpacity(.18),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SafeArea(
                        top: true,
                        bottom: false, // 하단은 우리가 별도 패딩으로 반영
                        child: ListView(
                          controller: scrollController,
                          physics: const NeverScrollableScrollPhysics(),
                          padding: EdgeInsets.fromLTRB(
                            16,
                            8,
                            16,
                            16 + (controller.showKeypad ? 260 : 100) + viewInset + sysBottom,
                          ),
                          children: [
                            // 헤더
                            GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: _toggleSheet,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 8, bottom: 12),
                                child: Column(
                                  children: [
                                    Container(
                                      width: 40, height: 4,
                                      decoration: BoxDecoration(
                                        color: Colors.black38,
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        const Text('정산 유형 / 메모 카드',
                                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                        Text(controller.buildPlateNumber(),
                                            style: const TextStyle(color: Colors.black54)),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),

                            // 정산 영역
                            OfflineInputBillSection(
                              selectedBill: controller.selectedBill,
                              onChanged: (value) => setState(() => controller.selectedBill = value),
                              selectedBillType: selectedBillType,
                              onTypeChanged: (newType) => setState(() => selectedBillType = newType),
                              countTypeController: controller.countTypeController,
                            ),

                            const SizedBox(height: 24),

                            // 메모 섹션
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
        // 하단 네비/제스처 바와 겹치지 않게 SafeArea로 감쌈
        bottomNavigationBar: SafeArea(
          top: false, left: false, right: false, bottom: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              OfflineInputBottomNavigation(
                showKeypad: controller.showKeypad,
                keypad: _buildDockAndKeypad(),
                actionButton: OfflineInputBottomActionSection(
                  controller: controller,
                  mountedContext: mounted,
                  onStateRefresh: () => setState(() {}),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SizedBox(height: 48, child: Image.asset('assets/images/pelican.png')),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 하단 도크: 번호판 입력 3분할을 키패드 바로 위에 고정
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
      fillColor: active ? _Palette.light.withOpacity(.22) : Colors.white,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
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
    final isMidActive   = controller.activeController == controller.controllerMidDigit;
    final isBackActive  = controller.activeController == controller.controllerBackDigit;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 8, offset: Offset(0, -2))],
      ),
      child: Row(
        children: [
          // 앞자리 (2~3)
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

          // 가운데 (1)
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

          // 뒷자리 (4)
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
