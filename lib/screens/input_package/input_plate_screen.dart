// lib/screens/input_package/input_plate_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 기존 프로젝트 상태/섹션/위젯 import 그대로 유지
import '../../states/bill/bill_state.dart';
import '../../states/area/area_state.dart';

import 'input_plate_controller.dart';
import 'sections/input_bill_section.dart';
import 'sections/input_location_section.dart';
import 'sections/input_photo_section.dart';
import 'sections/input_plate_section.dart';
import 'sections/input_bottom_action_section.dart';
import 'sections/input_custom_status_section.dart';

import 'widgets/input_custom_status_bottom_sheet.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'widgets/input_bottom_navigation.dart';

import 'live_ocr_page.dart';

import '../../utils/usage_reporter.dart';

class InputPlateScreen extends StatefulWidget {
  const InputPlateScreen({super.key});

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {
  final controller = InputPlateController();

  // ⬇️ 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'plate input';

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
      if (text.length == 4 && controller.isInputValid()) {
        final plateNumber = controller.buildPlateNumber();
        final area = context.read<AreaState>().currentArea;
        final data = await _fetchPlateStatus(plateNumber, area);

        if (mounted && data != null) {
          final fetchedStatus = data['customStatus'] as String?;
          final fetchedList = (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          final String? fetchedCountType = (data['countType'] as String?)?.trim();

          setState(() {
            controller.fetchedCustomStatus = fetchedStatus;
            controller.customStatusController.text = fetchedStatus ?? '';
            // 토글 UI는 없지만, 서버 값은 메모 섹션에서 참고 가능
            selectedStatusNames = fetchedList;
            statusSectionKey = UniqueKey();

            if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
              controller.countTypeController.text = fetchedCountType;
              selectedBillType = '정기';
              controller.selectedBillType = '정기';
              controller.selectedBill = fetchedCountType;
            }
          });

          await inputCustomStatusBottomSheet(context, plateNumber, area);
        }
      }
    });

    // 기존 bill 캐시 로드
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final billState = context.read<BillState>();
      await billState.loadFromBillCache();
      if (!mounted) return;
      setState(() {
        controller.isLocationSelected = controller.locationController.text.isNotEmpty;
      });
    });

    // ⬇️ 첫 빌드 직후 한 번만 자동으로 LiveOcrPage 열기
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_openedScannerOnce) return;
      _openedScannerOnce = true;
      await _openLiveScanner(); // 사용자가 닫으면 plate == null 로 처리
    });
  }

  @override
  void dispose() {
    // ✅ 컨트롤러 정리
    _sheetController.dispose();
    controller.dispose();
    super.dispose();
  }

  /// plate_status 단건 조회
  /// ✅ UsageReporter: area 기준 read 1회 보고(성공/실패 불문)
  Future<Map<String, dynamic>?> _fetchPlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    try {
      final doc = await FirebaseFirestore.instance.collection('plate_status').doc(docId).get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } on FirebaseException catch (e) {
      // 필요 시 UI 로그/스낵바 등 처리 가능
      debugPrint('[_fetchPlateStatus] FirebaseException: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[_fetchPlateStatus] error: $e');
      return null;
    } finally {
      // ⬇️ installId prefix 없이 source 슬러그만으로 집계
      await UsageReporter.instance.report(
        area: (area.isEmpty ? 'unknown' : area),
        action: 'read',
        n: 1,
        source: 'InputPlateScreen._fetchPlateStatus/plate_status.doc.get',
        useSourceOnlyKey: true, // ★ 중요
      );
    }
  }

  // ─────────────────────────────
  // 🔽 가운데 임의문자/누락 허용 파서 + 폴백
  // ─────────────────────────────

  // 허용 한글 가운데 글자(국내 번호판)
  static const List<String> _allowedKoreanMids = [
    '가','나','다','라','마','거','너','더','러','머','버','서','어','저',
    '고','노','도','로','모','보','소','오','조','구','누','두','루','무','부','수','우','주',
    '하','허','호','배'
  ];

  // 흔한 OCR 혼동 치환
  static const Map<String, String> _charMap = {
    'O': '0', 'o': '0',
    'I': '1', 'l': '1',
    'B': '8', 'S': '5',
  };

  // 가운데 글자 보정(리→러 등)
  static const Map<String, String> _midNormalize = {
    '리': '러',
    '이': '어',
    '지': '저',
    '히': '허',
    '기': '거',
    '니': '너',
    '디': '더',
    '미': '머',
    '비': '버',
    '시': '서',
  };

  String _normalize(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s+'), '');
    _charMap.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  /// 엄격: (2~3)숫자 + (허용한글 1) + (4)숫자
  RegExp get _rxStrict {
    final allowed = _allowedKoreanMids.join();
    return RegExp(r'^(\d{2,3})([' + allowed + r'])(\d{4})$');
    // 예: 12가3456, 123허4567
  }

  /// 임의문자 허용: (2~3)숫자 + (.) + (4)숫자
  final RegExp _rxAnyMid = RegExp(r'^(\d{2,3})(.)(\d{4})$');

  /// 누락 케이스: 숫자만 7(3+4) 또는 6(2+4)
  final RegExp _rxOnly7 = RegExp(r'^\d{7}$');
  final RegExp _rxOnly6 = RegExp(r'^\d{6}$');

  /// 스캐너에서 돌아온 plate 문자열을 엄격→임의문자→숫자만 순서로 파싱하여 적용
  void _applyPlateWithFallback(String plate) {
    final raw = _normalize(plate);

    // 1) 엄격
    final s = _rxStrict.firstMatch(raw);
    if (s != null) {
      final front = s.group(1)!;
      var mid = s.group(2)!;
      final back = s.group(3)!;

      // 가운데 보정(있으면)
      mid = _midNormalize[mid] ?? mid;

      _applyToFields(front: front, mid: mid, back: back);
      return;
    }

    // 2) 임의문자 허용
    final a = _rxAnyMid.firstMatch(raw);
    if (a != null) {
      final front = a.group(1)!;
      var mid = a.group(2)!; // 한글이 아니어도 그대로 수용
      final back = a.group(3)!;

      // 한글이면 보정 후 허용 목록 안에 있으면 치환(선택적)
      if (RegExp(r'^[가-힣]$').hasMatch(mid)) {
        final fixed = _midNormalize[mid];
        if (fixed != null) mid = fixed;
      }

      _applyToFields(front: front, mid: mid, back: back);
      return;
    }

    // 3) 숫자만 7자리 → 3+4 (가운데 누락)
    if (_rxOnly7.hasMatch(raw)) {
      final front = raw.substring(0, 3);
      final back = raw.substring(3, 7);
      _applyToFields(front: front, mid: '', back: back, promptMid: true);
      return;
    }

    // 4) 숫자만 6자리 → 2+4 (가운데 누락)
    if (_rxOnly6.hasMatch(raw)) {
      final front = raw.substring(0, 2);
      final back = raw.substring(2, 6);
      _applyToFields(front: front, mid: '', back: back, promptMid: true);
      return;
    }

    // 그 외: 형식 불명 → 사용자 안내
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('인식값 형식 확인 필요: $plate')),
    );
  }

  /// 컨트롤러와 키패드/포커스를 실제로 갱신
  void _applyToFields({
    required String front,
    required String mid,
    required String back,
    bool promptMid = false, // 가운데 누락 시 true로 주면 중간칸 포커스 + 키패드 오픈
  }) {
    setState(() {
      controller.setFrontDigitMode(front.length == 3);
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;   // 임의문자 허용
      controller.controllerBackDigit.text = back;

      if (promptMid || mid.isEmpty) {
        controller.setActiveController(controller.controllerMidDigit);
        controller.showKeypad = true;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가운데 글자가 누락되었습니다. 가운데 한 글자를 입력해 주세요.')),
        );
      } else {
        controller.showKeypad = false;
      }
    });
  }

  // ─────────────────────────────

  // 🔽 스캐너로 이동 → 성공 시 입력칸 자동 채우기 (사용자가 닫으면 plate == null)
  Future<void> _openLiveScanner() async {
    final plate = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const LiveOcrPage()),
    );
    if (plate == null) return; // 사용자가 LiveOcrPage를 넘긴(닫은) 경우

    _applyPlateWithFallback(plate);
  }

  Widget _buildKeypad() {
    final active = controller.activeController;

    if (active == controller.controllerFrontDigit) {
      return NumKeypad(
        key: const ValueKey('frontKeypad'),
        controller: controller.controllerFrontDigit,
        maxLength: controller.isThreeDigit ? 3 : 2,
        onComplete: () =>
            setState(() => controller.setActiveController(controller.controllerMidDigit)),
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
        onComplete: () =>
            setState(() => controller.setActiveController(controller.controllerBackDigit)),
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

  // ⬇️ showKeypad일 때, 번호판 도크 + 키패드를 함께 표시
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

  // 좌측 상단(11시) 화면 태그 위젯
  Widget _buildScreenTag(BuildContext context) {
    final base = Theme.of(context).textTheme.labelSmall;
    final style = (base ??
        const TextStyle(
          fontSize: 11,
          color: Colors.black54,
          fontWeight: FontWeight.w600,
        ))
        .copyWith(
      color: Colors.black54,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.2,
    );

    return SafeArea(
      child: IgnorePointer( // 제스처 간섭 방지
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $screenTag',
              child: Text(screenTag, style: style),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ✅ 키보드/인셋 + 시스템 하단 안전영역 반영
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final sysBottom = MediaQuery.of(context).padding.bottom;
    final bottomSafePadding = (controller.showKeypad ? 280.0 : 140.0) + viewInset + sysBottom;

    // 🔽 뒤로가기: 시트가 열려 있으면 먼저 닫고, 닫혀 있으면 pop 허용
    return PopScope(
      canPop: !_sheetOpen,
      onPopInvoked: (didPop) async {
        if (didPop) return; // 이미 pop된 경우
        if (_sheetOpen) {
          await _animateSheet(open: false); // 시트 먼저 닫기
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          // ⬇️ 좌측 상단(11시)에 'plate input' 텍스트 고정
          flexibleSpace: _buildScreenTag(context),
          title: Align(
            alignment: Alignment.centerRight,
            child: Text(
              controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.black),
            ),
          ),
          actions: [
            // 수동으로도 다시 열 수 있도록 버튼 유지
            IconButton(
              tooltip: '실시간 OCR 스캔',
              onPressed: _openLiveScanner,
              icon: const Icon(Icons.auto_awesome_motion),
            ),
          ],
        ),
        body: LayoutBuilder(
          builder: (context, constraints) {
            return Stack(
              children: [
                // 상단(기본) 콘텐츠: 번호판/위치/사진 섹션 — ✅ 세로 스크롤 가능
                Positioned.fill(
                  child: SingleChildScrollView(
                    // 🔹 작은 폰 보완: 항상 세로 스크롤 가능 + 드래그 시 키보드 닫기
                    physics: const AlwaysScrollableScrollPhysics(),
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // ⚠️ 업종 드롭다운은 보통 InputPlateSection 내부에 있으므로
                        // 그 파일에서 숨겨야 UI에서 완전히 사라집니다.
                        InputPlateSection(
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
                              // 필요 시 아래 라인 활성화하면 탭 시 항상 하단 키패드+도크가 열립니다.
                              // controller.showKeypad = true;
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
                        InputLocationSection(locationController: controller.locationController),
                        const SizedBox(height: 16),
                        InputPhotoSection(
                          capturedImages: controller.capturedImages,
                          plateNumber: controller.buildPlateNumber(),
                        ),
                        // 필요 시 추가 안내/여백
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // 하단 시트: 컨트롤러로 열고 닫을 때 애니메이션 + 최상단까지 열림
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _sheetClosed,
                  minChildSize: _sheetClosed,
                  maxChildSize: _sheetOpened,
                  // ★ 1.0 = 최상단까지
                  snap: true,
                  snapSizes: const [_sheetClosed, _sheetOpened],
                  builder: (context, scrollController) {
                    // 메인 배경(화이트)와 구분되는 아주 옅은 톤
                    const sheetBg = Color(0xFFF6F8FF); // subtle blue-tinted light gray

                    return Container(
                      decoration: const BoxDecoration(
                        color: sheetBg, // 기존: Colors.white
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      // ✅ SafeArea: 상단만 보호 / 하단은 우리가 직접 패딩 관리
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
                            16 + (controller.showKeypad ? 260 : 100) + viewInset + sysBottom,
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
                                        // 핸들 색도 살짝 진하게 해서 대비 ↑ (선택)
                                        color: Colors.black38, // 기존: Colors.black26
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                      children: [
                                        Text(
                                          _sheetOpen ? '정산 유형 / 메모 카드 닫기' : '정산 유형 / 메모 카드 열기',
                                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
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
                            InputBillSection(
                              selectedBill: controller.selectedBill,
                              onChanged: (value) => setState(() => controller.selectedBill = value),
                              selectedBillType: selectedBillType,
                              onTypeChanged: (newType) => setState(() => selectedBillType = newType),
                              countTypeController: controller.countTypeController,
                            ),

                            const SizedBox(height: 24),

                            // 차량 상태 토글은 제거, 메모 섹션만 유지
                            InputCustomStatusSection(
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
        // ✅ 하단 제스처 바와 겹치지 않게 SafeArea로 감싸기
        bottomNavigationBar: SafeArea(
          top: false, left: false, right: false, bottom: true,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InputBottomNavigation(
                showKeypad: controller.showKeypad,
                keypad: _buildDockAndKeypad(), // ★ 도크 + 키패드 묶음
                actionButton: InputBottomActionSection(
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
      ),
    );
  }
}

/// 하단 도크: 번호판 입력 3분할을 키패드 바로 위에 고정해 시선/손 집중을 돕는다.
class _PlateDock extends StatelessWidget {
  final InputPlateController controller;
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
      fillColor: active ? Colors.yellow.shade50 : Colors.white,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: active ? Colors.amber : Colors.grey.shade300,
          width: active ? 2 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: Colors.amber.shade700,
          width: 2,
        ),
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
