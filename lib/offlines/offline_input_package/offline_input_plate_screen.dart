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

// ✅ TTS
import '../../offlines/tts/offline_tts.dart';

import '../../theme.dart';

enum _DockField { front, mid, back }

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

  _DockField? _dockEditing;

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
      if (text.length == 4 && controller.isInputValid()) {
        // 입력 완료 시점 이벤트 필요시 추가
      }
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

  Future<void> _openLiveScanner() async {
    final plate = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const OfflineLiveOcrPage()),
    );
    if (plate == null) return;

    final normalized = plate.replaceAll(RegExp(r'\s+'), '');

    RegExpMatch? m = RegExp(r'^(\d{2,3})(.)(\d{4})$').firstMatch(normalized);
    final m2 = m ?? RegExp(r'^(\d{2,3})(\d{4})$').firstMatch(normalized);

    if (m != null) {
      final front = m.group(1)!;
      final mid = m.group(2)!;
      final back = m.group(3)!;

      setState(() {
        controller.setFrontDigitMode(front.length == 3);
        controller.controllerFrontDigit.text = front;
        controller.controllerMidDigit.text = mid;
        controller.controllerBackDigit.text = back;
        controller.showKeypad = false;
        _dockEditing = null;
      });
      return;
    } else if (m2 != null) {
      final front = m2.group(1)!;
      final back = m2.group(2)!;

      setState(() {
        controller.setFrontDigitMode(front.length == 3);
        controller.controllerFrontDigit.text = front;
        controller.controllerMidDigit.text = '';
        controller.controllerBackDigit.text = back;
        controller.showKeypad = true;
        _dockEditing = null;
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

  void _beginDockEdit(_DockField field) {
    setState(() {
      _dockEditing = field;
      switch (field) {
        case _DockField.front:
          controller.controllerFrontDigit.clear();
          controller.setActiveController(controller.controllerFrontDigit);
          break;
        case _DockField.mid:
          controller.controllerMidDigit.clear();
          controller.setActiveController(controller.controllerMidDigit);
          break;
        case _DockField.back:
          controller.controllerBackDigit.clear();
          controller.setActiveController(controller.controllerBackDigit);
          break;
      }
      controller.showKeypad = true;
    });
  }

  Widget _buildKeypad() {
    final active = controller.activeController;

    if (active == controller.controllerFrontDigit) {
      return NumKeypad(
        key: const ValueKey('frontKeypad'),
        controller: controller.controllerFrontDigit,
        maxLength: controller.isThreeDigit ? 3 : 2,
        onComplete: () => setState(() {
          if (_dockEditing == _DockField.front) {
            controller.showKeypad = false;
            _dockEditing = null;
          } else {
            controller.setActiveController(controller.controllerMidDigit);
          }
        }),
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
        onComplete: () => setState(() {
          if (_dockEditing == _DockField.mid) {
            controller.showKeypad = false;
            _dockEditing = null;
          } else {
            controller.setActiveController(controller.controllerBackDigit);
          }
        }),
      );
    }

    return NumKeypad(
      key: const ValueKey('backKeypad'),
      controller: controller.controllerBackDigit,
      maxLength: 4,
      onComplete: () => setState(() {
        controller.showKeypad = false;
        _dockEditing = null;
      }),
      enableDigitModeSwitch: false,
      onReset: () {
        setState(() {
          controller.clearInput();
          controller.setActiveController(controller.controllerFrontDigit);
          _dockEditing = null;
        });
      },
    );
  }

  Widget _buildDock() {
    return _PlateDock(
      controller: controller,
      onActivateFront: () => _beginDockEdit(_DockField.front),
      onActivateMid: () => _beginDockEdit(_DockField.mid),
      onActivateBack: () => _beginDockEdit(_DockField.back),
    );
  }

  Widget _buildBottomBar() {
    final actionButton = OfflineInputBottomActionSection(
      controller: controller,
      mountedContext: mounted,
      onStateRefresh: () => setState(() {}),
      // ✅ 저장 성공 직후 TTS 호출
      onAfterSavedSuccess: () async {
        await OfflineTts.instance.sayParkingInserted();
      },
    );

    if (controller.showKeypad) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OfflineInputBottomNavigation(
            showKeypad: true,
            keypad: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildDock(),
                const SizedBox(height: 8),
                _buildKeypad(),
              ],
            ),
            actionButton: actionButton,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(height: 48, child: Image.asset('assets/images/pelican.png')),
          ),
        ],
      );
    } else {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 8),
            child: _buildDock(),
          ),
          OfflineInputBottomNavigation(
            showKeypad: false,
            keypad: const SizedBox.shrink(),
            actionButton: actionButton,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(height: 48, child: Image.asset('assets/images/pelican.png')),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pal = AppCardPalette.of(context);
    final base = pal.parkingBase;
    final dark = pal.parkingDark;

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
              icon: Icon(Icons.auto_awesome_motion, color: base),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
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
                              _dockEditing = null;
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
                      shadowColor: dark.withOpacity(.18),
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: SafeArea(
                        top: true,
                        bottom: false,
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
                            OfflineInputBillSection(
                              selectedBill: controller.selectedBill,
                              onChanged: (value) => setState(() => controller.selectedBill = value),
                              selectedBillType: selectedBillType,
                              onTypeChanged: (newType) => setState(() => selectedBillType = newType),
                              countTypeController: controller.countTypeController,
                            ),
                            const SizedBox(height: 24),
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
        bottomNavigationBar: SafeArea(
          top: false,
          left: false,
          right: false,
          bottom: true,
          child: _buildBottomBar(),
        ),
      ),
    );
  }
}

class _PlateDock extends StatelessWidget {
  final OfflineInputPlateController controller;
  final VoidCallback onActivateFront;
  final VoidCallback onActivateMid;
  final VoidCallback onActivateBack;

  const _PlateDock({
    required this.controller,
    required this.onActivateFront,
    required this.onActivateMid,
    required this.onActivateBack,
  });

  InputDecoration _dec(
      BuildContext context,
      bool active, {
        required Color base,
        required Color light,
      }) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      filled: true,
      fillColor: active ? light.withOpacity(.22) : Colors.white,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: Colors.grey.shade300, width: 1),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: const BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: base, width: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pal = AppCardPalette.of(context);
    final base = pal.parkingBase;
    final light = pal.parkingLight;

    final isFrontActive = controller.activeController == controller.controllerFrontDigit;
    final isMidActive = controller.activeController == controller.controllerMidDigit;
    final isBackActive = controller.activeController == controller.controllerBackDigit;

    return Container(
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Row(
        children: [
          Expanded(
            flex: 28,
            child: GestureDetector(
              onTap: onActivateFront,
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.controllerFrontDigit,
                  readOnly: true,
                  maxLength: controller.isThreeDigit ? 3 : 2,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: _dec(context, isFrontActive, base: base, light: light),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 18,
            child: GestureDetector(
              onTap: onActivateMid,
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.controllerMidDigit,
                  readOnly: true,
                  maxLength: 1,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: _dec(context, isMidActive, base: base, light: light),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 36,
            child: GestureDetector(
              onTap: onActivateBack,
              child: AbsorbPointer(
                child: TextField(
                  controller: controller.controllerBackDigit,
                  readOnly: true,
                  maxLength: 4,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                  decoration: _dec(context, isBackActive, base: base, light: light),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
