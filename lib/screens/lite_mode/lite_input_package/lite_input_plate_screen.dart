import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

// 기존 프로젝트 상태/섹션/위젯 import 그대로 유지
import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart';

import 'lite_input_plate_controller.dart';
import 'sections/lite_input_bill_section.dart';
import 'sections/lite_input_location_section.dart';
import 'sections/lite_input_photo_section.dart';
import 'sections/lite_input_plate_section.dart';
import 'sections/lite_input_bottom_action_section.dart';
import 'sections/lite_input_custom_status_section.dart';

import 'widgets/lite_input_custom_status_bottom_sheet.dart';
import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'widgets/lite_input_bottom_navigation.dart';

import 'lite_live_ocr_page.dart';

import '../../../utils/usage/usage_reporter.dart';

/// 도크에서 어떤 칸을 편집 중인지 구분
enum _DockField { front, mid, back }

class LiteInputPlateScreen extends StatefulWidget {
  const LiteInputPlateScreen({super.key});

  @override
  State<LiteInputPlateScreen> createState() => _LiteInputPlateScreenState();
}

class _LiteInputPlateScreenState extends State<LiteInputPlateScreen> {
  final controller = LiteInputPlateController();

  // ⬇️ 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'lite plate input';

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  bool _openedScannerOnce = false;

  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false; // 현재 열림 상태

  // 도크에서 편집 시작 여부(완료 시 키패드 닫기 위한 플래그)
  _DockField? _dockEditing;

  static const double _sheetClosed = 0.16; // 헤더만 살짝
  static const double _sheetOpened = 1.00; // ★ 최상단까지 (화면 높이 꽉 채움)

  // ✅ 월정기 문서 존재 여부(정기 버튼으로 불러오기 성공했는지)
  bool _monthlyDocExists = false;

  // ✅ monthly_plate_status "메모/상태 반영" 처리 중 플래그(중복 클릭 방지)
  bool _monthlyApplying = false;

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

    // '고정' 제거 이후: 과거 값이 남아있으면 '변동'으로 정규화
    if (controller.selectedBillType == '고정' || controller.selectedBillType.trim().isEmpty) {
      controller.selectedBillType = '변동';
    }

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
          final fetchedList =
              (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];

          final String? fetchedCountType = (data['countType'] as String?)?.trim();

          setState(() {
            controller.fetchedCustomStatus = fetchedStatus;
            controller.customStatusController.text = fetchedStatus ?? '';
            // 토글 UI는 없지만, 서버 값은 메모 섹션에서 참고 가능
            selectedStatusNames = fetchedList;
            statusSectionKey = UniqueKey();

            if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
              controller.countTypeController.text = fetchedCountType;
              controller.selectedBillType = '정기';
              controller.selectedBill = fetchedCountType;

              // ✅ plate_status에서 정기처럼 보이게 세팅되더라도,
              // monthly_plate_status 문서가 있다고 확정할 수는 없으므로 false 유지(사용자 fetch 후 true)
              _monthlyDocExists = false;
            }
          });

          await liteInputCustomStatusBottomSheet(context, plateNumber, area);
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
      debugPrint('[_fetchPlateStatus] FirebaseException: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[_fetchPlateStatus] error: $e');
      return null;
    } finally {
      await UsageReporter.instance.report(
        area: (area.isEmpty ? 'unknown' : area),
        action: 'read',
        n: 1,
        source: 'LiteInputPlateScreen._fetchPlateStatus/plate_status.doc.get',
        useSourceOnlyKey: true,
      );
    }
  }

  /// ✅ monthly_plate_status 단건 조회 (정기 버튼 클릭 시 사용)
  /// ✅ UsageReporter: area 기준 read 1회 보고(성공/실패 불문)
  Future<Map<String, dynamic>?> _fetchMonthlyPlateStatus(String plateNumber, String area) async {
    final docId = '${plateNumber}_$area';
    try {
      final doc = await FirebaseFirestore.instance
          .collection('monthly_plate_status')
          .doc(docId)
          .get();

      if (doc.exists) {
        return doc.data();
      }
      return null;
    } on FirebaseException catch (e) {
      debugPrint('[_fetchMonthlyPlateStatus] FirebaseException: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[_fetchMonthlyPlateStatus] error: $e');
      return null;
    } finally {
      await UsageReporter.instance.report(
        area: (area.isEmpty ? 'unknown' : area),
        action: 'read',
        n: 1,
        source: 'LiteInputPlateScreen._fetchMonthlyPlateStatus/monthly_plate_status.doc.get',
        useSourceOnlyKey: true,
      );
    }
  }

  /// ✅ '정기' 버튼 클릭 시: monthly_plate_status에서 동일 번호판 문서가 있으면 불러와 화면에 출력(반영)
  Future<void> _handleMonthlySelectedFetchAndApply() async {
    // 번호판이 아직 완성되지 않은 상태면 조회하지 않음
    if (!controller.isInputValid()) {
      if (!mounted) return;
      setState(() => _monthlyDocExists = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 입력을 완료한 후 정기 정보를 불러올 수 있습니다.')),
      );
      return;
    }

    final plateNumber = controller.buildPlateNumber();
    final area = context.read<AreaState>().currentArea;

    final data = await _fetchMonthlyPlateStatus(plateNumber, area);
    if (!mounted) return;

    if (data == null) {
      setState(() => _monthlyDocExists = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('해당 번호판의 정기(월정기) 등록 정보가 없습니다.')),
      );
      return;
    }

    final fetchedStatus = (data['customStatus'] as String?)?.trim();
    final fetchedList =
        (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final fetchedCountType = (data['countType'] as String?)?.trim();

    setState(() {
      _monthlyDocExists = true;

      // 메모/상태 출력
      controller.fetchedCustomStatus = fetchedStatus;
      controller.customStatusController.text = fetchedStatus ?? '';
      selectedStatusNames = fetchedList;
      statusSectionKey = UniqueKey();

      // 정기 출력(countType)
      if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
        controller.countTypeController.text = fetchedCountType;
        controller.selectedBill = fetchedCountType;
      }
      // selectedBillType은 이미 '정기'로 바뀐 상태이므로 여기서는 재설정하지 않음
    });

    // 바로 보이도록 시트를 열어줌
    if (!_sheetOpen) {
      await _animateSheet(open: true);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('정기(월정기) 정보를 불러왔습니다.')),
    );
  }

  /// ✅ 월정기( monthly_plate_status )에 "메모/상태"만 반영(merge)
  /// - plate_status는 건드리지 않음
  Future<void> _applyMonthlyMemoAndStatusOnly() async {
    if (_monthlyApplying) return;

    if (!controller.isInputValid()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 입력을 완료한 후 반영할 수 있습니다.')),
      );
      return;
    }

    if (!_monthlyDocExists) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정기(월정기) 문서가 없습니다. 먼저 정기 정보를 불러오거나 등록해 주세요.')),
      );
      return;
    }

    final plateNumber = controller.buildPlateNumber();
    final area = context.read<AreaState>().currentArea;
    final docId = '${plateNumber}_$area';

    final customStatus = controller.customStatusController.text.trim();
    final statusList = List<String>.from(selectedStatusNames);

    setState(() => _monthlyApplying = true);

    try {
      await FirebaseFirestore.instance
          .collection('monthly_plate_status')
          .doc(docId)
          .set(
        {
          // ✅ 핵심: "추가 상태/메모"만 반영
          'customStatus': customStatus,
          'statusList': statusList,
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );

      // ✅ UsageReporter: write 1회
      await UsageReporter.instance.report(
        area: (area.isEmpty ? 'unknown' : area),
        action: 'write',
        n: 1,
        source: 'LiteInputPlateScreen._applyMonthlyMemoAndStatusOnly/monthly_plate_status.doc.set(merge)',
        useSourceOnlyKey: true,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('월정기(정기) 메모/상태가 반영되었습니다.')),
      );
    } on FirebaseException catch (e) {
      debugPrint('[_applyMonthlyMemoAndStatusOnly] FirebaseException: ${e.code} ${e.message}');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('반영 실패: ${e.message ?? e.code}')),
      );
    } catch (e) {
      debugPrint('[_applyMonthlyMemoAndStatusOnly] error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('반영 실패: $e')),
      );
    } finally {
      if (mounted) setState(() => _monthlyApplying = false);
    }
  }

  /// ✅ "반영" 버튼(추가 상태/메모 섹션 하단)
  Widget _buildMonthlyApplyButton() {
    // 정기 탭일 때만 노출
    if (controller.selectedBillType != '정기') {
      return const SizedBox.shrink();
    }

    final enabled = !_monthlyApplying && _monthlyDocExists;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 10),
        SizedBox(
          height: 50,
          child: ElevatedButton(
            onPressed: enabled ? _applyMonthlyMemoAndStatusOnly : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              disabledBackgroundColor: Colors.grey.shade300,
              disabledForegroundColor: Colors.grey.shade600,
              elevation: 0,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _monthlyApplying
                ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
                : const Text(
              '반영',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
        if (!_monthlyDocExists) ...[
          const SizedBox(height: 8),
          Text(
            '정기(월정기) 문서를 불러온 경우에만 반영할 수 있습니다.',
            style: TextStyle(fontSize: 12, color: Colors.black.withOpacity(0.55)),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────
  // 🔽 가운데 임의문자/누락 허용 파서 + 폴백
  // ─────────────────────────────

  static const List<String> _allowedKoreanMids = [
    '가','나','다','라','마','거','너','더','러','머','버','서','어','저',
    '고','노','도','로','모','보','소','오','조','구','누','두','루','무',
    '부','수','우','주','하','허','호','배'
  ];

  static const Map<String, String> _charMap = {
    'O': '0','o': '0','I': '1','l': '1','B': '8','S': '5',
  };

  static const Map<String, String> _midNormalize = {
    '리': '러','이': '어','지': '저','히': '허','기': '거','니': '너','디': '더','미': '머','비': '버','시': '서',
  };

  String _normalize(String s) {
    var t = s.trim().replaceAll(RegExp(r'\s+'), '');
    _charMap.forEach((k, v) => t = t.replaceAll(k, v));
    return t;
  }

  RegExp get _rxStrict {
    final allowed = _allowedKoreanMids.join();
    return RegExp(r'^(\d{2,3})([' + allowed + r'])(\d{4})$');
  }

  final RegExp _rxAnyMid = RegExp(r'^(\d{2,3})(.)(\d{4})$');
  final RegExp _rxOnly7 = RegExp(r'^\d{7}$');
  final RegExp _rxOnly6 = RegExp(r'^\d{6}$');

  void _applyPlateWithFallback(String plate) {
    final raw = _normalize(plate);

    final s = _rxStrict.firstMatch(raw);
    if (s != null) {
      final front = s.group(1)!;
      var mid = s.group(2)!;
      final back = s.group(3)!;

      mid = _midNormalize[mid] ?? mid;

      _applyToFields(front: front, mid: mid, back: back);
      return;
    }

    final a = _rxAnyMid.firstMatch(raw);
    if (a != null) {
      final front = a.group(1)!;
      var mid = a.group(2)!;
      final back = a.group(3)!;

      if (RegExp(r'^[가-힣]$').hasMatch(mid)) {
        final fixed = _midNormalize[mid];
        if (fixed != null) mid = fixed;
      }

      _applyToFields(front: front, mid: mid, back: back);
      return;
    }

    if (_rxOnly7.hasMatch(raw)) {
      final front = raw.substring(0, 3);
      final back = raw.substring(3, 7);
      _applyToFields(front: front, mid: '', back: back, promptMid: true);
      return;
    }

    if (_rxOnly6.hasMatch(raw)) {
      final front = raw.substring(0, 2);
      final back = raw.substring(2, 6);
      _applyToFields(front: front, mid: '', back: back, promptMid: true);
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('인식값 형식 확인 필요: $plate')),
    );
  }

  void _applyToFields({
    required String front,
    required String mid,
    required String back,
    bool promptMid = false,
  }) {
    setState(() {
      controller.setFrontDigitMode(front.length == 3);
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;
      controller.controllerBackDigit.text = back;

      // ✅ 번호판을 OCR로 새로 채우면 월정기 로딩 확정 상태는 초기화
      _monthlyDocExists = false;

      if (promptMid || mid.isEmpty) {
        controller.showKeypad = true;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('가운데 글자가 누락되었습니다. 가운데 한 글자를 입력해 주세요.')),
        );
      } else {
        controller.showKeypad = false;
      }
    });
  }

  Future<void> _openLiveScanner() async {
    final plate = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const LiteLiveOcrPage()),
    );
    if (plate == null) return;

    _applyPlateWithFallback(plate);
  }

  void _beginDockEdit(_DockField field) {
    setState(() {
      _dockEditing = field;

      // ✅ 번호판 수정 시작이면 월정기 로딩 확정 상태는 초기화
      _monthlyDocExists = false;

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
          _monthlyDocExists = false;
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
    final actionButton = LiteInputBottomActionSection(
      controller: controller,
      mountedContext: mounted,
      onStateRefresh: () => setState(() {}),
    );

    final Widget ocrButton = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: ElevatedButton.icon(
        onPressed: _openLiveScanner,
        icon: const Icon(Icons.camera_alt_outlined),
        label: const Text('실시간 OCR 다시 스캔'),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          minimumSize: const Size.fromHeight(55),
          padding: EdgeInsets.zero,
          side: const BorderSide(color: Colors.grey, width: 1.0),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
      ),
    );

    if (controller.showKeypad) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LiteInputBottomNavigation(
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
          ocrButton,
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
          LiteInputBottomNavigation(
            showKeypad: false,
            keypad: const SizedBox.shrink(),
            actionButton: actionButton,
          ),
          ocrButton,
        ],
      );
    }
  }

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
      child: IgnorePointer(
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

  void _handleBackButtonPressed() {
    if (_sheetOpen) {
      _animateSheet(open: false);
      return;
    }
    Navigator.of(context).pop(false);
  }

  @override
  Widget build(BuildContext context) {
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final sysBottom = MediaQuery.of(context).padding.bottom;
    final bottomSafePadding = (controller.showKeypad ? 280.0 : 140.0) + viewInset + sysBottom;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (_sheetOpen) {
          await _animateSheet(open: false);
          return;
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 1,
          flexibleSpace: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _handleBackButtonPressed,
            child: Stack(
              children: [
                _buildScreenTag(context),
                SafeArea(
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '뒤로가기',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: Colors.blueGrey,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 16,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.black,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
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
                        LiteInputPlateSection(
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
                              _monthlyDocExists = false; // ✅ 번호판 변경 흐름에서 월정기 로딩 상태 리셋
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
                        LiteInputLocationSection(locationController: controller.locationController),
                        const SizedBox(height: 16),
                        LiteInputPhotoSection(
                          capturedImages: controller.capturedImages,
                          plateNumber: controller.buildPlateNumber(),
                        ),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),

                // 하단 시트
                DraggableScrollableSheet(
                  controller: _sheetController,
                  initialChildSize: _sheetClosed,
                  minChildSize: _sheetClosed,
                  maxChildSize: _sheetOpened,
                  snap: true,
                  snapSizes: const [_sheetClosed, _sheetOpened],
                  builder: (context, scrollController) {
                    const sheetBg = Color(0xFFF6F8FF);

                    return Container(
                      decoration: const BoxDecoration(
                        color: sheetBg,
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
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
                                        Text(
                                          _sheetOpen ? '정산 유형 / 메모 카드 닫기' : '정산 유형 / 메모 카드 열기',
                                          style: const TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                          ),
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

                            // ⬇️ 정산 영역 (정기 클릭 시 monthly_plate_status에서 조회/반영)
                            LiteInputBillSection(
                              selectedBill: controller.selectedBill,
                              onChanged: (value) => setState(() => controller.selectedBill = value),
                              selectedBillType: controller.selectedBillType,
                              onTypeChanged: (newType) {
                                setState(() {
                                  controller.selectedBillType = newType;
                                  if (newType == '정기') {
                                    _monthlyDocExists = false; // ✅ fetch 결과로 다시 확정
                                  }
                                });

                                if (newType == '정기') {
                                  _handleMonthlySelectedFetchAndApply();
                                }
                              },
                              countTypeController: controller.countTypeController,
                            ),

                            const SizedBox(height: 24),

                            LiteInputCustomStatusSection(
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

                            // ✅ 추가: 메모/상태 하단 "반영" 버튼(정기일 때만 표시)
                            _buildMonthlyApplyButton(),

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

/// 하단 도크: 번호판 입력 3분할을 키패드/액션바 주변에 배치
class _PlateDock extends StatelessWidget {
  final LiteInputPlateController controller;
  final VoidCallback onActivateFront;
  final VoidCallback onActivateMid;
  final VoidCallback onActivateBack;

  const _PlateDock({
    required this.controller,
    required this.onActivateFront,
    required this.onActivateMid,
    required this.onActivateBack,
  });

  InputDecoration _dec(BuildContext context, bool active) {
    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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

  Widget _buildEditableField({
    required BuildContext context,
    required TextEditingController textController,
    required bool isActive,
    required VoidCallback onTap,
    required int maxLength,
  }) {
    final chipColor = isActive ? Colors.amber.shade700 : Colors.grey.shade500;

    return GestureDetector(
      onTap: onTap,
      child: AbsorbPointer(
        child: Stack(
          children: [
            TextField(
              controller: textController,
              readOnly: true,
              maxLength: maxLength,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              decoration: _dec(context, isActive),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(isActive ? 0.18 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.edit_outlined,
                      size: 12,
                      color: chipColor,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      isActive ? '편집중' : '편집',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: chipColor,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isFrontActive = controller.activeController == controller.controllerFrontDigit;
    final isMidActive = controller.activeController == controller.controllerMidDigit;
    final isBackActive = controller.activeController == controller.controllerBackDigit;

    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      color: Colors.grey.shade700,
    );

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
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                flex: 28,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('앞자리', style: labelStyle),
                    const SizedBox(height: 4),
                    _buildEditableField(
                      context: context,
                      textController: controller.controllerFrontDigit,
                      isActive: isFrontActive,
                      onTap: onActivateFront,
                      maxLength: controller.isThreeDigit ? 3 : 2,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 18,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('한글', style: labelStyle),
                    const SizedBox(height: 4),
                    _buildEditableField(
                      context: context,
                      textController: controller.controllerMidDigit,
                      isActive: isMidActive,
                      onTap: onActivateMid,
                      maxLength: 1,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                flex: 36,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('뒷자리', style: labelStyle),
                    const SizedBox(height: 4),
                    _buildEditableField(
                      context: context,
                      textController: controller.controllerBackDigit,
                      isActive: isBackActive,
                      onTap: onActivateBack,
                      maxLength: 4,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.touch_app,
                size: 14,
                color: Colors.grey.shade600,
              ),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '번호판 각 칸을 탭하면 해당 자리를 수정할 수 있습니다.',
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade700,
                  ),
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
