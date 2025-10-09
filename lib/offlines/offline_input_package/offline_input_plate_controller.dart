import 'package:flutter/material.dart';
import 'package:camera/camera.dart';

import '../../utils/snackbar_helper.dart';
import 'utils/offline_input_plate_service.dart';

// ▼ SQLite (경로는 프로젝트에 맞게 조정하세요)
import '../sql/offline_auth_db.dart';
import '../sql/offline_auth_service.dart';

class OfflineInputPlateController {
  final TextEditingController controllerFrontDigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();
  final TextEditingController customStatusController = TextEditingController();

  final TextEditingController countTypeController = TextEditingController();

  bool showKeypad = true;
  bool isLoading = false;
  bool isLocationSelected = false;
  String dropdownValue = '전국';

  String selectedBillType = '변동';
  String? selectedBill; // ✅ 공개 필드로 단순화

  int selectedBasicStandard = 0;
  int selectedBasicAmount = 0;
  int selectedAddStandard = 0;
  int selectedAddAmount = 0;

  bool isThreeDigit = true;

  String? fetchedCustomStatus;

  List<String> statuses = [];
  List<bool> isSelected = [];
  List<String> selectedStatuses = [];

  List<String> fetchedStatusList = [];

  final List<String> regions = const [
    '전국',
    '강원',
    '경기',
    '경남',
    '경북',
    '광주',
    '대구',
    '대전',
    '부산',
    '서울',
    '울산',
    '인천', // NOTE: 필요 시 원문 유지 가능
    '전남',
    '전북',
    '제주',
    '충남',
    '충북',
    '국기',
    '대표',
    '영사',
    '외교',
    '임시',
    '준영',
    '준외',
    '협정',
  ];

  late TextEditingController activeController;
  final List<XFile> capturedImages = [];

  OfflineInputPlateController() {
    activeController = controllerFrontDigit;
    _addInputListeners();
  }

  void _addInputListeners() {
    controllerFrontDigit.addListener(_handleInputChange);
    controllerMidDigit.addListener(_handleInputChange);
    controllerBackDigit.addListener(_handleInputChange);
  }

  void _removeInputListeners() {
    controllerFrontDigit.removeListener(_handleInputChange);
    controllerMidDigit.removeListener(_handleInputChange);
    controllerBackDigit.removeListener(_handleInputChange);
  }

  void _handleInputChange() {}

  void setActiveController(TextEditingController controller) {
    activeController = controller;
    showKeypad = true;
  }

  void setFrontDigitMode(bool isThree) {
    isThreeDigit = isThree;
    controllerFrontDigit.clear();
    setActiveController(controllerFrontDigit);
  }

  void clearInput() {
    controllerFrontDigit.clear();
    controllerMidDigit.clear();
    controllerBackDigit.clear();
    activeController = controllerFrontDigit;
    showKeypad = true;
  }

  void clearLocation() {
    locationController.clear();
    isLocationSelected = false;
  }

  void resetForm() {
    clearInput();
    clearLocation();
    capturedImages.clear();
    selectedStatuses.clear();
    selectedBill = null; // ✅ 변경 반영
    selectedBasicStandard = 0;
    selectedBasicAmount = 0;
    selectedAddStandard = 0;
    selectedAddAmount = 0;

    customStatusController.clear();
    countTypeController.clear();

    fetchedCustomStatus = null;
    fetchedStatusList = [];
    isSelected = List.generate(statuses.length, (_) => false);
    isThreeDigit = true;
    selectedBillType = '변동';
  }

  String buildPlateNumber() {
    return '${controllerFrontDigit.text}-${controllerMidDigit.text}-${controllerBackDigit.text}';
  }

  bool isInputValid() {
    final validFront =
    isThreeDigit ? controllerFrontDigit.text.length == 3 : controllerFrontDigit.text.length == 2;
    return validFront && controllerMidDigit.text.length == 1 && controllerBackDigit.text.length == 4;
  }

  void dispose() {
    _removeInputListeners();
    controllerFrontDigit.dispose();
    controllerMidDigit.dispose();
    controllerBackDigit.dispose();
    locationController.dispose();
    customStatusController.dispose();
    countTypeController.dispose();
  }

  /// (이전 Firestore) 사용자 정의 상태 제거 → 로컬 SQLite 최신 1건에서 custom_status 초기화
  Future<void> deleteCustomStatusFromFirestore(BuildContext context) async {
    final plateNumber = buildPlateNumber();
    final area = await _loadCurrentArea();

    final db = await OfflineAuthDb.instance.database;
    await db.transaction((txn) async {
      // 최신 1건 조회
      final rows = await txn.query(
        OfflineAuthDb.tablePlates,
        columns: const ['id'],
        where: 'plate_number = ? AND area = ?',
        whereArgs: [plateNumber, area],
        orderBy: 'created_at DESC',
        limit: 1,
      );
      if (rows.isEmpty) return;

      final id = rows.first['id'] as int;
      await txn.update(
        OfflineAuthDb.tablePlates,
        {
          'custom_status': '',
          'updated_at': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'id = ?',
        whereArgs: [id],
      );
      fetchedCustomStatus = null;
      fetchedStatusList = [];
    });
  }

  Future<void> submitPlateEntry(
      BuildContext context,
      VoidCallback refreshUI,
      ) async {
    final plateNumber = buildPlateNumber();

    isLoading = true;
    refreshUI();

    // await 전이므로 context 사용 OK
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final wasSuccessful = await OfflineInputPlateService.registerPlateEntry(
        context: context, // 내부에서도 mounted 체크 필요
        plateNumber: plateNumber,
        location: locationController.text,
        isLocationSelected: isLocationSelected,
        selectedBill: selectedBill, // ✅ 변경 반영
        selectedStatuses: selectedStatuses,
        basicStandard: selectedBasicStandard,
        basicAmount: selectedBasicAmount,
        addStandard: selectedAddStandard,
        addAmount: selectedAddAmount,
        region: dropdownValue,
        customStatus: customStatusController.text.trim().isNotEmpty
            ? customStatusController.text
            : fetchedCustomStatus ?? '',
        selectedBillType: selectedBillType,
      );

      // ✅ Firestore 연동 제거 (로컬만 사용)

      // async gap 이후 BuildContext 안전성 확인
      if (!context.mounted) return;

      Navigator.of(context).pop();
      if (wasSuccessful) {
        showSuccessSnackbar(context, '차량 정보 등록 완료');
        resetForm();
      }
    } catch (e) {
      if (!context.mounted) return;

      Navigator.of(context).pop();
      showFailedSnackbar(context, '등록 실패: ${e.toString()}');
    } finally {
      isLoading = false;
      if (context.mounted) {
        refreshUI();
      }
    }
  }

  // ─────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────

  Future<String> _loadCurrentArea() async {
    final db = await OfflineAuthDb.instance.database;
    final session = await OfflineAuthService.instance.currentSession();
    final uid = (session?.userId ?? '').trim();

    String area = '';

    if (uid.isNotEmpty) {
      final r1 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'userId = ?',
        whereArgs: [uid],
        limit: 1,
      );
      if (r1.isNotEmpty) {
        area = ((r1.first['currentArea'] as String?) ??
            (r1.first['selectedArea'] as String?) ??
            '')
            .trim();
      }
    }

    if (area.isEmpty) {
      final r2 = await db.query(
        OfflineAuthDb.tableAccounts,
        columns: const ['currentArea', 'selectedArea'],
        where: 'isSelected = 1',
        limit: 1,
      );
      if (r2.isNotEmpty) {
        area = ((r2.first['currentArea'] as String?) ??
            (r2.first['selectedArea'] as String?) ??
            '')
            .trim();
      }
    }

    if (area.isEmpty) area = 'HQ 지역';
    return area;
  }
}
