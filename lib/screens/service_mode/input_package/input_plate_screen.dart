// lib/screens/input_package/input_plate_screen.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart';

import '../../../repositories/plate_repo_services/firestore_plate_repository.dart';

import '../../../theme.dart';
import 'input_plate_controller.dart';
import 'sections/input_bill_section.dart';
import 'sections/input_location_section.dart';
import 'sections/input_photo_section.dart';
import 'sections/input_plate_section.dart';
import 'sections/input_bottom_action_section.dart';
import 'sections/input_custom_status_section.dart';

import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'widgets/input_bottom_navigation.dart';

import 'live_ocr_page.dart';

import '../../../utils/usage/usage_reporter.dart';

/// 도크에서 어떤 칸을 편집 중인지 구분
enum _DockField { front, mid, back }

class InputPlateScreen extends StatefulWidget {
  const InputPlateScreen({super.key});

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {
  final controller = InputPlateController();

  // ✅ Firestore/Repository 캐싱
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestorePlateRepository _plateRepo = FirestorePlateRepository();

  // ⬇️ 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'plate input';

  // ✅ DashboardSetting에서 저장한 단일 플래그 키
  static const String _prefsHasMonthlyKey = 'has_monthly_parking';

  // ✅ Firestore 경로 상수(정책 고정)
  static const String _plateStatusRoot = 'plate_status';
  static const String _monthsSub = 'months';
  static const String _platesSub = 'plates';
  static const String _monthlyPlateStatusRoot = 'monthly_plate_status';

  // ✅ UsageReporter: source-only key 사용 시 핫스팟 완화용 샤딩 수
  // - QPS가 커질수록(동일 source로 write 집중) 더 크게 잡는 것이 유리
  // - 과도하게 크게 잡으면 집계 시 합산 대상 문서 수가 늘어남(트레이드오프)
  static const int _usageSourceShardCount = 16;

  // ✅ 현재 기기 로컬 플래그(정기 선택 가능 여부)
  bool _hasMonthlyParking = false;
  bool _hasMonthlyLoaded = false;

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  bool _openedScannerOnce = false;

  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false; // 현재 열림 상태

  // ✅ 시트 내부 스크롤 컨트롤러(닫힘에서 스크롤 잠금/원복을 위해 보관)
  ScrollController? _sheetScrollController;

  // 도크에서 편집 시작 여부(완료 시 키패드 닫기 위한 플래그)
  _DockField? _dockEditing;

  static const double _sheetClosed = 0.16; // 헤더만 살짝
  static const double _sheetOpened = 1.00; // 최상단까지

  // ✅ 월정기 문서 존재 여부(정기에서 불러오기 성공했는지)
  bool _monthlyDocExists = false;

  // ✅ monthly_plate_status "메모/상태 반영" 처리 중 플래그(중복 클릭 방지)
  bool _monthlyApplying = false;

  // ✅ 월정기 로드 시 실제로 사용한 단일 docId 저장 (후속 update 대상 docId 보장)
  String? _resolvedMonthlyDocId;

  // ─────────────────────────────
  // ✅ 도커 내부 페이지(정산 유형 / 추가 상태·메모) 전환
  // ─────────────────────────────
  static const int _dockPageBill = 0;
  static const int _dockPageMemo = 1;

  int _dockPageIndex = _dockPageBill;
  bool _dockSlideFromRight = true;

  // ─────────────────────────────
  // ✅ plate_status get 성공 시 사용자 인지용 다이얼로그 제어
  // ─────────────────────────────
  String? _lastPlateStatusDialogKey;
  bool _plateStatusDialogShowing = false;

  // ─────────────────────────────
  // ✅ 문서명 정책 유틸 (단일 docId만 사용)
  // ─────────────────────────────

  /// area가 비어있으면 Firestore doc('') 불가/정책 일관성 깨짐 → 안전 처리
  String _safeArea(String area) {
    final a = area.trim();
    return a.isEmpty ? 'unknown' : a;
  }

  /// yyyyMM
  String _monthKey(DateTime dt) => '${dt.year}${dt.month.toString().padLeft(2, '0')}';

  /// ✅ 번호판 문자열을 정책 형태로 정규화: "59-라-3974" 형태(하이픈 포함)
  /// - 입력이 이미 "59-라-3974"면 그대로 유지
  /// - 입력이 "59라3974"처럼 들어오면 "59-라-3974"로 변환
  /// - 정규식에 맞지 않으면 원문(trim/공백 제거) 사용
  String _canonicalPlateNumber(String plateNumber) {
    final t = plateNumber.trim().replaceAll(' ', '');
    final raw = t.replaceAll('-', '');
    final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(raw);
    if (m == null) return t;
    return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
  }

  /// ✅ 단일 docId 규칙: "{plate(하이픈 포함)}_{area}"
  String _plateDocId(String plateNumber, String area) {
    final a = _safeArea(area);
    final p = _canonicalPlateNumber(plateNumber);
    return '${p}_$a';
  }

  // ✅ SharedPreferences에서 has_monthly_parking 로드
  Future<void> _loadHasMonthlyParkingFlag() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final v = prefs.getBool(_prefsHasMonthlyKey) ?? false;

      if (!mounted) return;
      if (!_hasMonthlyLoaded || _hasMonthlyParking != v) {
        setState(() {
          _hasMonthlyParking = v;
          _hasMonthlyLoaded = true;
        });
      }
    } catch (e) {
      debugPrint('has_monthly_parking 로드 실패: $e');
      if (!mounted) return;
      if (!_hasMonthlyLoaded) {
        setState(() {
          _hasMonthlyParking = false;
          _hasMonthlyLoaded = true;
        });
      }
    }
  }

  void _jumpSheetScrollToTop() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final sc = _sheetScrollController;
        if (sc != null && sc.hasClients) {
          sc.jumpTo(0);
        }
      } catch (_) {
        // ignore
      }
    });
  }

  void _resetDockToBillPage() {
    if (!mounted) return;
    setState(() {
      _dockSlideFromRight = false;
      _dockPageIndex = _dockPageBill;
    });
    _jumpSheetScrollToTop();
  }

  void _setDockPage(int index) {
    if (index == _dockPageIndex) return;
    if (!mounted) return;

    setState(() {
      _dockSlideFromRight = index > _dockPageIndex;
      _dockPageIndex = index;
    });

    _jumpSheetScrollToTop();
  }

  void _handleDockHorizontalSwipe(DragEndDetails details, {required bool canSwipe}) {
    if (!canSwipe) return;

    final v = details.primaryVelocity ?? 0.0;
    if (v.abs() < 250) return;

    if (v < 0) {
      _setDockPage(_dockPageMemo);
    } else {
      _setDockPage(_dockPageBill);
    }
  }

  bool _isSheetFullyClosed() {
    try {
      if (!_sheetController.isAttached) return false;
      return (_sheetController.size <= _sheetClosed + 0.0005);
    } catch (_) {
      return false;
    }
  }

  Future<void> _animateSheet({required bool open}) async {
    final target = open ? _sheetOpened : _sheetClosed;

    // ✅ 열 때마다 항상 정산 유형 페이지에서 시작
    if (open) {
      _resetDockToBillPage();
    }

    // ✅ 닫을 때는 내부 스크롤을 최상단으로 되돌림
    if (!open) {
      try {
        final sc = _sheetScrollController;
        if (sc != null && sc.hasClients) {
          sc.jumpTo(0);
        }
      } catch (_) {
        // ignore
      }
    }

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

  Future<void> _openSheetToMemoPage() async {
    if (!_sheetOpen) {
      await _animateSheet(open: true); // open 시 bill로 리셋됨
    }
    if (!mounted) return;
    _setDockPage(_dockPageMemo);
  }

  /// ✅ (UI/UX 리팩터링) plate_status get 성공 시 사용자 인지용 Modern Dialog
  /// - 요구사항: Dialog에서는 countType/statusList를 보여주지 않음
  /// - 표시: area, plate, customStatus(메모)만 표시
  /// - CTA: "상태 메모 보기" → 시트 열고 메모 탭 이동
  Future<void> _showPlateStatusLoadedDialog({
    required String plateNumber,
    required String area,
    String? customStatus,
  }) async {
    if (!mounted) return;

    final safeArea = _safeArea(area);
    final customStatusText = (customStatus ?? '').trim().isEmpty ? '-' : customStatus!.trim();

    // ✅ AppCardPalette(service*) 컬러를 Dialog 오버레이에도 반영
    final palette = AppCardPalette.of(context);

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'plate_status_loaded',
      barrierColor: palette.serviceDark.withOpacity(0.60),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (ctx, a1, a2) {
        return Center(
          child: _PlateStatusLoadedDialog(
            safeArea: safeArea,
            plateNumber: plateNumber,
            customStatusText: customStatusText,
            onClose: () => Navigator.of(ctx).pop(),
            onGoMemo: () async {
              Navigator.of(ctx).pop();
              await _openSheetToMemoPage();
            },
          ),
        );
      },
      transitionBuilder: (ctx, animation, secondary, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1.0).animate(curved),
            child: child,
          ),
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();

    // ✅ 화면 진입 시 로컬 플래그 로드
    _loadHasMonthlyParkingFlag();

    // ⬇️ 시트 사이즈 변화에 따라 _sheetOpen 동기화 (드래그로 여닫을 때도 반영)
    _sheetController.addListener(() {
      try {
        final s = _sheetController.size;
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);

        if (openNow != _sheetOpen && mounted) {
          setState(() {
            _sheetOpen = openNow;

            // ✅ 드래그로 열려도 항상 bill 페이지로 시작
            if (openNow) {
              _dockSlideFromRight = false;
              _dockPageIndex = _dockPageBill;
            }
          });

          if (openNow) {
            _jumpSheetScrollToTop();
          }
        }

        // ✅ 완전 닫힘 상태에서는 내부 스크롤 offset을 0으로 강제
        if (_isSheetFullyClosed()) {
          final sc = _sheetScrollController;
          if (sc != null && sc.hasClients && sc.offset != 0) {
            sc.jumpTo(0);
          }
        }
      } catch (_) {
        // ignore
      }
    });

    controller.controllerBackDigit.addListener(() async {
      final text = controller.controllerBackDigit.text;

      // ✅ 입력 완료(뒷자리 4자리 + 전체 유효) 시 plate_status 조회
      if (text.length == 4 && controller.isInputValid()) {
        final plateNumber = controller.buildPlateNumber();
        final area = context.read<AreaState>().currentArea;

        // ✅ 입력 완료 시에는 "plate_status" 조회 (월샤딩 + 단일 docId)
        final data = await _fetchPlateStatus(plateNumber, area);

        if (!mounted || data == null) return;

        final fetchedStatus = (data['customStatus'] as String?)?.trim();
        final fetchedList =
            (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final String? fetchedCountType = (data['countType'] as String?)?.trim();

        // ✅ UI 반영은 기존대로 유지(요구사항은 "Dialog 노출"만 제외)
        setState(() {
          controller.fetchedCustomStatus = fetchedStatus;
          controller.customStatusController.text = fetchedStatus ?? '';
          selectedStatusNames = fetchedList;
          statusSectionKey = UniqueKey();

          if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
            controller.countTypeController.text = fetchedCountType;
            controller.selectedBillType = '정기';
            controller.selectedBill = fetchedCountType;

            // monthly 문서 존재 여부는 "정기 불러오기"로 확정
            _monthlyDocExists = false;
            _resolvedMonthlyDocId = null;
          } else {
            _monthlyDocExists = false;
            _resolvedMonthlyDocId = null;
          }
        });

        // ✅ Dialog 중복 표시 방지 (단일 docId 기반 키)
        final dialogKey = _plateDocId(plateNumber, area);
        if (_plateStatusDialogShowing) return;
        if (_lastPlateStatusDialogKey == dialogKey) return;

        _plateStatusDialogShowing = true;
        _lastPlateStatusDialogKey = dialogKey;

        try {
          // ✅ Dialog에는 customStatus(메모)만 전달/표시
          await _showPlateStatusLoadedDialog(
            plateNumber: plateNumber,
            area: area,
            customStatus: fetchedStatus,
          );
        } finally {
          _plateStatusDialogShowing = false;
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
      await _openLiveScanner();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // ✅ 다른 화면에서 refresh 후 돌아오는 경우를 대비해 재로드(비용 매우 낮음)
    _loadHasMonthlyParkingFlag();
  }

  @override
  void dispose() {
    _sheetController.dispose();

    // ✅ UsageReporter는 버퍼링 후 배치 커밋 → 화면 종료 직전 flush(best-effort)
    try {
      UsageReporter.instance.flush();
    } catch (_) {
      // ignore
    }

    controller.dispose();
    super.dispose();
  }

  /// plate_status 단건 조회 (월 단위 샤딩 구조 + 단일 docId)
  ///
  /// ✅ 저장 구조:
  ///   plate_status/{area}/months/{yyyyMM}/plates/{plateDocId}
  ///
  /// ✅ (핵심) plateDocId 정책(단일):
  ///   plateDocId = "{plate(하이픈 포함)}_{area}"
  ///
  /// ✅ 조회 정책:
  ///   - 현재월 → 직전월(최대 2개월) 우선
  ///   - 실패 시 collectionGroup('plates')로 전체월 폴백(단일 docId로만, 규칙/인덱스 제한 시 자동 무시)
  Future<Map<String, dynamic>?> _fetchPlateStatus(String plateNumber, String area) async {
    int reads = 0;

    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    final now = DateTime.now();
    final monthsToTry = <DateTime>[
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month - 1, 1),
    ];

    try {
      // 1) 빠른 경로: 현재월/전월 (단일 docId만 get)
      for (final m in monthsToTry) {
        final mk = _monthKey(m);

        final doc = await _firestore
            .collection(_plateStatusRoot)
            .doc(safeArea)
            .collection(_monthsSub)
            .doc(mk)
            .collection(_platesSub)
            .doc(docId)
            .get();
        reads += 1;

        if (doc.exists) return doc.data();
      }

      // 2) 느린 경로: 최근 2개월에 없으면 전체 월에서 검색(collectionGroup)
      //    - 규칙/인덱스 미지원이면 FirebaseException 발생 가능 → 캐치 후 무시
      try {
        final qs = await _firestore
            .collectionGroup(_platesSub)
            .where(FieldPath.documentId, isEqualTo: docId)
            .get();
        reads += 1;

        if (qs.docs.isNotEmpty) {
          QueryDocumentSnapshot<Map<String, dynamic>>? best;
          int bestMonth = -1;

          for (final d in qs.docs) {
            final path = d.reference.path; // plate_status/{area}/months/{yyyyMM}/plates/{docId}
            if (!path.contains('$_plateStatusRoot/$safeArea/$_monthsSub/')) continue;

            final parts = path.split('/');
            final monthsIndex = parts.indexOf(_monthsSub);
            if (monthsIndex < 0 || monthsIndex + 1 >= parts.length) continue;

            final mk = parts[monthsIndex + 1];
            final mkInt = int.tryParse(mk) ?? -1;

            if (mkInt > bestMonth) {
              bestMonth = mkInt;
              best = d;
            }
          }

          if (best != null) return best.data();
          return qs.docs.first.data();
        }
      } on FirebaseException catch (e) {
        debugPrint('[collectionGroup fallback blocked] ${e.code} ${e.message}');
      }

      return null;
    } on FirebaseException catch (e) {
      debugPrint('[_fetchPlateStatus] FirebaseException: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[_fetchPlateStatus] error: $e');
      return null;
    } finally {
      final nToReport = (reads <= 0) ? 1 : reads;

      try {
        await UsageReporter.instance.report(
          area: safeArea,
          action: 'read',
          n: nToReport,
          source: 'InputPlateScreen._fetchPlateStatus/plate_status.lookup',
          useSourceOnlyKey: true,
          sourceShardCount: _usageSourceShardCount,
        );
      } catch (e) {
        debugPrint('[UsageReporter] report failed in _fetchPlateStatus: $e');
      }
    }
  }

  Future<Map<String, dynamic>?> _fetchMonthlyPlateStatus(String plateNumber, String area) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    try {
      final doc = await _firestore.collection(_monthlyPlateStatusRoot).doc(docId).get();
      if (doc.exists) {
        _resolvedMonthlyDocId = docId; // ✅ 단일 docId 확정
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
      try {
        await UsageReporter.instance.report(
          area: safeArea,
          action: 'read',
          n: 1,
          source: 'InputPlateScreen._fetchMonthlyPlateStatus/monthly_plate_status.lookup',
          useSourceOnlyKey: true,
          sourceShardCount: _usageSourceShardCount,
        );
      } catch (e) {
        debugPrint('[UsageReporter] report failed in _fetchMonthlyPlateStatus: $e');
      }
    }
  }

  /// '정기' 선택 시 monthly_plate_status에서 불러와 화면에 반영
  Future<void> _handleMonthlySelectedFetchAndApply() async {
    if (!controller.isInputValid()) {
      if (!mounted) return;
      setState(() {
        _monthlyDocExists = false;
        _resolvedMonthlyDocId = null;
      });
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
      setState(() {
        _monthlyDocExists = false;
        _resolvedMonthlyDocId = null;
      });
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

      controller.fetchedCustomStatus = fetchedStatus;
      controller.customStatusController.text = fetchedStatus ?? '';
      selectedStatusNames = fetchedList;
      statusSectionKey = UniqueKey();

      if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
        controller.countTypeController.text = fetchedCountType;
        controller.selectedBill = fetchedCountType;
      }
    });

    if (!_sheetOpen) {
      await _animateSheet(open: true);
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('정기(월정기) 정보를 불러왔습니다.')),
    );
  }

  /// 월정기(monthly_plate_status)에 "메모/상태"만 반영(update)
  Future<void> _applyMonthlyMemoAndStatusOnly() async {
    if (_monthlyApplying) return;

    if (!controller.isInputValid()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 입력을 완료한 후 반영할 수 있습니다.')),
      );
      return;
    }

    if (!_monthlyDocExists ||
        (_resolvedMonthlyDocId == null || _resolvedMonthlyDocId!.trim().isEmpty)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('정기(월정기) 문서가 없습니다. 먼저 정기 정보를 불러오거나 등록해 주세요.')),
      );
      return;
    }

    final plateNumber = controller.buildPlateNumber();
    final area = context.read<AreaState>().currentArea;

    final customStatus = controller.customStatusController.text.trim();
    final statusList = List<String>.from(selectedStatusNames);

    setState(() => _monthlyApplying = true);

    try {
      await _plateRepo.setMonthlyMemoAndStatusOnly(
        plateNumber: plateNumber,
        area: area,
        createdBy: 'system',
        customStatus: customStatus,
        statusList: statusList,
        skipIfDocMissing: false,
      );

      try {
        await UsageReporter.instance.report(
          area: _safeArea(area),
          action: 'write',
          n: 1,
          source: 'InputPlateScreen._applyMonthlyMemoAndStatusOnly/monthly_plate_status.doc.update',
          useSourceOnlyKey: true,
          sourceShardCount: _usageSourceShardCount,
        );
      } catch (e) {
        debugPrint('[UsageReporter] report failed in _applyMonthlyMemoAndStatusOnly: $e');
      }

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

  /// "반영" 버튼(추가 상태/메모 섹션 하단) - 정기일 때만 노출
  Widget _buildMonthlyApplyButton() {
    if (controller.selectedBillType != '정기') {
      return const SizedBox.shrink();
    }

    final enabled = !_monthlyApplying && _monthlyDocExists && (_resolvedMonthlyDocId != null);

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
    '가','나','다','라','마','거','너','더','러','머','버','서','어','저','고','노','도','로','모','보','소','오','조','구','누','두','루','무','부','수','우','주','하','허','호','배'
  ];

  static const Map<String, String> _charMap = {
    'O': '0',
    'o': '0',
    'I': '1',
    'l': '1',
    'B': '8',
    'S': '5',
  };

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
      _resolvedMonthlyDocId = null;

      // ✅ 번호판이 새로 채워졌으므로 안내 다이얼로그 중복 키 초기화
      _lastPlateStatusDialogKey = null;

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
      MaterialPageRoute(builder: (_) => const LiveOcrPage()),
    );
    if (plate == null) return;

    _applyPlateWithFallback(plate);
  }

  /// 도크에서 특정 칸 편집 시작
  void _beginDockEdit(_DockField field) {
    setState(() {
      _dockEditing = field;

      _monthlyDocExists = false;
      _resolvedMonthlyDocId = null;

      // ✅ 편집 시작 → 안내 다이얼로그 중복 키 초기화
      _lastPlateStatusDialogKey = null;

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
          _resolvedMonthlyDocId = null;

          // ✅ 입력 초기화 → 안내 다이얼로그 중복 키 초기화
          _lastPlateStatusDialogKey = null;
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
    final actionButton = InputBottomActionSection(
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
          InputBottomNavigation(
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
          InputBottomNavigation(
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

  Widget _buildDockPagedBody({required bool canSwipe}) {
    final Widget page = (_dockPageIndex == _dockPageBill)
        ? Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_hasMonthlyLoaded && !_hasMonthlyParking)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF8E1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFFECB3)),
              ),
              child: const Text(
                '정기 주차가 제한된 근무지입니다.',
                style: TextStyle(fontSize: 12, height: 1.25),
              ),
            ),
          ),
        InputBillSection(
          selectedBill: controller.selectedBill,
          onChanged: (value) => setState(() => controller.selectedBill = value),
          selectedBillType: controller.selectedBillType,
          onTypeChanged: (newType) {
            if (newType == '정기' && _hasMonthlyLoaded && !_hasMonthlyParking) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('현재 지역에서는 정기(월주차) 기능을 사용할 수 없습니다.')),
              );
              return;
            }

            setState(() {
              controller.selectedBillType = newType;
              _monthlyDocExists = false;
              _resolvedMonthlyDocId = null;
            });

            if (newType == '정기') {
              _handleMonthlySelectedFetchAndApply();
            }
          },
          countTypeController: controller.countTypeController,
        ),
      ],
    )
        : Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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
        _buildMonthlyApplyButton(),
        const SizedBox(height: 8),
      ],
    );

    final content = AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        final begin = _dockSlideFromRight ? const Offset(0.10, 0) : const Offset(-0.10, 0);
        final offsetAnim = Tween<Offset>(begin: begin, end: Offset.zero).animate(animation);
        return SlideTransition(
          position: offsetAnim,
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      child: KeyedSubtree(
        key: ValueKey<int>(_dockPageIndex),
        child: page,
      ),
    );

    // ✅ 완전 닫힘(canSwipe=false)에서는 가로 스와이프 전환 완전 비활성화
    if (!canSwipe) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) => _handleDockHorizontalSwipe(d, canSwipe: canSwipe),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final sysBottom = MediaQuery.of(context).padding.bottom;
    final bottomSafePadding = (controller.showKeypad ? 280.0 : 140.0) + viewInset + sysBottom;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        // ✅ 시스템/제스처 back도 동일하게 동작
        if (_sheetOpen) {
          await _animateSheet(open: false);
          return;
        }
        if (mounted) {
          Navigator.of(context).pop(false);
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
                              _dockEditing = null;
                              _monthlyDocExists = false;
                              _resolvedMonthlyDocId = null;

                              // ✅ 입력 초기화 → 안내 다이얼로그 중복 키 초기화
                              _lastPlateStatusDialogKey = null;
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
                    const sheetBg = Color(0xFFF6F8FF);

                    // ✅ 최신 스크롤 컨트롤러 보관
                    _sheetScrollController = scrollController;

                    final bool lockScroll = _isSheetFullyClosed();
                    final bool canSwipe = !lockScroll;

                    // ✅ bottom padding: 시스템 키보드(viewInset)만 대응
                    final sheetBottomPadding = 16.0 + viewInset;

                    return Container(
                      decoration: const BoxDecoration(
                        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black26,
                            blurRadius: 10,
                            offset: Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        clipBehavior: Clip.antiAlias,
                        child: ColoredBox(
                          color: sheetBg,
                          child: SafeArea(
                            top: true,
                            bottom: false,
                            child: NotificationListener<ScrollNotification>(
                              onNotification: (notification) {
                                if (!lockScroll) return false;

                                if (notification is ScrollUpdateNotification ||
                                    notification is OverscrollNotification ||
                                    notification is UserScrollNotification) {
                                  try {
                                    if (scrollController.hasClients && scrollController.offset != 0) {
                                      scrollController.jumpTo(0);
                                    }
                                  } catch (_) {
                                    // ignore
                                  }
                                  return true;
                                }
                                return false;
                              },
                              child: CustomScrollView(
                                controller: scrollController,
                                physics: const ClampingScrollPhysics(),
                                slivers: [
                                  SliverPersistentHeader(
                                    pinned: true,
                                    delegate: _SheetHeaderDelegate(
                                      backgroundColor: sheetBg,
                                      sheetOpen: _sheetOpen,
                                      plateText: controller.buildPlateNumber(),
                                      onToggle: _toggleSheet,
                                      currentPageIndex: _dockPageIndex,
                                      onSelectBill: () => _setDockPage(_dockPageBill),
                                      onSelectMemo: () => _setDockPage(_dockPageMemo),
                                    ),
                                  ),
                                  SliverPadding(
                                    padding: EdgeInsets.fromLTRB(16, 12, 16, sheetBottomPadding),
                                    sliver: SliverList(
                                      delegate: SliverChildListDelegate(
                                        [
                                          _buildDockPagedBody(canSwipe: canSwipe),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
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

/// ✅ Modern Dialog
/// ✅ AppCardPalette.serviceBase/serviceDark/serviceLight를 포인트 컬러로 사용
/// - 요구사항: countType/statusList는 "Dialog에서 표시하지 않음"
class _PlateStatusLoadedDialog extends StatelessWidget {
  final String safeArea;
  final String plateNumber;
  final String customStatusText;
  final VoidCallback onClose;
  final VoidCallback onGoMemo;

  const _PlateStatusLoadedDialog({
    required this.safeArea,
    required this.plateNumber,
    required this.customStatusText,
    required this.onClose,
    required this.onGoMemo,
  });

  Widget _infoCard({
    required BuildContext context,
    required IconData icon,
    required String label,
    required Widget value,
  }) {
    final palette = AppCardPalette.of(context);
    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;

    return Container(
      decoration: BoxDecoration(
        color: light.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: dark.withOpacity(0.22)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: light.withOpacity(0.22),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: dark.withOpacity(0.18)),
            ),
            alignment: Alignment.center,
            child: Icon(icon, size: 18, color: base),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w900,
                    color: Colors.black.withOpacity(0.72),
                    letterSpacing: 0.2,
                  ),
                ),
                const SizedBox(height: 6),
                value,
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = AppCardPalette.of(context);

    final base = palette.serviceBase;
    final dark = palette.serviceDark;
    final light = palette.serviceLight;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: light.withOpacity(0.22),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: dark.withOpacity(0.18)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.check_rounded, color: base, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '불러오기 완료',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        color: Colors.black.withOpacity(0.88),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: onClose,
                    icon: Icon(Icons.close_rounded, color: Colors.black.withOpacity(0.78)),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '저장된 메모를 화면에 반영했습니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: Colors.black.withOpacity(0.65),
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: light.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: dark.withOpacity(0.20)),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '지역: $safeArea',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.82),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        '번호판: $plateNumber',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                          color: Colors.black.withOpacity(0.70),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _infoCard(
                context: context,
                icon: Icons.note_alt_rounded,
                label: '메모',
                value: Text(
                  customStatusText,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.35,
                    color: Colors.black.withOpacity(0.84),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onClose,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: BorderSide(color: base.withOpacity(0.55), width: 1.2),
                        foregroundColor: base,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '닫기',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onGoMemo,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        backgroundColor: base,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text(
                        '상태 메모 보기',
                        style: TextStyle(fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// ✅ 카드 헤더(핸들/세그먼트 탭) 고정
class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  final Color backgroundColor;
  final bool sheetOpen;
  final String plateText;

  final int currentPageIndex;
  final VoidCallback onToggle;
  final VoidCallback onSelectBill;
  final VoidCallback onSelectMemo;

  _SheetHeaderDelegate({
    required this.backgroundColor,
    required this.sheetOpen,
    required this.plateText,
    required this.onToggle,
    required this.currentPageIndex,
    required this.onSelectBill,
    required this.onSelectMemo,
  });

  @override
  double get minExtent => 104;

  @override
  double get maxExtent => 104;

  Widget _segmentButton({
    required BuildContext context,
    required String label,
    required bool selected,
    required VoidCallback? onTap,
  }) {
    final selectedBg = Colors.white;
    final normalBg = Colors.transparent;

    final border = Border.all(
      color: selected ? Colors.black87 : Colors.black26,
      width: selected ? 1.4 : 1.0,
    );

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOutCubic,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? selectedBg : normalBg,
            borderRadius: BorderRadius.circular(10),
            border: border,
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w800 : FontWeight.w700,
              color: selected ? Colors.black : Colors.black54,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final VoidCallback? outerTap = sheetOpen ? null : onToggle;

    final bool billSelected = currentPageIndex == _InputPlateScreenState._dockPageBill;
    final bool memoSelected = currentPageIndex == _InputPlateScreenState._dockPageMemo;

    return Material(
      color: backgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: outerTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Column(
            children: [
              InkWell(
                onTap: sheetOpen ? onToggle : null,
                borderRadius: BorderRadius.circular(12),
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 3),
                  child: Center(child: _SheetHandle()),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _segmentButton(
                      context: context,
                      label: '정산 유형',
                      selected: billSelected,
                      onTap: sheetOpen ? onSelectBill : null,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _segmentButton(
                      context: context,
                      label: '상태 메모',
                      selected: memoSelected,
                      onTap: sheetOpen ? onSelectMemo : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      sheetOpen ? '핸들을 탭하면 닫힙니다' : '탭하면 카드가 열립니다',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.black.withOpacity(0.55),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      plateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: Colors.black54,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _SheetHeaderDelegate oldDelegate) {
    return oldDelegate.sheetOpen != sheetOpen ||
        oldDelegate.plateText != plateText ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.currentPageIndex != currentPageIndex;
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.black38,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// 하단 도크: 번호판 입력 3분할
class _PlateDock extends StatelessWidget {
  final InputPlateController controller;
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
