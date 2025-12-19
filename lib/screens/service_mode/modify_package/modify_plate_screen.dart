import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../models/plate_model.dart';
import '../../../enums/plate_type.dart';

import '../../../states/area/area_state.dart';
import '../../../utils/usage/usage_reporter.dart';

import 'modify_plate_controller.dart';
import 'sections/modify_location_section.dart';
import 'sections/modify_photo_section.dart';
import 'sections/modify_plate_section.dart';
import 'sections/modify_status_custom_section.dart';

import 'utils/buttons/modify_animated_action_button.dart';
import 'utils/buttons/modify_animated_parking_button.dart';
import 'utils/buttons/modify_animated_photo_button.dart';

import 'widgets/modify_bottom_navigation.dart';
import 'widgets/modify_camera_preview_dialog.dart';
import 'widgets/modify_location_bottom_sheet.dart';
import '../../../utils/snackbar_helper.dart';
import 'utils/modify_camera_helper.dart';

class ModifyPlateScreen extends StatefulWidget {
  final PlateModel plate;
  final PlateType collectionKey;

  const ModifyPlateScreen({
    super.key,
    required this.plate,
    required this.collectionKey,
  });

  @override
  State<ModifyPlateScreen> createState() => _ModifyPlateScreenState();
}

class _ModifyPlateScreenState extends State<ModifyPlateScreen> {
  // ⬇️ 화면 식별 태그(FAQ/에러 리포트 연계용)
  static const String screenTag = 'plate modify';

  // ✅ Firestore
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // ✅ Firestore 경로 상수(정책 고정)
  static const String _plateStatusRoot = 'plate_status';
  static const String _monthsSub = 'months';
  static const String _platesSub = 'plates';

  late ModifyPlateController _controller;
  late ModifyCameraHelper _cameraHelper;

  final TextEditingController controllerFrontdigit = TextEditingController();
  final TextEditingController controllerMidDigit = TextEditingController();
  final TextEditingController controllerBackDigit = TextEditingController();
  final TextEditingController locationController = TextEditingController();

  final List<XFile> _capturedImages = [];
  final List<String> _existingImageUrls = [];

  bool isLoading = false;
  late List<String> selectedStatusNames;

  // ✅ plate_status에서 실제로 찾은 문서 ref를 보관(삭제/업데이트 시 동일 문서 타겟 보장)
  DocumentReference<Map<String, dynamic>>? _resolvedPlateStatusRef;

  // ───── DraggableScrollableSheet 상태/애니메이션 ─────
  final DraggableScrollableController _sheetController = DraggableScrollableController();
  bool _sheetOpen = false; // 현재 열림 상태
  static const double _sheetClosed = 0.16; // 헤더만 보이게
  static const double _sheetOpened = 1.00; // 최상단까지(가득)

  // ─────────────────────────────
  // ✅ 문서명 정책 유틸
  // ─────────────────────────────

  /// area가 비어있으면 doc('')/경로 불일치 → 안전 처리
  String _safeArea(String area) {
    final a = area.trim();
    return a.isEmpty ? 'unknown' : a;
  }

  /// ✅ 레거시(읽기/삭제 폴백용): 과거 하이픈 제거 docId 저장 데이터 대응
  String _legacyPlatePk(String plateNumber) {
    return plateNumber.replaceAll('-', '').replaceAll(' ', '').trim();
  }

  /// yyyyMM
  String _monthKey(DateTime dt) => '${dt.year}${dt.month.toString().padLeft(2, '0')}';

  /// ✅ plateNumber 표기 차이(하이픈 유무)를 흡수하기 위한 후보 생성
  List<String> _plateNumberVariants(String plateNumber) {
    final t = plateNumber.trim().replaceAll(' ', '');
    final raw = t.replaceAll('-', '');

    final m = RegExp(r'^(\d{2,3})([가-힣])(\d{4})$').firstMatch(raw);
    if (m == null) {
      return [t];
    }

    final noHyphen = '${m.group(1)}${m.group(2)}${m.group(3)}';
    final withHyphen = '${m.group(1)}-${m.group(2)}-${m.group(3)}';

    final res = <String>[];
    void add(String s) {
      if (s.isNotEmpty && !res.contains(s)) res.add(s);
    }

    add(t); // 원문 우선
    add(noHyphen); // 72로6085
    add(withHyphen); // 72-로-6085
    return res;
  }

  /// ✅ "{plateNumber}_{area}" docId 후보 리스트(하이픈/비하이픈 둘 다)
  List<String> _plateDocIdCandidates(String plateNumber, String area) {
    final a = _safeArea(area);
    return _plateNumberVariants(plateNumber).map((p) => '${p}_$a').toList();
  }

  /// ✅ 레거시 pk 후보들(하이픈 제거)
  List<String> _legacyPkCandidates(String plateNumber) {
    final res = <String>[];
    for (final p in _plateNumberVariants(plateNumber)) {
      final legacy = _legacyPlatePk(p);
      if (legacy.isNotEmpty && !res.contains(legacy)) res.add(legacy);
    }
    return res;
  }

  String _currentAreaSafe() {
    try {
      final a = context.read<AreaState>().currentArea;
      return _safeArea(a);
    } catch (_) {
      return 'unknown';
    }
  }

  // ─────────────────────────────
  // ✅ plate_status 조회/해결(월샤딩 + 폴백)
  // ─────────────────────────────

  Future<_PlateStatusLookupResult?> _lookupPlateStatus({
    required String plateNumber,
    required String area,
  }) async {
    int reads = 0;
    final safeArea = _safeArea(area);

    final docIdCandidates = _plateDocIdCandidates(plateNumber, safeArea);
    final legacyCandidates = _legacyPkCandidates(plateNumber);

    final now = DateTime.now();
    final monthsToTry = <DateTime>[
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month - 1, 1),
    ];

    try {
      // 1) 빠른 경로: 현재월/전월
      for (final m in monthsToTry) {
        final mk = _monthKey(m);

        // 신규 docId 후보들
        for (final docId in docIdCandidates) {
          final ref = _firestore
              .collection(_plateStatusRoot)
              .doc(safeArea)
              .collection(_monthsSub)
              .doc(mk)
              .collection(_platesSub)
              .doc(docId);

          final snap = await ref.get();
          reads += 1;

          if (snap.exists) {
            return _PlateStatusLookupResult(
              data: snap.data() ?? <String, dynamic>{},
              ref: ref,
              reads: reads,
            );
          }
        }

        // 레거시 후보들
        for (final legacyId in legacyCandidates) {
          final ref = _firestore
              .collection(_plateStatusRoot)
              .doc(safeArea)
              .collection(_monthsSub)
              .doc(mk)
              .collection(_platesSub)
              .doc(legacyId);

          final snap = await ref.get();
          reads += 1;

          if (snap.exists) {
            return _PlateStatusLookupResult(
              data: snap.data() ?? <String, dynamic>{},
              ref: ref,
              reads: reads,
            );
          }
        }
      }

      // 2) 느린 경로: 전체월 폴백(collectionGroup)
      try {
        final subset = docIdCandidates.take(10).toList();
        if (subset.isNotEmpty) {
          final qs = await _firestore
              .collectionGroup(_platesSub)
              .where(FieldPath.documentId, whereIn: subset)
              .get();
          reads += 1;

          if (qs.docs.isNotEmpty) {
            QueryDocumentSnapshot<Map<String, dynamic>>? best;
            int bestMonth = -1;

            for (final d in qs.docs) {
              final path = d.reference.path;
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

            final chosen = best ?? qs.docs.first;
            return _PlateStatusLookupResult(
              data: chosen.data(),
              ref: chosen.reference,
              reads: reads,
            );
          }
        }

        final legacySubset = legacyCandidates.take(10).toList();
        if (legacySubset.isNotEmpty) {
          final qsLegacy = await _firestore
              .collectionGroup(_platesSub)
              .where(FieldPath.documentId, whereIn: legacySubset)
              .get();
          reads += 1;

          if (qsLegacy.docs.isNotEmpty) {
            QueryDocumentSnapshot<Map<String, dynamic>>? best;
            int bestMonth = -1;

            for (final d in qsLegacy.docs) {
              final path = d.reference.path;
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

            final chosen = best ?? qsLegacy.docs.first;
            return _PlateStatusLookupResult(
              data: chosen.data(),
              ref: chosen.reference,
              reads: reads,
            );
          }
        }
      } on FirebaseException catch (e) {
        debugPrint('[ModifyPlateScreen] collectionGroup fallback blocked: ${e.code} ${e.message}');
      }

      return null;
    } catch (e) {
      debugPrint('[ModifyPlateScreen] _lookupPlateStatus error: $e');
      return null;
    } finally {
      final nToReport = (reads <= 0) ? 1 : reads;
      try {
        await UsageReporter.instance.report(
          area: safeArea,
          action: 'read',
          n: nToReport,
          source: 'ModifyPlateScreen._lookupPlateStatus/plate_status.lookup',
          useSourceOnlyKey: true,
        );
      } catch (e) {
        debugPrint('[UsageReporter] report failed in _lookupPlateStatus: $e');
      }
    }
  }

  Future<void> _loadPlateStatusToUiOnce() async {
    final plateNumber = widget.plate.plateNumber;
    final area = _currentAreaSafe();

    final result = await _lookupPlateStatus(plateNumber: plateNumber, area: area);
    if (!mounted) return;
    if (result == null) return;

    final data = result.data;
    _resolvedPlateStatusRef = result.ref;

    final fetchedStatus = (data['customStatus'] as String?)?.trim();
    final fetchedList =
        (data['statusList'] as List<dynamic>?)?.map((e) => e.toString()).toList() ?? [];
    final fetchedCountType = (data['countType'] as String?)?.trim();

    setState(() {
      _controller.fetchedCustomStatus = fetchedStatus;
      _controller.customStatusController.text = fetchedStatus ?? '';
      selectedStatusNames = fetchedList;

      // ✅ 정산 유형은 사용자 수정 불가이지만, "서버에 저장된 현재값 표기"는 허용
      // (원치 않으면 이 블록을 제거하면 됩니다)
      if (fetchedCountType != null && fetchedCountType.isNotEmpty) {
        _controller.selectedBillCountType = fetchedCountType;
        _controller.selectedBill = fetchedCountType;
      }
    });
  }

  Future<void> _deletePlateStatusMemoAndStatus() async {
    if (_resolvedPlateStatusRef == null) {
      final plateNumber = widget.plate.plateNumber;
      final area = _currentAreaSafe();
      final result = await _lookupPlateStatus(plateNumber: plateNumber, area: area);
      if (result == null) {
        throw StateError('plate_status 문서를 찾을 수 없습니다.');
      }
      _resolvedPlateStatusRef = result.ref;
    }

    final ref = _resolvedPlateStatusRef!;
    try {
      await ref.update({
        'customStatus': FieldValue.delete(),
        'statusList': FieldValue.delete(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      try {
        await UsageReporter.instance.report(
          area: _currentAreaSafe(),
          action: 'write',
          n: 1,
          source: 'ModifyPlateScreen._deletePlateStatusMemoAndStatus/plate_status.doc.update(delete)',
          useSourceOnlyKey: true,
        );
      } catch (e) {
        debugPrint('[UsageReporter] report failed in _deletePlateStatusMemoAndStatus: $e');
      }
    } on FirebaseException catch (e) {
      debugPrint('[ModifyPlateScreen] delete memo firebase error: ${e.code} ${e.message}');
      rethrow;
    }
  }

  // ─────────────────────────────
  // ✅ Sheet open 상태 동기화(드래그 포함)
  // ─────────────────────────────
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

  void _toggleSheet() {
    _animateSheet(open: !_sheetOpen);
  }

  @override
  void initState() {
    super.initState();

    _controller = ModifyPlateController(
      context: context,
      plate: widget.plate,
      collectionKey: widget.collectionKey,
      controllerFrontdigit: controllerFrontdigit,
      controllerMidDigit: controllerMidDigit,
      controllerBackDigit: controllerBackDigit,
      locationController: locationController,
      capturedImages: _capturedImages,
      existingImageUrls: _existingImageUrls,
    );

    _cameraHelper = ModifyCameraHelper();

    _cameraHelper.initializeInputCamera().then((_) {
      if (mounted) setState(() {});
    });

    _controller.initializePlate();
    _controller.initializeFieldValues();

    selectedStatusNames = List<String>.from(widget.plate.statusList);

    _sheetController.addListener(() {
      try {
        final s = _sheetController.size;
        final bool openNow = s >= ((_sheetClosed + _sheetOpened) / 2);
        if (mounted && openNow != _sheetOpen) {
          setState(() => _sheetOpen = openNow);
        }
      } catch (_) {
        // ignore
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadPlateStatusToUiOnce();
    });
  }

  void _showCameraPreviewDialog() async {
    await _cameraHelper.initializeInputCamera();
    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (context) => ModifyCameraPreviewDialog(
        onImageCaptured: (image) {
          setState(() {
            _controller.capturedImages.add(image);
          });
        },
      ),
    );

    await _cameraHelper.dispose();
    await Future.delayed(const Duration(milliseconds: 200));
    if (mounted) setState(() {});
  }

  void _selectParkingLocation() {
    showDialog(
      context: context,
      builder: (_) => ModifyLocationBottomSheet(
        locationController: _controller.locationController,
        onLocationSelected: (location) {
          setState(() {
            _controller.locationController.text = location;
            _controller.isLocationSelected = true;
          });
        },
      ),
    );
  }

  VoidCallback _buildLocationAction() {
    return _selectParkingLocation;
  }

  @override
  void dispose() {
    _sheetController.dispose();
    _controller.dispose();
    _cameraHelper.dispose();
    super.dispose();
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

  @override
  Widget build(BuildContext context) {
    final viewInset = MediaQuery.of(context).viewInsets.bottom;
    final bottomSafePadding = 140.0 + viewInset;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        centerTitle: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 1,
        flexibleSpace: _buildScreenTag(context),
        title: const Text(
          "번호판 수정",
          style: TextStyle(color: Colors.grey, fontSize: 16),
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
                      ModifyPlateSection(
                        dropdownValue: _controller.dropdownValue,
                        regions: _controller.regions,
                        controllerFrontdigit: controllerFrontdigit,
                        controllerMidDigit: controllerMidDigit,
                        controllerBackDigit: controllerBackDigit,
                        isEditable: false,
                        onRegionChanged: (region) {
                          setState(() => _controller.dropdownValue = region);
                        },
                      ),
                      const SizedBox(height: 32.0),
                      ModifyLocationSection(locationController: _controller.locationController),
                      const SizedBox(height: 32.0),
                      ModifyPhotoSection(
                        capturedImages: _controller.capturedImages,
                        imageUrls: widget.plate.imageUrls ?? [],
                        plateNumber: widget.plate.plateNumber,
                      ),
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

                  return Container(
                    decoration: const BoxDecoration(
                      color: sheetBg,
                      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, -4)),
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
                          16 + 100 + viewInset,
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
                                        _sheetOpen ? '정산 / 상태 (탭하여 닫기)' : '정산 / 상태 (탭하여 열기)',
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      Text(
                                        widget.plate.plateNumber,
                                        style: const TextStyle(color: Colors.black54),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),

                          // ✅ 정산 유형: 사용자 수정 불가(읽기 전용)
                          _ReadOnlyBillSection(
                            billTypeLabel: _controller.selectedBillType,
                            countTypeLabel: _controller.selectedBillCountType ??
                                _controller.selectedBill ??
                                widget.plate.billingType ??
                                '-',
                          ),

                          const SizedBox(height: 24),

                          const Text(
                            '추가 상태 메모 (최대 20자)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _controller.customStatusController,
                            maxLength: 20,
                            decoration: InputDecoration(
                              hintText: '예: 뒷범퍼 손상',
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                              contentPadding:
                              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            ),
                          ),

                          if (_controller.fetchedCustomStatus != null)
                            ModifyStatusCustomSection(
                              customStatus: _controller.fetchedCustomStatus!,
                              onDelete: () async {
                                try {
                                  await _deletePlateStatusMemoAndStatus();

                                  if (!mounted) return;
                                  setState(() {
                                    _controller.fetchedCustomStatus = null;
                                    _controller.customStatusController.clear();
                                    selectedStatusNames = [];
                                  });
                                  showSuccessSnackbar(context, '자동 메모가 삭제되었습니다');
                                } catch (_) {
                                  if (!mounted) return;
                                  showFailedSnackbar(context, '삭제 실패. 다시 시도해주세요');
                                }
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
          ModifyBottomNavigation(
            actionButton: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: ModifyAnimatedPhotoButton(onPressed: _showCameraPreviewDialog),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ModifyAnimatedParkingButton(
                        isLocationSelected: _controller.isLocationSelected,
                        onPressed: _buildLocationAction(),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                ModifyAnimatedActionButton(
                  isLoading: isLoading,
                  isLocationSelected: _controller.isLocationSelected,
                  buttonLabel: '수정 완료',
                  onPressed: () async {
                    setState(() => isLoading = true);

                    await _controller.handleAction(() {
                      if (mounted) {
                        Navigator.pop(context);
                        showSuccessSnackbar(context, "수정이 완료되었습니다!");
                      }
                    }, selectedStatusNames);

                    if (mounted) setState(() => isLoading = false);
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: SafeArea(
              top: false,
              child: SizedBox(
                height: 48,
                child: Image.asset('assets/images/pelican.png'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReadOnlyBillSection extends StatelessWidget {
  final String billTypeLabel;
  final String countTypeLabel;

  const _ReadOnlyBillSection({
    required this.billTypeLabel,
    required this.countTypeLabel,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '정산 유형',
          style: TextStyle(fontSize: 18.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12.0),

        // 타입/선택 모두 읽기 전용 표시
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border.all(color: Colors.black26),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  countTypeLabel.isEmpty ? '-' : countTypeLabel,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
              Text(
                billTypeLabel,
                style: const TextStyle(
                  color: Colors.black54,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),
        const Text(
          '정산 유형은 이 화면에서 변경할 수 없습니다.',
          style: TextStyle(fontSize: 12, color: Colors.black54),
        ),
      ],
    );
  }
}

class _PlateStatusLookupResult {
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> ref;
  final int reads;

  _PlateStatusLookupResult({
    required this.data,
    required this.ref,
    required this.reads,
  });
}
