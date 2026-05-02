import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import '../../../../app/usage/usage_reporter.dart';
import '../../../../app/utils/status_dialog.dart';
import '../../../../features/dev/application/area_state.dart';
import '../../../../features/monthly/page/sheets/widgets/keypad/kor_keypad.dart';
import '../../../../features/monthly/page/sheets/widgets/keypad/num_keypad.dart';
import '../../../../features/payment/applications/bill_state.dart';
import '../../../plate/domain/repositories/plate_repository.dart';
import '../../../plate/domain/services/plate_status_record.dart';
import '../controllers/input_plate_controller.dart';
import '../data/vehicle_parking_preference_repository.dart';
import 'live_ocr_page.dart';
import 'sheets/input_bottom_navigation.dart';
import 'sheets/input_region_bottom_sheet.dart';
import 'widgets/input_bill_section.dart';
import 'widgets/input_bottom_action_section.dart';
import 'widgets/input_custom_status_section.dart';
import 'widgets/input_location_section.dart';
import 'widgets/input_photo_section.dart';
import 'widgets/input_plate_section.dart';

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

enum _DockField { front, mid, back }

enum _MonthlyFetchFailureType { notFound, readError }

class _MonthlyFetchResult {
  final PlateStatusRecord? data;
  final _MonthlyFetchFailureType? failure;

  const _MonthlyFetchResult.success(this.data) : failure = null;

  const _MonthlyFetchResult.failure(this.failure) : data = null;

  bool get isSuccess => data != null;
}

class InputPlateScreen extends StatefulWidget {
  final bool isMinorMode;

  const InputPlateScreen({
    super.key,
    this.isMinorMode = false,
  });

  @override
  State<InputPlateScreen> createState() => _InputPlateScreenState();
}

class _InputPlateScreenState extends State<InputPlateScreen> {
  late final InputPlateController controller;

  PlateRepository get _plateRepo => context.read<PlateRepository>();

  static const String screenTag = 'plate input';
  static const String _kScreenTagAsset = 'assets/images/pelican_text.png';
  static const double _kScreenTagHeight = 54.0;
  static const String _prefsHasMonthlyKey = 'has_monthly_parking';
  static const bool _usageUseSourceOnlyKey = true;
  static const int _usageSourceShardCount = 10;
  static const String _usageSrcPlateStatusLookupOnComplete =
      'plate_status.lookup.on_complete';
  static const String _usageSrcMonthlyLookup =
      'InputPlateScreen._fetchMonthlyPlateStatus/monthly_plate_status.lookup';
  static const String _usageSrcMonthlyUpdate =
      'InputPlateScreen._applyMonthlyMemoAndStatusOnly/monthly_plate_status.doc.update';

  bool _hasMonthlyParking = false;
  bool _hasMonthlyLoaded = false;

  List<String> selectedStatusNames = [];
  Key statusSectionKey = UniqueKey();

  bool _openedScannerOnce = false;

  final DraggableScrollableController _sheetController =
      DraggableScrollableController();
  bool _sheetOpen = false;

  ScrollController? _sheetScrollController;

  _DockField? _dockEditing;

  String _midBeforeEdit = '';
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

  LiveOcrSessionResult? _lastOcrSessionResult;

  final VehicleParkingPreferenceRepository _vehiclePrefRepo =
      VehicleParkingPreferenceRepository.instance;
  List<String> _manufacturerOptions = const [];
  List<String> _modelOptions = const [];
  String? _selectedManufacturerName;
  String? _selectedModelName;

  String _safeArea(String area) {
    final a = area.trim();
    return a.isEmpty ? 'unknown' : a;
  }

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

  void _handleDockHorizontalSwipe(DragEndDetails details,
      {required bool canSwipe}) {
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
      await _animateSheet(open: true);
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
    final customStatusText =
        (customStatus ?? '').trim().isEmpty ? '-' : customStatus!.trim();

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
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
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
        debugPrint('[InputPlateScreen] pop failed: $e');
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

    controller = InputPlateController(isMinorMode: widget.isMinorMode);

    _loadHasMonthlyParkingFlag();
    Future.microtask(_loadVehicleManufacturers);

    if (controller.selectedBillType == '고정' ||
        controller.selectedBillType.trim().isEmpty) {
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

        final fetchedStatus = data.customStatus;
        final fetchedList = data.statusList;
        final String? fetchedCountType = data.countType;

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
        controller.isLocationSelected =
            controller.locationController.text.isNotEmpty;
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

  Future<PlateStatusRecord?> _fetchPlateStatus(
      String plateNumber, String area) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    debugPrint(
      '[InputPlateScreen][PlateStatusLookup] start docId=$docId area=$safeArea',
    );

    try {
      return await _plateRepo.fetchLatestPlateStatus(
        plateNumber: plateNumber,
        area: safeArea,
      );
    } on PlateStatusReadException catch (e) {
      debugPrint('[_fetchPlateStatus] repository error: $e');
      return null;
    } catch (e) {
      debugPrint('[_fetchPlateStatus] error: $e');
      return null;
    } finally {
      await _reportUsage(
        area: safeArea,
        action: 'read',
        n: 1,
        source: _usageSrcPlateStatusLookupOnComplete,
      );
    }
  }

  Future<_MonthlyFetchResult> _fetchMonthlyPlateStatus(
      String plateNumber, String area) async {
    final safeArea = _safeArea(area);
    final docId = _plateDocId(plateNumber, safeArea);

    try {
      final data = await _plateRepo.fetchMonthlyPlateStatus(
        plateNumber: plateNumber,
        area: safeArea,
      );
      if (data != null) {
        _resolvedMonthlyDocId = docId;
        return _MonthlyFetchResult.success(data);
      }
      return const _MonthlyFetchResult.failure(
        _MonthlyFetchFailureType.notFound,
      );
    } on MonthlyPlateStatusReadException catch (e) {
      debugPrint('[_fetchMonthlyPlateStatus] repository error: $e');
      return const _MonthlyFetchResult.failure(
        _MonthlyFetchFailureType.readError,
      );
    } catch (e) {
      debugPrint('[_fetchMonthlyPlateStatus] error: $e');
      return const _MonthlyFetchResult.failure(
        _MonthlyFetchFailureType.readError,
      );
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
      await StatusDialog.showFailure(
        context,
        title: StatusDialog.invalidPlateInput,
      );
      return;
    }

    final plateNumber = controller.buildPlateNumber();
    final area = context.read<AreaState>().currentArea;

    final result = await _fetchMonthlyPlateStatus(plateNumber, area);
    if (!mounted) return;

    if (!result.isSuccess) {
      setState(() {
        _monthlyDocExists = false;
        _resolvedMonthlyDocId = null;
      });

      if (result.failure == _MonthlyFetchFailureType.notFound) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.monthlyDocNotFound,
        );
      } else if (result.failure == _MonthlyFetchFailureType.readError) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.monthlyDocReadFailed,
        );
      }
      return;
    }

    final data = result.data!;
    final fetchedStatus = data.customStatus;
    final fetchedList = data.statusList;
    final fetchedCountType = data.countType;

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
  }

  Future<void> _applyMonthlyMemoAndStatusOnly() async {
    if (_monthlyApplying) return;

    if (!controller.isInputValid()) {
      await StatusDialog.showFailure(
        context,
        title: StatusDialog.invalidPlateInput,
      );
      return;
    }

    if (!_monthlyDocExists ||
        (_resolvedMonthlyDocId == null ||
            _resolvedMonthlyDocId!.trim().isEmpty)) {
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
    } on MonthlyPlateStatusWriteException catch (e) {
      debugPrint('[_applyMonthlyMemoAndStatusOnly] repository error: $e');
      if (mounted) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.monthlyApplyFailed,
        );
      }
    } catch (e) {
      debugPrint('[_applyMonthlyMemoAndStatusOnly] error: $e');
      if (mounted) {
        await StatusDialog.showFailure(
          context,
          title: StatusDialog.monthlyApplyFailed,
        );
      }
    } finally {
      if (mounted) setState(() => _monthlyApplying = false);
    }
  }

  Widget _buildMonthlyApplyButton() {
    final cs = Theme.of(context).colorScheme;

    if (controller.selectedBillType != '정기') {
      return const SizedBox.shrink();
    }

    final enabled = !_monthlyApplying &&
        _monthlyDocExists &&
        (_resolvedMonthlyDocId != null);

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
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              side: BorderSide(
                color: enabled
                    ? cs.primary.withOpacity(0.25)
                    : cs.outlineVariant.withOpacity(0.85),
              ),
            ),
            child: _monthlyApplying
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                          enabled ? cs.onPrimary : cs.onSurfaceVariant),
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

  static const List<String> _allowedKoreanMids = [
    '가',
    '나',
    '다',
    '라',
    '마',
    '거',
    '너',
    '더',
    '러',
    '머',
    '버',
    '서',
    '어',
    '저',
    '고',
    '노',
    '도',
    '로',
    '모',
    '보',
    '소',
    '오',
    '조',
    '구',
    '누',
    '두',
    '루',
    '무',
    '부',
    '수',
    '우',
    '주',
    '아',
    '바',
    '사',
    '자',
    '하',
    '허',
    '호',
    '배'
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

  void _applyPlateWithFallback(String plate, {String? sessionId}) {
    final raw = _normalize(plate);

    final s = _rxStrict.firstMatch(raw);
    if (s != null) {
      final front = s.group(1)!;
      var mid = s.group(2)!;
      final back = s.group(3)!;

      mid = _midNormalize[mid] ?? mid;
      _applyToFields(front: front, mid: mid, back: back, sessionId: sessionId);
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

      _applyToFields(front: front, mid: mid, back: back, sessionId: sessionId);
      return;
    }

    if (_rxOnly7.hasMatch(raw)) {
      final front = raw.substring(0, 3);
      final back = raw.substring(3, 7);
      _applyToFields(
        front: front,
        mid: '',
        back: back,
        promptMid: true,
        sessionId: sessionId,
      );
      return;
    }

    if (_rxOnly6.hasMatch(raw)) {
      final front = raw.substring(0, 2);
      final back = raw.substring(2, 6);
      _applyToFields(
        front: front,
        mid: '',
        back: back,
        promptMid: true,
        sessionId: sessionId,
      );
      return;
    }
  }

  void _applyToFields({
    required String front,
    required String mid,
    required String back,
    bool promptMid = false,
    String? sessionId,
  }) {
    controller.suppressOcrEditCount(true);
    setState(() {
      controller.isThreeDigit = front.length == 3;
      controller.controllerFrontDigit.text = front;
      controller.controllerMidDigit.text = mid;
      controller.controllerBackDigit.text = back;

      _midBeforeEdit = '';
      _monthlyDocExists = false;
      _resolvedMonthlyDocId = null;
      _lastPlateStatusDialogKey = null;

      if (promptMid || mid.isEmpty) {
        controller.showKeypad = true;
        controller.setActiveController(controller.controllerMidDigit);
      } else {
        controller.showKeypad = false;
      }
    });
    controller.suppressOcrEditCount(false);
    if (sessionId != null && sessionId.isNotEmpty) {
      controller.bindOcrSession(sessionId);
    } else {
      controller.clearOcrSession();
    }
  }

  String _ocrExitTypeLabel(LiveOcrExitType type) {
    switch (type) {
      case LiveOcrExitType.autoDirect:
        return '자동 확정(strict)';
      case LiveOcrExitType.autoLoose:
        return '자동 확정(loose)';
      case LiveOcrExitType.autoForceInsert:
        return '강제 삽입';
      case LiveOcrExitType.candidateChipSelected:
        return '후보 칩 선택';
      case LiveOcrExitType.userAborted:
        return '사용자 중도 종료';
      case LiveOcrExitType.permissionDenied:
        return '권한 거부';
      case LiveOcrExitType.cameraInitFailed:
        return '카메라 초기화 실패';
    }
  }

  String _buildOcrClipboardText(LiveOcrSessionResult result) {
    final summary = <String>[
      'sessionId: ${result.sessionId}',
      '종료유형: ${_ocrExitTypeLabel(result.exitType)}',
      '최종번호판: ${result.plate ?? '-'}',
      '선택칩: ${result.selectedChipLabel ?? '-'}',
      'attemptCount: ${result.attemptCount}',
      '마지막 OCR 텍스트: ${result.lastOcrText ?? '-'}',
      '마지막 실패사유: ${result.lastFailureReason ?? '-'}',
      '후보값: ${result.candidateValues.isEmpty ? '-' : result.candidateValues.join(', ')}',
      'usedLearningMid: ${result.usedLearningMid}',
      'usedLearningRank: ${result.usedLearningRank}',
      'weakFront: ${result.weakFront ?? '-'}',
      'weakBack: ${result.weakBack ?? '-'}',
      'weakObservedValue: ${result.weakObservedValue ?? '-'}',
      'requiresMidCompletion: ${result.requiresMidCompletion}',
      'weakMidSuggestions: ${result.weakMidSuggestions.isEmpty ? '-' : result.weakMidSuggestions.join(', ')}',
      'weakCorrectionWillLinkOnSubmit: ${result.requiresMidCompletion && result.weakObservedValue != null}',
      '',
      '----- OCR SESSION LOG -----',
      result.logText.isEmpty ? '로그가 없습니다.' : result.logText,
    ];
    return summary.join('\n');
  }

  Future<void> _showOcrSessionDialog() async {
    final result = _lastOcrSessionResult;
    if (result == null || !mounted) return;

    final cs = Theme.of(context).colorScheme;
    final text = _buildOcrClipboardText(result);

    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: cs.surface,
        title: const Text('OCR 세션 로그'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('종료 유형: ${_ocrExitTypeLabel(result.exitType)}'),
                Text('최종 번호판: ${result.plate ?? '-'}'),
                Text('선택 칩: ${result.selectedChipLabel ?? '-'}'),
                Text('시도 횟수: ${result.attemptCount}'),
                Text('마지막 실패 사유: ${result.lastFailureReason ?? '-'}'),
                Text('weakFront: ${result.weakFront ?? '-'}'),
                Text('weakBack: ${result.weakBack ?? '-'}'),
                Text('weakObservedValue: ${result.weakObservedValue ?? '-'}'),
                Text('mid 보정 필요: ${result.requiresMidCompletion}'),
                Text(
                  'mid 제안: ${result.weakMidSuggestions.isEmpty ? '-' : result.weakMidSuggestions.join(', ')}',
                ),
                Text(
                  '최종 등록 시 보정 학습 연결: ${result.requiresMidCompletion && result.weakObservedValue != null}',
                ),
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: cs.outlineVariant.withOpacity(0.85),
                    ),
                  ),
                  child: SelectableText(
                    result.logText.isEmpty ? '로그가 없습니다.' : result.logText,
                    style: TextStyle(
                      fontSize: 12,
                      height: 1.35,
                      color: cs.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              if (!mounted) return;
              Navigator.pop(context);
            },
            child: const Text('복사'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      ),
    );
  }

  Widget _buildTopRightOcrLogAction(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final hasLog = _lastOcrSessionResult != null;

    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(right: 6, top: 2),
          child: Semantics(
            label: hasLog ? 'ocr_log_available' : 'ocr_log_unavailable',
            button: true,
            child: IconButton(
              tooltip: hasLog ? 'OCR 로그 보기' : 'OCR 로그 없음',
              onPressed: hasLog ? _showOcrSessionDialog : null,
              icon: Icon(
                Icons.article_outlined,
                color: hasLog
                    ? cs.onSurface
                    : cs.onSurfaceVariant.withOpacity(0.40),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _loadVehicleManufacturers() async {
    try {
      final manufacturers = await _vehiclePrefRepo.getManufacturers();
      if (!mounted) return;
      setState(() => _manufacturerOptions = manufacturers);
    } catch (e) {
      debugPrint('[VehicleParkingPreference] manufacturer load failed: $e');
    }
  }

  Future<String?> _showCenteredOptionDialog({
    required String title,
    required List<String> options,
    String? selectedValue,
  }) {
    final cs = Theme.of(context).colorScheme;

    return showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          backgroundColor: cs.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 420,
              maxHeight: 520,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 8, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: () => Navigator.of(dialogContext).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                Divider(height: 1, color: cs.outlineVariant.withOpacity(0.85)),
                Flexible(
                  child: options.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text(
                            '선택 가능한 항목이 없습니다.',
                            style: TextStyle(color: cs.onSurfaceVariant),
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: options.length,
                          separatorBuilder: (_, __) => Divider(
                            height: 1,
                            color: cs.outlineVariant.withOpacity(0.45),
                          ),
                          itemBuilder: (_, index) {
                            final value = options[index];
                            final selected = value == selectedValue;

                            return ListTile(
                              title: Text(
                                value,
                                style: TextStyle(
                                  fontWeight: selected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
                                  color: cs.onSurface,
                                ),
                              ),
                              trailing: selected
                                  ? Icon(Icons.check_rounded,
                                      color: cs.primary)
                                  : null,
                              onTap: () =>
                                  Navigator.of(dialogContext).pop(value),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openManufacturerDialog() async {
    if (_manufacturerOptions.isEmpty) {
      await _loadVehicleManufacturers();
    }
    if (!mounted) return;

    final selected = await _showCenteredOptionDialog(
      title: '제조사 선택',
      options: _manufacturerOptions,
      selectedValue: _selectedManufacturerName,
    );

    if (!mounted || selected == null) return;

    final models = await _vehiclePrefRepo.getModelsByManufacturer(selected);
    if (!mounted) return;

    setState(() {
      _selectedManufacturerName = selected;
      _selectedModelName = null;
      _modelOptions = models;
      controller.selectedManufacturerName = selected;
      controller.selectedModelName = null;
      controller.priority1SlotKey = null;
      controller.priority2SlotKey = null;
      controller.priority3SlotKey = null;
    });
  }

  Future<void> _openModelDialog() async {
    final manufacturer = _selectedManufacturerName;
    if (manufacturer == null || manufacturer.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('제조사를 먼저 선택해주세요.')),
      );
      return;
    }

    if (_modelOptions.isEmpty) {
      final models = await _vehiclePrefRepo.getModelsByManufacturer(manufacturer);
      if (!mounted) return;
      setState(() => _modelOptions = models);
    }
    if (!mounted) return;

    final selected = await _showCenteredOptionDialog(
      title: '차종 선택',
      options: _modelOptions,
      selectedValue: _selectedModelName,
    );

    if (!mounted || selected == null) return;

    final pref = await _vehiclePrefRepo.findPreference(
      manufacturerName: manufacturer,
      modelName: selected,
    );
    if (!mounted) return;

    setState(() {
      _selectedModelName = selected;
      controller.selectedManufacturerName = manufacturer;
      controller.selectedModelName = selected;
      controller.priority1SlotKey = pref?.priority1SlotKey;
      controller.priority2SlotKey = pref?.priority2SlotKey;
      controller.priority3SlotKey = pref?.priority3SlotKey;
    });
  }

  void _openRegionPicker() {
    inputRegionPickerBottomSheet(
      context: context,
      selectedRegion: controller.dropdownValue,
      regions: controller.regions,
      onConfirm: (region) {
        setState(() {
          controller.dropdownValue = region;
        });
      },
    );
  }

  Future<void> _openLiveScanner() async {
    final sessionId = const Uuid().v4();
    final result = await Navigator.of(context).push<LiveOcrSessionResult>(
      MaterialPageRoute(builder: (_) => LiveOcrPage(sessionId: sessionId)),
    );
    if (!mounted || result == null) return;

    setState(() {
      _lastOcrSessionResult = result;
    });

    if (result.plate != null && result.plate!.isNotEmpty) {
      _applyPlateWithFallback(result.plate!, sessionId: result.sessionId);
      return;
    }

    if (result.requiresMidCompletion &&
        result.weakFront != null &&
        result.weakBack != null) {
      _applyToFields(
        front: result.weakFront!,
        mid: '',
        back: result.weakBack!,
        promptMid: true,
        sessionId: result.sessionId,
      );
      return;
    }

    if (result.exitType == LiveOcrExitType.userAborted) {
      return;
    }
  }

  void _beginDockEdit(_DockField field) {
    final prevMid =
        field == _DockField.mid ? controller.controllerMidDigit.text : null;
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
          _midBeforeEdit = prevMid ?? '';
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
            if (controller.controllerMidDigit.text.isEmpty &&
                _midBeforeEdit.isNotEmpty) {
              controller.controllerMidDigit.text = _midBeforeEdit;
            }
            controller.showKeypad = false;
            _dockEditing = null;
            _midBeforeEdit = '';
          } else {
            _midBeforeEdit = '';
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
      selectedRegion: controller.dropdownValue,
      onTapRegion: _openRegionPicker,
      onActivateFront: () => _beginDockEdit(_DockField.front),
      onActivateMid: () => _beginDockEdit(_DockField.mid),
      onActivateBack: () => _beginDockEdit(_DockField.back),
    );
  }

  Widget _buildBottomBar() {
    final cs = Theme.of(context).colorScheme;

    final actionButton = InputBottomActionSection(
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
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
            padding:
                const EdgeInsets.only(left: 12, right: 12, top: 6, bottom: 8),
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
    final cs = Theme.of(context).colorScheme;

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
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: cs.tertiaryContainer.withOpacity(0.55),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: cs.outlineVariant.withOpacity(0.85)),
                    ),
                    child: Text(
                      '정기 주차가 제한된 근무지입니다.',
                      style: TextStyle(
                          fontSize: 12, height: 1.25, color: cs.onSurface),
                    ),
                  ),
                ),
              InputBillSection(
                selectedBill: controller.selectedBill,
                onChanged: (value) =>
                    setState(() => controller.selectedBill = value),
                selectedBillType: controller.selectedBillType,
                onTypeChanged: (newType) {
                  if (newType == '정기' &&
                      _hasMonthlyLoaded &&
                      !_hasMonthlyParking) {
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
        final begin = _dockSlideFromRight
            ? const Offset(0.10, 0)
            : const Offset(-0.10, 0);
        final offsetAnim =
            Tween<Offset>(begin: begin, end: Offset.zero).animate(animation);
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
      onHorizontalDragEnd: (d) =>
          _handleDockHorizontalSwipe(d, canSwipe: canSwipe),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final sysBottom = MediaQuery.of(context).padding.bottom;
    final bottomSafePadding =
        (controller.showKeypad ? 280.0 : 140.0) + viewInset + sysBottom;

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
        backgroundColor: cs.background,
        appBar: AppBar(
          automaticallyImplyLeading: false,
          centerTitle: true,
          backgroundColor: cs.surface,
          foregroundColor: cs.onSurface,
          elevation: 0,
          surfaceTintColor: Colors.transparent,
          shape: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withOpacity(0.85),
              width: 1,
            ),
          ),
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
                          controller.isThreeDigit
                              ? '현재 앞자리: 세자리'
                              : '현재 앞자리: 두자리',
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
                _buildTopRightOcrLogAction(context),
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
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: EdgeInsets.fromLTRB(16, 16, 16, bottomSafePadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InputPlateSection(
                          selectedManufacturerName: _selectedManufacturerName,
                          selectedModelName: _selectedModelName,
                          onTapManufacturer: _openManufacturerDialog,
                          onTapModel: _openModelDialog,
                        ),
                        const SizedBox(height: 16),
                        InputLocationSection(
                          locationController: controller.locationController,
                        ),
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
                    _sheetScrollController = scrollController;

                    final bool lockScroll = _isSheetFullyClosed();
                    final bool canSwipe = !lockScroll;

                    final sheetBottomPadding = 16.0 + viewInset;

                    return Container(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
                        border: Border.all(
                            color: cs.outlineVariant.withOpacity(0.85)),
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
                        borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(16)),
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
                                  if (scrollController.hasClients &&
                                      scrollController.offset != 0) {
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
                                    onSelectBill: () =>
                                        _setDockPage(_dockPageBill),
                                    onSelectMemo: () =>
                                        _setDockPage(_dockPageMemo),
                                  ),
                                ),
                                SliverPadding(
                                  padding: EdgeInsets.fromLTRB(
                                      16, 12, 16, sheetBottomPadding),
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
                    child:
                        Icon(Icons.check_rounded, color: cs.primary, size: 20),
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
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerLow,
                  borderRadius: BorderRadius.circular(14),
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                  border:
                      Border.all(color: cs.outlineVariant.withOpacity(0.85)),
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
                      child: Icon(Icons.note_alt_rounded,
                          size: 18, color: cs.primary),
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
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        side: BorderSide(
                            color: cs.outlineVariant.withOpacity(0.85)),
                        foregroundColor: cs.onSurface,
                      ),
                      child: const Text('닫기',
                          style: TextStyle(fontWeight: FontWeight.w900)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onGoMemo,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                        backgroundColor: cs.primary,
                        foregroundColor: cs.onPrimary,
                      ),
                      child: const Text('상태 메모 보기',
                          style: TextStyle(fontWeight: FontWeight.w900)),
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

    final bg = selected ? cs.surfaceContainerLow : Colors.transparent;
    final border = selected
        ? cs.primary.withOpacity(0.55)
        : cs.outlineVariant.withOpacity(0.85);
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
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    final cs = Theme.of(context).colorScheme;

    final VoidCallback? outerTap = sheetOpen ? null : onToggle;

    final bool billSelected =
        currentPageIndex == _InputPlateScreenState._dockPageBill;
    final bool memoSelected =
        currentPageIndex == _InputPlateScreenState._dockPageMemo;

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
                    child:
                        _SheetHandle(color: cs.outlineVariant.withOpacity(0.9)),
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
  final InputPlateController controller;
  final String selectedRegion;
  final VoidCallback onTapRegion;
  final VoidCallback onActivateFront;
  final VoidCallback onActivateMid;
  final VoidCallback onActivateBack;

  const _PlateDock({
    required this.controller,
    required this.selectedRegion,
    required this.onTapRegion,
    required this.onActivateFront,
    required this.onActivateMid,
    required this.onActivateBack,
  });

  InputDecoration _dec(BuildContext context, bool active, bool compact) {
    final cs = Theme.of(context).colorScheme;

    return InputDecoration(
      isDense: true,
      contentPadding: EdgeInsets.symmetric(
        horizontal: compact ? 4 : 6,
        vertical: compact ? 8 : 10,
      ),
      filled: true,
      fillColor: active ? cs.primary.withOpacity(0.08) : cs.surface,
      counterText: '',
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(
          color: active
              ? cs.primary.withOpacity(0.75)
              : cs.outlineVariant.withOpacity(0.85),
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

  Widget _buildRegionBox(BuildContext context, bool compact) {
    final cs = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTapRegion,
        child: Container(
          height: compact ? 46 : 50,
          padding: EdgeInsets.symmetric(horizontal: compact ? 4 : 6),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            border: Border.all(color: cs.outlineVariant.withOpacity(0.85)),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  selectedRegion,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w900,
                    color: cs.onSurface,
                  ),
                ),
              ),
              SizedBox(width: compact ? 1 : 2),
              Icon(
                Icons.expand_more,
                size: compact ? 15 : 17,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
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
    required bool compact,
  }) {
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: onTap,
      child: AbsorbPointer(
        child: TextField(
          controller: textController,
          readOnly: true,
          maxLength: maxLength,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: compact ? 18 : 20,
            fontWeight: FontWeight.w900,
            color: cs.onSurface,
            height: 1.0,
          ),
          decoration: _dec(context, isActive, compact),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isFrontActive =
        controller.activeController == controller.controllerFrontDigit;
    final isMidActive =
        controller.activeController == controller.controllerMidDigit;
    final isBackActive =
        controller.activeController == controller.controllerBackDigit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 340;
        final gap = compact ? 4.0 : 6.0;
        final regionWidth = compact ? 54.0 : 62.0;
        final labelStyle = TextStyle(
          fontSize: compact ? 10 : 11,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        );

        return Container(
          margin: EdgeInsets.symmetric(horizontal: compact ? 8 : 12),
          padding: EdgeInsets.symmetric(
            horizontal: compact ? 8 : 10,
            vertical: compact ? 8 : 10,
          ),
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
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: regionWidth,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('지역', style: labelStyle),
                    const SizedBox(height: 4),
                    _buildRegionBox(context, compact),
                  ],
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 30,
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
                      compact: compact,
                    ),
                  ],
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 17,
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
                      compact: compact,
                    ),
                  ],
                ),
              ),
              SizedBox(width: gap),
              Expanded(
                flex: 40,
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
                      compact: compact,
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
