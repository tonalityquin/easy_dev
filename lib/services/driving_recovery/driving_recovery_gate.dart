import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';

import '../../repositories/plate_repo_services/plate_repository.dart';
import '../../states/plate/minor_plate_state.dart';
import '../../states/plate/triple_plate_state.dart';
import '../../states/user/user_state.dart';

import '../../utils/snackbar_helper.dart';

// ✅ 모드별 상태 시트(기존 구현 재사용)
import '../../screens/minor_mode/type_package/parking_completed_package/widgets/minor_parking_completed_status_bottom_sheet.dart';
import '../../screens/triple_mode/type_package/parking_completed_package/widgets/triple_parking_completed_status_bottom_sheet.dart';

/// 앱 재실행/강제 종료 등으로 남아있는 '내 주행 중(선점)' 상태를
/// 업무 화면 진입 시 1회 감지하고 복구 UI(목록/잠금해제/상태열기)를 제공.
///
/// ✅ 변경: 복구 UI를 BottomSheet가 아닌 "정중앙 Dialog"로 표시합니다.
///
/// - MinorTypePage / TripleTypePage의 body에서 감싸서 사용합니다.
/// - Firestore 'plates'에서 isSelected=true & selectedBy=내이름 조건으로 조회합니다.
/// - 요청 계열(parking_requests / departure_requests)만 대상입니다.
/// - 같은 세션에서 중복 팝업 방지를 위해 내부적으로 1회만 실행합니다.
enum DrivingRecoveryMode { minor, triple }

class DrivingRecoveryGate extends StatefulWidget {
  const DrivingRecoveryGate({
    super.key,
    required this.mode,
    required this.child,
  });

  final DrivingRecoveryMode mode;
  final Widget child;

  @override
  State<DrivingRecoveryGate> createState() => _DrivingRecoveryGateState();
}

class _DrivingRecoveryGateState extends State<DrivingRecoveryGate> {
  @override
  void initState() {
    super.initState();

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;

      // 라우트가 current가 아니면(다른 모달 위) 실행하지 않음
      final route = ModalRoute.of(context);
      if (route != null && route.isCurrent != true) return;

      await DrivingRecoveryService.maybePrompt(context, mode: widget.mode);
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class DrivingRecoveryService {
  static bool _promptedInThisSession = false;

  static const List<String> _targetTypes = <String>[
    'parking_requests',
    'departure_requests',
  ];

  static Future<void> maybePrompt(
      BuildContext context, {
        required DrivingRecoveryMode mode,
      }) async {
    if (_promptedInThisSession) return;

    final userState = context.read<UserState>();
    if (!userState.isLoggedIn) return;

    final userName = (userState.name).trim();
    if (userName.isEmpty) return;

    // 동일 세션 중복 방지
    _promptedInThisSession = true;

    final plates = await _fetchMyDrivingPlates(userName: userName);

    if (!context.mounted) return;
    if (plates.isEmpty) return;

    // ✅ 정중앙 Dialog로 표시
    final rootCtx = Navigator.of(context, rootNavigator: true).context;

    await showDialog<void>(
      context: rootCtx,
      useRootNavigator: true,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.55),
      builder: (_) => _DrivingRecoveryDialog(
        mode: mode,
        userName: userName,
        initialPlates: plates,
      ),
    );
  }

  static Future<List<PlateModel>> _fetchMyDrivingPlates({
    required String userName,
  }) async {
    final fs = FirebaseFirestore.instance;

    // 1) whereIn(type)까지 포함한 쿼리(인덱스/환경에 따라 실패할 수 있어 try)
    try {
      final snap = await fs
          .collection('plates')
          .where('isSelected', isEqualTo: true)
          .where('selectedBy', isEqualTo: userName)
          .where('type', whereIn: _targetTypes)
          .get();

      final out = snap.docs.map((d) => PlateModel.fromDocument(d)).toList();
      _sortByUpdatedAtDesc(out);
      return out;
    } catch (_) {
      // fallback 2) type 조건 제거 후 클라이언트 필터
    }

    try {
      final snap = await fs
          .collection('plates')
          .where('isSelected', isEqualTo: true)
          .where('selectedBy', isEqualTo: userName)
          .get();

      final out = snap.docs.map((d) => PlateModel.fromDocument(d)).toList();
      out.removeWhere((p) => !_targetTypes.contains(p.type));
      _sortByUpdatedAtDesc(out);
      return out;
    } catch (_) {
      return <PlateModel>[];
    }
  }

  static void _sortByUpdatedAtDesc(List<PlateModel> list) {
    list.sort((a, b) {
      final at = a.updatedAt ?? a.requestTime;
      final bt = b.updatedAt ?? b.requestTime;
      return bt.compareTo(at);
    });
  }
}

class _DrivingRecoveryDialog extends StatefulWidget {
  const _DrivingRecoveryDialog({
    required this.mode,
    required this.userName,
    required this.initialPlates,
  });

  final DrivingRecoveryMode mode;
  final String userName;
  final List<PlateModel> initialPlates;

  @override
  State<_DrivingRecoveryDialog> createState() => _DrivingRecoveryDialogState();
}

class _DrivingRecoveryDialogState extends State<_DrivingRecoveryDialog> {
  late List<PlateModel> _plates;
  bool _busyAll = false;

  @override
  void initState() {
    super.initState();
    _plates = List<PlateModel>.of(widget.initialPlates);
  }

  PlateType? _typeEnumOf(PlateModel p) => p.typeEnum;

  String _kindLabel(PlateModel p) {
    final t = _typeEnumOf(p);
    if (t == PlateType.parkingRequests) return '입차';
    if (t == PlateType.departureRequests) return '출차';
    return '주행';
  }

  String _safeLocation(String raw) {
    final t = raw.trim();
    return t.isEmpty ? '미지정' : t;
  }

  String _fmtWhen(DateTime? dt) {
    if (dt == null) return '—';
    final l = dt.toLocal();
    final y = l.year.toString().padLeft(4, '0');
    final m = l.month.toString().padLeft(2, '0');
    final d = l.day.toString().padLeft(2, '0');
    final hh = l.hour.toString().padLeft(2, '0');
    final mm = l.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  Future<PlateModel?> _fetchPlateById(String id) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('plates').doc(id).get();
      if (!doc.exists) return null;
      return PlateModel.fromDocument(doc);
    } catch (_) {
      return null;
    }
  }

  bool _isStillMyDriving(PlateModel p) {
    final selectedBy = (p.selectedBy ?? '').trim();
    final t = _typeEnumOf(p);
    return p.isSelected == true &&
        selectedBy.isNotEmpty &&
        selectedBy == widget.userName &&
        (t == PlateType.parkingRequests || t == PlateType.departureRequests);
  }

  void _removeById(String id) {
    setState(() => _plates.removeWhere((p) => p.id == id));
  }

  Future<void> _updateLocalState(PlateModel updatedPlate) async {
    final t = updatedPlate.typeEnum;
    if (t == null) return;

    try {
      if (widget.mode == DrivingRecoveryMode.minor) {
        final s = context.read<MinorPlateState>();
        await s.minorUpdatePlateLocally(t, updatedPlate);
      } else {
        final s = context.read<TriplePlateState>();
        await s.tripleUpdatePlateLocally(t, updatedPlate);
      }
    } catch (_) {
      // provider 미존재/예외는 무시(복구 흐름 자체가 더 중요)
    }
  }

  Future<void> _appendCancelLog({
    required String plateId,
    required String phase,
    required String userName,
  }) async {
    final fs = FirebaseFirestore.instance;
    final now = DateTime.now();

    final log = <String, dynamic>{
      'action': '주행 취소',
      'performedBy': userName,
      'timestamp': now.toIso8601String(),
      'phase': phase,
    };

    try {
      await fs.collection('plates').doc(plateId).update({
        'logs': FieldValue.arrayUnion([log]),
      });
    } catch (_) {}
  }

  Future<void> _unlockOne(PlateModel p) async {
    final repo = context.read<PlateRepository>();

    await repo.recordWhoPlateClick(
      p.id,
      false,
      area: p.area,
    );

    await _appendCancelLog(
      plateId: p.id,
      phase: _kindLabel(p),
      userName: widget.userName,
    );

    final updated = p.copyWith(isSelected: false, selectedBy: null);
    await _updateLocalState(updated);

    if (!mounted) return;

    try {
      showSuccessSnackbar(context, '잠금이 해제되었습니다. (${p.plateNumber})');
    } catch (_) {}

    _removeById(p.id);
    if (_plates.isEmpty && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  Future<void> _unlockAll() async {
    if (_busyAll) return;
    setState(() => _busyAll = true);

    try {
      final snapshot = List<PlateModel>.of(_plates);
      for (final p in snapshot) {
        if (!mounted) return;
        await _unlockOne(p);
      }
    } finally {
      if (mounted) setState(() => _busyAll = false);
    }
  }

  Future<void> _openStatusSheet(PlateModel p) async {
    final rootCtx = Navigator.of(context, rootNavigator: true).context;

    if (widget.mode == DrivingRecoveryMode.minor) {
      await showMinorParkingCompletedStatusBottomSheetFromDialog(
        context: rootCtx,
        plate: p,
      );
    } else {
      await showTripleParkingCompletedStatusBottomSheetFromDialog(
        context: rootCtx,
        plate: p,
      );
    }

    // 상태 시트에서 완료/취소가 수행되었는지 확인 → 목록 동기화
    final latest = await _fetchPlateById(p.id);
    if (!mounted) return;

    if (latest == null || !_isStillMyDriving(latest)) {
      _removeById(p.id);
      if (_plates.isEmpty && mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      return;
    }

    setState(() {
      final idx = _plates.indexWhere((x) => x.id == p.id);
      if (idx != -1) _plates[idx] = latest;
    });
  }

  @override
  Widget build(BuildContext context) {
    // 중앙 다이얼로그 크기: 모바일 기준 적당한 maxHeight 설정
    final media = MediaQuery.of(context);
    final maxH = (media.size.height * 0.82).clamp(420.0, 720.0);
    final maxW = (media.size.width * 0.92).clamp(320.0, 520.0);

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxW, maxHeight: maxH),
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.black12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 30,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 10, 10),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: Colors.orange.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.orange.withOpacity(0.30)),
                      ),
                      child: Icon(
                        Icons.warning_amber_rounded,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        '주행 중 상태 복구',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context, rootNavigator: true).pop(),
                      icon: const Icon(Icons.close),
                      splashRadius: 18,
                      tooltip: '닫기',
                    ),
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '사용자(${widget.userName})의 “주행 중(선점)” 상태가 남아있습니다.\n'
                        '각 항목에서 상태 화면을 열어 계속 진행하거나, 잠금을 해제(주행 취소)할 수 있습니다.',
                    style: const TextStyle(fontSize: 12, color: Colors.black54, height: 1.25),
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _busyAll ? null : _unlockAll,
                    icon: const Icon(Icons.lock_open),
                    label: Text(_busyAll ? '처리 중...' : '전체 잠금 해제'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 44),
                      side: const BorderSide(color: Colors.black12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      foregroundColor: Colors.black87,
                      backgroundColor: Colors.grey.shade50,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ),
                ),
              ),

              const Divider(height: 1),

              // List
              Expanded(
                child: _plates.isEmpty
                    ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(18),
                    child: Text(
                      '남아있는 주행 중 항목이 없습니다.',
                      style: TextStyle(color: Colors.black54, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
                    : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                  itemCount: _plates.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = _plates[i];
                    final label = _kindLabel(p);

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.black12),
                        color: Colors.grey.shade50,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.orange.withOpacity(0.10),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(color: Colors.orange.withOpacity(0.30)),
                                ),
                                child: Text(
                                  '$label 주행 중',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.deepOrange,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  p.plateNumber,
                                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _kv('지역', p.area),
                          const SizedBox(height: 6),
                          _kv('위치', _safeLocation(p.location)),
                          const SizedBox(height: 6),
                          _kv('마지막 갱신', _fmtWhen(p.updatedAt ?? p.requestTime)),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => _openStatusSheet(p),
                                  icon: const Icon(Icons.open_in_new),
                                  label: const Text('상태 열기'),
                                  style: FilledButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 44),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => _unlockOne(p),
                                  icon: const Icon(Icons.lock_open),
                                  label: const Text('잠금 해제'),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(double.infinity, 44),
                                    side: const BorderSide(color: Colors.black12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    foregroundColor: Colors.black87,
                                    backgroundColor: Colors.white,
                                    textStyle: const TextStyle(fontWeight: FontWeight.w900),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Row(
      children: [
        SizedBox(
          width: 86,
          child: Text(
            k,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black54,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Expanded(
          child: Text(
            v.trim().isEmpty ? '—' : v.trim(),
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w800,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
