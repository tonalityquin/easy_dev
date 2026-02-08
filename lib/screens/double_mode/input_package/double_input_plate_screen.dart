import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../states/bill/bill_state.dart';
import '../../../states/area/area_state.dart';

import '../../../repositories/plate_repo_services/firestore_plate_repository.dart';

import 'double_input_plate_controller.dart';
import 'sections/double_input_bill_section.dart';
import 'sections/double_input_location_section.dart';
import 'sections/double_input_photo_section.dart';
import 'sections/double_input_plate_section.dart';
import 'sections/double_input_bottom_action_section.dart';
import 'sections/double_input_custom_status_section.dart';

import 'keypad/num_keypad.dart';
import 'keypad/kor_keypad.dart';
import 'widgets/double_input_bottom_navigation.dart';

import 'double_live_ocr_page.dart';

import '../../../utils/usage/usage_reporter.dart';

/// ─────────────────────────────────────────────────────────────
/// ✅ 로고(PNG) 가독성 보장 유틸
double _contrastRatio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final l1 = la >= lb ? la : lb;
  final l2 = la >= lb ? lb : la;
  return (l1 + 0.05) / (l2 + 0.05);
}

Color _resolveLogoTint({
  required Color background,
  required Color preferred,
  required Color fallback,
  double minContrast = 3.0,
}) {
  if (_contrastRatio(preferred, background) >= minContrast) return preferred;
  return fallback;
}

/// ✅ (경고 방지) required 파라미터만 사용하는 tint 로고 위젯
class _BrandTintedLogo extends StatelessWidget {
  const _BrandTintedLogo({
    required this.assetPath,
    required this.height,
    required this.preferredColor,
    required this.fallbackColor,
    this.minContrast = 3.0,
  });

  final String assetPath;
  final double height;

  final Color preferredColor;
  final Color fallbackColor;
  final double minContrast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bg = theme.scaffoldBackgroundColor;

    final tint = _resolveLogoTint(
      background: bg,
      preferred: preferredColor,
      fallback: fallbackColor,
      minContrast: minContrast,
    );

    return Image.asset(
      assetPath,
      fit: BoxFit.contain,
      height: height,
      color: tint,
      colorBlendMode: BlendMode.srcIn,
    );
  }
}

/// 도크에서 어떤 칸을 편집 중인지 구분
enum _DockField { front, mid, back }

class DoubleInputPlateScreen extends StatefulWidget {
  const DoubleInputPlateScreen({super.key});

  @override
  State<DoubleInputPlateScreen> createState() => _DoubleInputPlateScreenState();
}

class _DoubleInputPlateScreenState extends State<DoubleInputPlateScreen> {
  final controller = DoubleInputPlateController();

  // ✅ Firestore/Repository 캐싱
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirestorePlateRepository _plateRepo = FirestorePlateRepository();

  static const String screenTag = 'double plate input';

  // ✅ (신규) screen tag 텍스트 대신 사용할 이미지
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';

  // ✅ (권장 고정) 좌측 상단 태그 이미지 높이
  static const double _kScreenTagHeight = 54.0;

  static const String _prefsHasMonthlyKey = 'has_monthly_parking';

  static const String _plateStatusRoot = 'plate_status';
  static const String _monthsSub = 'months';
  static const String _platesSub = 'plates';
  static const String _monthlyPlateStatusRoot = 'monthly_plate_status';

  // ✅ (A안) collectionGroup 조회를 위한 문서 필드 키
  // - plate_status/{area}/months/{yyyyMM}/plates/{docId} 문서 내부에 아래 필드가 "저장"되어야
  //   A(primary: orderBy+limit)가 제대로 동작합니다.
  static const String _fPlateDocId = 'plateDocId'; // 예: "222-노-2222_britishArea"
  static const String _fMonthKey = 'monthKey'; // 예: "202601" (yyyyMM)

  static const bool _usageUseSourceOnlyKey = true;
  static const int _usageSourceShardCount = 10;

  static const String _usageSrcDoublePlateStatusLookupOnComplete =
      'Double.plate_status.lookup.on_complete';

  static const String _usageSrcMonthlyLookup =
      'DoubleInputPlateScreen._fetchMonthlyPlateStatus/monthly_plate_status.lookup';
  static const String _usageSrcMonthlyUpdate =
      'DoubleInputPlateScreen._applyMonthlyMemoAndStatusOnly/monthly_plate_status.doc.update';

  bool _hasMonthlyParking = false;
  bool _hasMonthlyLoaded = false;

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  bool _openedScannerOnce = false;

  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false;

  ScrollController? _sheetScrollController;

  _DockField? _dockEditing;

  static const double _sheetClosed = 0.16;
  static const double _sheetOpened = 1.00;

  bool _monthlyDocExists = false;
  bool _monthlyApplying = false;
  String? _resolvedMonthlyDocId;

  static const int _dockPageBill = 0;
  static const int _dockPageMemo = 1;

  int _dockPageIndex = _dockPageBill;
  bool _dockSlideFromRight = true;

  String? _lastPlateStatusDialogKey;
  bool _plateStatusDialogShowing = false;

  // ─────────────────────────────
  // ✅ 문서명 정책 유틸
  // ─────────────────────────────

  String _safeArea(String area) {
    final a = area.trim();
    return a.isEmpty ? 'unknown' : a;
  }

  String _monthKey(DateTime dt) =>
      '${dt.year}${dt.month.toString().padLeft(2, '0')}';

  String _canonicalPlateNumber(String plateNumber) {
    final t = plateNumber.trim().replaceAll(' ', '');
    final raw = t.replaceAll('-', '');
    final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(raw);
    if (m == null) return t;
    return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
  }

  String _plateDocId(String plateNumber, String area) {
    final a = _safeArea(area);
    final p = _canonicalPlateNumber(plateNumber);
    return '${p}_$a';
  }

  Future<void> _reportUsage({
    required String area,
    required String action,
    required String source,
    int n = 1,
  }) async {
    try {
      await UsageReporter.instance.report(
        area: area,
        action: action,
        n: n,
        source: source,
        useSourceOnlyKey: _usageUseSourceOnlyKey,
        sourceShardCount: _usageSourceShardCount,
      );
    } catch (e) {
      debugPrint('[UsageReporter] report failed ($source): $e');
    }
  }

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
      } catch (_) {}
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

    if (open) {
      _resetDockToBillPage();
    }

    if (!open) {
      try {
        final sc = _sheetScrollController;
        if (sc != null && sc.hasClients) {
          sc.jumpTo(0);
        }
      } catch (_) {}
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

  Future<void> _showPlateStatusLoadedDialog({
    required String plateNumber,
    required String area,
    String? customStatus,
  }) async {
    if (!mounted) return;

    final cs = Theme.of(context).colorScheme;

    final safeArea = _safeArea(area);
    final customStatusText = (customStatus ?? '').trim().isEmpty ? '-' : customStatus!.trim();

    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'plate_status_loaded',
      barrierColor: cs.scrim.withOpacity(0.55),
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

  // ✅ Navigator pop 재진입 방지
  bool _exitInProgress = false;
  bool _exitPostFrameScheduled = false;

  void _requestExit({bool defer = false}) {
    if (_exitInProgress) return;

    void doPop() {
      if (!mounted) return;
      if (_exitInProgress) return;

      _exitInProgress = true;
      try {
        Navigator.of(context).pop(false);
      } catch (e) {
        _exitInProgress = false;
        debugPrint('[DoubleInputPlateScreen] pop failed: $e');
      }
    }

    if (!defer) {
      doPop();
      return;
    }

    if (_exitPostFrameScheduled) return;
    _exitPostFrameScheduled = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _exitPostFrameScheduled = false;
      doPop();
    });
  }

  @override
  void initState() {
    super.initState();

    _loadHasMonthlyParkingFlag();

    if (controller.selectedBillType == '고정' || controller.selectedBillType.trim().isEmpty) {
      controller.selectedBillType = '변동';
    }

    _sheetController.addListener(() {
      try {
        final s = _sheetController.size;
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);

        if (openNow != _sheetOpen && mounted) {
          setState(() {
            _sheetOpen = openNow;

            if (openNow) {
              _dockSlideFromRight = false;
              _dockPageIndex = _dockPageBill;
            }
          });

          if (openNow) {
            _jumpSheetScrollToTop();
          }
        }

        if (_isSheetFullyClosed()) {
          final sc = _sheetScrollController;
          if (sc != null && sc.hasClients && sc.offset != 0) {
            sc.jumpTo(0);
          }
        }
      } catch (_) {}
    });

    controller.controllerBackDigit.addListener(() async {
      final text = controller.controllerBackDigit.text;
      if (text.length == 4 && controller.isInputValid()) {
        final plateNumber = controller.buildPlateNumber();
        final area = context.read<AreaState>().currentArea;

        final data = await _fetchPlateStatus(plateNumber, area);
        if (!mounted || data == null) return;

        final fetchedStatus = (data['customStatus'] as String?)?.trim();
        final fetchedList = (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
        final String? fetchedCountType = (data['countType'] as String?)?.trim();

        setState(() {
          controller.fetchedCustomStatus = fetchedStatus;
          controller.customStatusController.text = fetchedStatus ?? '';
          selectedStatusNames = fetchedList;
          statusSectionKey = UniqueKey();

          if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
            controller.countTypeController.text = fetchedCountType;
            controller.selectedBillType = '정기';
            controller.selectedBill = fetchedCountType;

            _monthlyDocExists = false;
            _resolvedMonthlyDocId = null;
          } else {
            _monthlyDocExists = false;
            _resolvedMonthlyDocId = null;
          }
        });

        final dialogKey = _plateDocId(plateNumber, area);
        if (_plateStatusDialogShowing) return;
        if (_lastPlateStatusDialogKey == dialogKey) return;

        _plateStatusDialogShowing = true;
        _lastPlateStatusDialogKey = dialogKey;

        try {
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

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final billState = context.read<BillState>();
      await billState.loadFromBillCache();
      if (!mounted) return;
      setState(() {
        controller.isLocationSelected = controller.locationController.text.isNotEmpty;
      });
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (_openedScannerOnce) return;
      _openedScannerOnce = true;
      await _openLiveScanner();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadHasMonthlyParkingFlag();
  }

  @override
  void dispose() {
    _sheetController.dispose();
    controller.dispose();
    super.dispose();
  }

  /// (A안 반영) plate_status 조회:
  /// 1) 현재월/전월 2개월 direct get
  /// 2) 실패 시 collectionGroup('plates') + where(plateDocId==docId) 폴백
  ///    - primary: orderBy(monthKey desc) + limit(1)
  ///    - secondary: 인덱스/필드 이슈 시 where만 + limit(cap) 후 클라이언트에서 최신 선택
  ///
  /// 비용/형태 로그:
  /// - directGets: 문서 get 시도 횟수
  /// - primaryDocs/secondaryDocs: 각 쿼리 반환 문서 수
  /// - estReads: doc.get + (각 쿼리당 최소 1 read 특성 반영한 추정치)
  Future<Map<String, dynamic>?> _fetchPlateStatus(String plateNumber, String area) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    int directGetCount = 0;

    bool triedPrimary = false;
    bool triedSecondary = false;

    int primaryDocs = 0;
    int secondaryDocs = 0;

    final now = DateTime.now();
    final monthsToTry = <DateTime>[
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month - 1, 1),
    ];

    debugPrint(
      '[DoubleInputPlateScreen][PlateStatusLookup] start docId=$docId area=$safeArea monthsTry=${monthsToTry.map(_monthKey).join(',')}',
    );

    try {
      // (1) direct get: 현재월/전월
      for (final m in monthsToTry) {
        final mk = _monthKey(m);
        directGetCount++;

        final doc = await _firestore
            .collection(_plateStatusRoot)
            .doc(safeArea)
            .collection(_monthsSub)
            .doc(mk)
            .collection(_platesSub)
            .doc(docId)
            .get();

        if (doc.exists) {
          debugPrint(
            '[DoubleInputPlateScreen][PlateStatusLookup] hit direct month=$mk (directGets=$directGetCount)',
          );
          return doc.data();
        }
      }

      // (2) A primary: where(plateDocId == docId) + orderBy(monthKey desc) + limit(1)
      try {
        triedPrimary = true;

        final qs = await _firestore
            .collectionGroup(_platesSub)
            .where(_fPlateDocId, isEqualTo: docId)
            .orderBy(_fMonthKey, descending: true)
            .limit(1)
            .get();

        primaryDocs = qs.docs.length;

        if (qs.docs.isNotEmpty) {
          final d = qs.docs.first;
          final data = d.data();
          final mk = (data[_fMonthKey] as String?)?.trim();

          debugPrint(
            '[DoubleInputPlateScreen][PlateStatusLookup] hit A(primary) monthKey=$mk path=${d.reference.path} (primaryDocs=$primaryDocs)',
          );
          return data;
        }

        debugPrint(
          '[DoubleInputPlateScreen][PlateStatusLookup] miss A(primary) (primaryDocs=$primaryDocs)',
        );
      } on FirebaseException catch (e) {
        debugPrint(
          '[DoubleInputPlateScreen][PlateStatusLookup] A(primary) failed: ${e.code} ${e.message}',
        );
      }

      // (3) A secondary (다운그레이드): where만 + limit(cap) 후 최신 선택
      // - monthKey 필드 우선
      // - 없으면 path에서 months/{yyyyMM} 파싱(레거시 호환 최후 수단)
      try {
        triedSecondary = true;

        const int cap = 12;

        final qs = await _firestore
            .collectionGroup(_platesSub)
            .where(_fPlateDocId, isEqualTo: docId)
            .limit(cap)
            .get();

        secondaryDocs = qs.docs.length;

        if (qs.docs.isEmpty) {
          debugPrint(
            '[DoubleInputPlateScreen][PlateStatusLookup] miss A(secondary) (secondaryDocs=$secondaryDocs cap=$cap)',
          );
          return null;
        }

        QueryDocumentSnapshot<Map<String, dynamic>>? best;
        int bestMonth = -1;

        for (final d in qs.docs) {
          final data = d.data();

          int mkInt = -1;
          final mk = (data[_fMonthKey] as String?)?.trim();
          if (mk != null && mk.isNotEmpty) {
            mkInt = int.tryParse(mk) ?? -1;
          } else {
            // 레거시: path 파싱
            final path = d.reference.path;
            final parts = path.split('/');
            final monthsIndex = parts.indexOf(_monthsSub);
            if (monthsIndex >= 0 && monthsIndex + 1 < parts.length) {
              final fromPath = parts[monthsIndex + 1];
              mkInt = int.tryParse(fromPath) ?? -1;
            }
          }

          if (mkInt > bestMonth) {
            bestMonth = mkInt;
            best = d;
          }
        }

        if (best != null) {
          final data = best.data();
          final mk = (data[_fMonthKey] as String?)?.trim();
          debugPrint(
            '[DoubleInputPlateScreen][PlateStatusLookup] hit A(secondary) bestMonth=$bestMonth monthKeyField=$mk path=${best.reference.path} (secondaryDocs=$secondaryDocs cap=$cap)',
          );
          return data;
        }

        debugPrint(
          '[DoubleInputPlateScreen][PlateStatusLookup] A(secondary) had docs but could not select best (secondaryDocs=$secondaryDocs). Return first.',
        );
        return qs.docs.first.data();
      } on FirebaseException catch (e) {
        debugPrint(
          '[DoubleInputPlateScreen][PlateStatusLookup] A(secondary) failed: ${e.code} ${e.message}',
        );
        return null;
      }
    } on FirebaseException catch (e) {
      debugPrint('[_fetchPlateStatus] FirebaseException: ${e.code} ${e.message}');
      return null;
    } catch (e) {
      debugPrint('[_fetchPlateStatus] error: $e');
      return null;
    } finally {
      // 비용(형태) 추정:
      // - direct doc.get: directGetCount 만큼 read 발생한다고 가정
      // - query: 각 쿼리마다 docsReturned만큼 read + (0건이어도 최소 1 read) 성격 반영
      final int estPrimaryReads = triedPrimary ? (primaryDocs == 0 ? 1 : primaryDocs) : 0;
      final int estSecondaryReads = triedSecondary ? (secondaryDocs == 0 ? 1 : secondaryDocs) : 0;
      final int estTotalReads = directGetCount + estPrimaryReads + estSecondaryReads;

      debugPrint(
        '[DoubleInputPlateScreen][PlateStatusLookup] done'
            ' directGets=$directGetCount'
            ' triedA(primary)=$triedPrimary primaryDocs=$primaryDocs estPrimaryReads~=$estPrimaryReads'
            ' triedA(secondary)=$triedSecondary secondaryDocs=$secondaryDocs estSecondaryReads~=$estSecondaryReads'
            ' estReads~=$estTotalReads (doc.get + query(min 1 read each))',
      );

      await _reportUsage(
        area: safeArea,
        action: 'read',
        n: 1,
        source: _usageSrcDoublePlateStatusLookupOnComplete,
      );
    }
  }

  Future<Map<String, dynamic>?> _fetchMonthlyPlateStatus(String plateNumber, String area) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    try {
      final doc = await _firestore.collection(_monthlyPlateStatusRoot).doc(docId).get();
      if (doc.exists) {
        _resolvedMonthlyDocId = docId;
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
      await _reportUsage(
        area: safeArea,
        action: 'read',
        n: 1,
        source: _usageSrcMonthlyLookup,
      );
    }
  }

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
    final fetchedList = (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
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

  Future<void> _applyMonthlyMemoAndStatusOnly() async {
    if (_monthlyApplying) return;

    if (!controller.isInputValid()) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('번호판 입력을 완료한 후 반영할 수 있습니다.')),
      );
      return;
    }

    if (!_monthlyDocExists || (_resolvedMonthlyDocId == null || _resolvedMonthlyDocId!.trim().isEmpty)) {
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

      await _reportUsage(
        area: _safeArea(area),
        action: 'write',
        n: 1,
        source: _usageSrcMonthlyUpdate,
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

  Widget _buildMonthlyApplyButton() {
    final cs = Theme.of(context).colorScheme;

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
              backgroundColor: enabled ? cs.primary : cs.surfaceContainerLow,
              foregroundColor: enabled ? cs.onPrimary : cs.onSurfaceVariant,
              elevation: 0,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              side: BorderSide(
                color: enabled ? cs.primary.withOpacity(0.25) : cs.outlineVariant.withOpacity(0.85),
              ),
            ),
            child: _monthlyApplying
                ? SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(enabled ? cs.onPrimary : cs.onSurfaceVariant),
              ),
            )
                : const Text(
              '반영',
              style: TextStyle(fontWeight: FontWeight.w900),
            ),
          ),
        ),
        if (!_monthlyDocExists) ...[
          const SizedBox(height: 8),
          Text(
            '정기(월정기) 문서를 불러온 경우에만 반영할 수 있습니다.',
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  // ─────────────────────────────
  // OCR 폴백 파서(원문 유지)
  // ─────────────────────────────
  static const List<String> _allowedKoreanMids = [
    '가','나','다','라','마','거','너','더','러','머','버','서','어','저','고','노','도','로','모','보','소','오','조','구','누','두','루','무','부','수','우','주','하','허','호','배'
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

      _monthlyDocExists = false;
      _resolvedMonthlyDocId = null;

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
      MaterialPageRoute(builder: (_) => const DoubleLiveOcrPage()),
    );
    if (plate == null) return;
    _applyPlateWithFallback(plate);
  }

  void _beginDockEdit(_DockField field) {
    setState(() {
      _dockEditing = field;

      _monthlyDocExists = false;
      _resolvedMonthlyDocId = null;

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
    final cs = Theme.of(context).colorScheme;

    final actionButton = DoubleInputBottomActionSection(
      controller: controller,
      mountedContext: mounted,
      onStateRefresh: () => setState(() {}),
    );

    final Widget ocrButton = Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: _openLiveScanner,
          icon: const Icon(Icons.camera_alt_outlined),
          label: const Text('실시간 OCR 다시 스캔'),
          style: OutlinedButton.styleFrom(
            backgroundColor: cs.surface,
            foregroundColor: cs.onSurface,
            side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
            minimumSize: const Size.fromHeight(55),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ).copyWith(
            overlayColor: MaterialStateProperty.resolveWith<Color?>(
                  (states) => states.contains(MaterialState.pressed)
                  ? cs.outlineVariant.withOpacity(0.12)
                  : null,
            ),
          ),
        ),
      ),
    );

    if (controller.showKeypad) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DoubleInputBottomNavigation(
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
          DoubleInputBottomNavigation(
            showKeypad: false,
            keypad: const SizedBox.shrink(),
            actionButton: actionButton,
          ),
          ocrButton,
        ],
      );
    }
  }

  /// ✅ (수정) 기존 좌측상단 screenTag 텍스트 → pelican_text.png 태그 이미지로 교체
  /// - 기존과 동일한 위치(SafeArea top-left, left 12 / top 4)
  /// - IgnorePointer 유지(탭 이벤트 방해 없음)
  /// - Semantics label 유지(접근성/로그 태그)
  Widget _buildScreenTag(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // ✅ 기존 텍스트 태그 톤(onSurfaceVariant 0.80)으로 tint 우선 시도
    // 대비 부족 시 onBackground로 폴백
    final tagPreferredTint = cs.onSurfaceVariant.withOpacity(0.80);

    return SafeArea(
      child: IgnorePointer(
        child: Align(
          alignment: Alignment.topLeft,
          child: Padding(
            padding: const EdgeInsets.only(left: 12, top: 4),
            child: Semantics(
              label: 'screen_tag: $screenTag',
              child: ExcludeSemantics(
                child: _BrandTintedLogo(
                  assetPath: _kScreenTagAsset,
                  height: _kScreenTagHeight,
                  preferredColor: tagPreferredTint,
                  fallbackColor: cs.onBackground,
                  minContrast: 3.0,
                ),
              ),
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
    _requestExit(defer: false);
  }

  Widget _buildDockPagedBody({required bool canSwipe}) {
    final cs = Theme.of(context).colorScheme;

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
                color: cs.tertiaryContainer.withOpacity(0.55),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
              ),
              child: Text(
                '정기 주차가 제한된 근무지입니다.',
                style: TextStyle(fontSize: 12, height: 1.25, color: cs.onSurface),
              ),
            ),
          ),
        DoubleInputBillSection(
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
        DoubleInputCustomStatusSection(
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

    if (!canSwipe) return content;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onHorizontalDragEnd: (d) => _handleDockHorizontalSwipe(d, canSwipe: canSwipe),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final sysBottom = MediaQuery.of(context).padding.bottom;
    final bottomSafePadding = (controller.showKeypad ? 280.0 : 140.0) + viewInset + sysBottom;

    return PopScope(
      canPop: false,
      onPopInvoked: (didPop) async {
        if (didPop) return;

        if (_sheetOpen) {
          await _animateSheet(open: false);
          return;
        }

        if (mounted) {
          _requestExit(defer: true);
        }
      },
      child: Scaffold(
        // ✅ [브랜드테마/독립프리셋 핵심] 배경을 테마 background로 명시
        // - 독립 프리셋(KB)은 background가 프리셋 토큰으로 설정됨
        backgroundColor: cs.background,

        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(bottom: BorderSide(color: cs.outlineVariant.withOpacity(0.85), width: 1)),
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
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 1,
                          height: 16,
                          color: cs.outlineVariant.withOpacity(0.85),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          controller.isThreeDigit ? '현재 앞자리: 세자리' : '현재 앞자리: 두자리',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
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
                        DoubleInputPlateSection(
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
                        DoubleInputLocationSection(locationController: controller.locationController),
                        const SizedBox(height: 16),
                        DoubleInputPhotoSection(
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
                    _sheetScrollController = scrollController;

                    final bool lockScroll = _isSheetFullyClosed();
                    final bool canSwipe = !lockScroll;

                    final sheetBottomPadding = 16.0 + viewInset;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                        color: cs.surface,
                        boxShadow: [
                          BoxShadow(
                            color: cs.shadow.withOpacity(0.12),
                            blurRadius: 10,
                            offset: const Offset(0, -4),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                        clipBehavior: Clip.antiAlias,
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
                                } catch (_) {}
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

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 24),
      backgroundColor: cs.surface,
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
                      color: cs.primary.withOpacity(0.10),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: cs.primary.withOpacity(0.18)),
                    ),
                    alignment: Alignment.center,
                    child: Icon(Icons.check_rounded, color: cs.primary, size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '불러오기 완료',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.2,
                        color: cs.onSurface,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '닫기',
                    onPressed: onClose,
                    icon: Icon(Icons.close_rounded, color: cs.onSurface),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '저장된 메모를 화면에 반영했습니다.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    height: 1.35,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                          fontWeight: FontWeight.w800,
                          color: cs.onSurface,
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
                          fontWeight: FontWeight.w800,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: cs.primary.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: cs.primary.withOpacity(0.18)),
                      ),
                      alignment: Alignment.center,
                      child: Icon(Icons.note_alt_rounded, size: 18, color: cs.primary),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '메모',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: cs.onSurfaceVariant,
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            customStatusText,
                            style: TextStyle(
                              fontSize: 13,
                              height: 1.35,
                              color: cs.onSurface,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(color: cs.outlineVariant.withOpacity(0.85)),
                        foregroundColor: cs.onSurface,
                      ),
                      child: const Text('닫기', style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onGoMemo,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                      child: const Text('상태 메모 보기', style: TextStyle(fontWeight: FontWeight.w900)),
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

class _SheetHeaderDelegate extends SliverPersistentHeaderDelegate {
  final bool sheetOpen;
  final String plateText;

  final int currentPageIndex;
  final VoidCallback onToggle;
  final VoidCallback onSelectBill;
  final VoidCallback onSelectMemo;

  _SheetHeaderDelegate({
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
    final cs = Theme.of(context).colorScheme;

    // ✅ selected 배경도 테마 기반으로(독립 프리셋 포함)
    final bg = selected ? cs.surfaceContainerLow : Colors.transparent;
    final border = selected ? cs.primary.withOpacity(0.55) : cs.outlineVariant.withOpacity(0.85);
    final fg = selected ? cs.onSurface : cs.onSurfaceVariant;

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
            color: bg,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: border, width: selected ? 1.4 : 1.0),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
              color: fg,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;

    final VoidCallback? outerTap = sheetOpen ? null : onToggle;

    final bool billSelected = currentPageIndex == _DoubleInputPlateScreenState._dockPageBill;
    final bool memoSelected = currentPageIndex == _DoubleInputPlateScreenState._dockPageMemo;

    return Material(
      color: cs.surface,
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
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Center(
                    child: _SheetHandle(color: cs.outlineVariant.withOpacity(0.9)),
                  ),
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
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      plateText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: cs.onSurfaceVariant,
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
        oldDelegate.currentPageIndex != currentPageIndex;
  }
}

class _SheetHandle extends StatelessWidget {
  final Color color;

  const _SheetHandle({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 4,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

class _PlateDock extends StatelessWidget {
  final DoubleInputPlateController controller;
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
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      filled: true,
      fillColor: active ? cs.primary.withOpacity(0.08) : cs.surface,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: active ? cs.primary.withOpacity(0.75) : cs.outlineVariant.withOpacity(0.85),
          width: active ? 2 : 1,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: cs.primary,
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
    final cs = Theme.of(context).colorScheme;

    final chipColor = isActive ? cs.primary : cs.onSurfaceVariant;

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
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: cs.onSurface,
              ),
              decoration: _dec(context, isActive),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: chipColor.withOpacity(isActive ? 0.14 : 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: chipColor.withOpacity(0.22)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.edit_outlined, size: 12, color: chipColor),
                    const SizedBox(width: 2),
                    Text(
                      isActive ? '편집중' : '편집',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
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
    final cs = Theme.of(context).colorScheme;

    final isFrontActive = controller.activeController == controller.controllerFrontDigit;
    final isMidActive = controller.activeController == controller.controllerMidDigit;
    final isBackActive = controller.activeController == controller.controllerBackDigit;

    final labelStyle = TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    );

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
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
              Icon(Icons.touch_app, size: 14, color: cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Flexible(
                child: Text(
                  '번호판 각 칸을 탭하면 해당 자리를 수정할 수 있습니다.',
                  style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
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
