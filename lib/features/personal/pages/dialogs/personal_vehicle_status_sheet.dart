import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/utils/dev_firebase_debug_dialog.dart';
import '../../../../shared/plate/application/common/movement_plate.dart';
import '../../../../shared/plate/domain/enums/plate_type.dart';
import '../../../../shared/plate/domain/models/plate_model.dart';
import '../../application/personal_saved_vehicle_store.dart';
import '../../application/personal_vehicle_status_service.dart';
import '../../domain/models/personal_saved_vehicle.dart';
import '../widgets/personal_vehicle_timeline.dart';
import 'personal_departure_success_dialog.dart';

Future<bool?> showPersonalVehicleStatusSheet({
  required BuildContext context,
  required PersonalSavedVehicle vehicle,
  required String area,
  PlateModel? initialPlate,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PersonalVehicleStatusSheet(
      vehicle: vehicle,
      area: area,
      initialPlate: initialPlate,
    ),
  );
}

class PersonalVehicleStatusSheet extends StatefulWidget {
  const PersonalVehicleStatusSheet({
    super.key,
    required this.vehicle,
    required this.area,
    this.initialPlate,
  });

  final PersonalSavedVehicle vehicle;
  final String area;
  final PlateModel? initialPlate;

  @override
  State<PersonalVehicleStatusSheet> createState() => _PersonalVehicleStatusSheetState();
}

class _PersonalVehicleStatusSheetState extends State<PersonalVehicleStatusSheet> {
  final PersonalVehicleStatusService _service = PersonalVehicleStatusService();
  final PersonalSavedVehicleStore _store = PersonalSavedVehicleStore();
  PlateModel? _plate;
  bool _loading = false;
  bool _requesting = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _plate = widget.initialPlate;
    _refresh();
  }

  Future<void> _refresh() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final plate = await _service.fetchCurrentVehiclePlate(
        plateNumber: widget.vehicle.plateNumber,
        area: widget.area,
      );
      if (!mounted) return;
      setState(() {
        _plate = plate;
        _loading = false;
      });
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal.vehicleStatusSheet.refresh',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'area': widget.area,
          'vehicleId': widget.vehicle.id,
          'plateNumberInput': widget.vehicle.plateNumber,
          'source': 'PersonalVehicleStatusService.fetchCurrentVehiclePlate',
        },
      );
      if (!mounted) return;
      setState(() {
        _error = '차량 상태를 불러오지 못했습니다.';
        _loading = false;
      });
    }
  }

  Future<void> _requestDeparture() async {
    final plate = _plate;
    if (plate == null || _requesting) return;
    if (plate.typeEnum != PlateType.parkingCompleted) return;

    setState(() => _requesting = true);
    try {
      await context.read<MovementPlate>().setDepartureRequested(
            plate.plateNumber,
            plate.area,
            plate.location,
            forceViewSync: true,
          );
      await _store.markUsed(widget.vehicle.id);
      if (!mounted) return;
      await showPersonalDepartureRequestedSuccessDialog(context, plate);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e, st) {
      await DevFirebaseDebugDialog.show(
        context: context,
        operation: 'personal.departureRequest.submit',
        error: e,
        stackTrace: st,
        details: <String, Object?>{
          'collection': 'plates',
          'plateNumber': plate.plateNumber,
          'area': plate.area,
          'location': plate.location,
          'currentType': plate.type,
          'expectedFromType': PlateType.parkingCompleted.firestoreValue,
          'targetType': PlateType.departureRequests.firestoreValue,
          'forceViewSync': true,
          'writePath': 'MovementPlate.setDepartureRequested',
          'viewWrites': 'parking_completed_view remove, departure_requests_view upsert',
        },
      );
      if (!mounted) return;
      setState(() {
        _requesting = false;
        _error = '출차 요청 중 오류가 발생했습니다.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final maxHeight = mq.size.height * .90;
    final plate = _plate;
    final type = plate?.typeEnum;
    final canRequest = type == PlateType.parkingCompleted;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        boxShadow: [
          BoxShadow(
            color: cs.shadow.withOpacity(.18),
            blurRadius: 28,
            offset: const Offset(0, -12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 42,
            height: 5,
            decoration: BoxDecoration(
              color: cs.outlineVariant,
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          Flexible(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.vehicle.displayPlate,
                              style: text.headlineSmall?.copyWith(
                                color: cs.onSurface,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.6,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '${widget.vehicle.displayLabel} · ${widget.area.trim().isEmpty ? '지점 미확인' : widget.area.trim()}',
                              style: text.bodyMedium?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '닫기',
                        onPressed: _requesting ? null : () => Navigator.of(context).pop(false),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _StatusHero(plate: plate, loading: _loading, error: _error),
                  if (plate != null) ...[
                    const SizedBox(height: 14),
                    _InfoGrid(plate: plate),
                    const SizedBox(height: 14),
                    Container(
                      height: 260,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: PersonalDepartureRequestFocusedGrid(
                          area: plate.area,
                          details: parsePersonalParkingLocation(plate.location),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    PersonalVehicleTimeline(plate: plate),
                  ] else ...[
                    const SizedBox(height: 18),
                    _EmptyStatusCard(onRefresh: _refresh),
                  ],
                ],
              ),
            ),
          ),
          Container(
            padding: EdgeInsets.fromLTRB(20, 12, 20, 12 + mq.padding.bottom),
            decoration: BoxDecoration(
              color: cs.surface,
              border: Border(top: BorderSide(color: cs.outlineVariant.withOpacity(.55))),
            ),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _requesting ? null : _refresh,
                    icon: _loading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.primary),
                          )
                        : const Icon(Icons.refresh_rounded),
                    label: const Text('상태 새로고침'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: canRequest && !_requesting ? _requestDeparture : null,
                    icon: _requesting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2, color: cs.onPrimary),
                          )
                        : const Icon(Icons.near_me_rounded),
                    label: Text(_requesting ? '요청 중...' : '출차 요청하기'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: cs.primary,
                      foregroundColor: cs.onPrimary,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusHero extends StatelessWidget {
  const _StatusHero({required this.plate, required this.loading, required this.error});

  final PlateModel? plate;
  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final type = plate?.typeEnum;
    final label = loading
        ? '상태 확인 중'
        : error != null
            ? '확인 실패'
            : _statusLabel(type);
    final message = loading
        ? '차량의 현재 주차 정보를 불러오고 있습니다.'
        : error != null
            ? error!
            : plate == null
                ? '현재 지점에서 주차 중인 차량 정보를 찾지 못했습니다.'
                : '${plate!.location.isEmpty ? '위치 미지정' : plate!.location} · ${_formatDateTime(plate!.requestTime)}';
    final colors = _statusColors(cs, type, loading: loading, error: error != null);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.$2,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: colors.$1.withOpacity(.12),
              borderRadius: BorderRadius.circular(17),
            ),
            child: Icon(_statusIcon(type, loading: loading, error: error != null), color: colors.$1),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: text.titleMedium?.copyWith(
                    color: colors.$1,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: text.bodySmall?.copyWith(
                    color: colors.$1.withOpacity(.78),
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoGrid extends StatelessWidget {
  const _InfoGrid({required this.plate});

  final PlateModel plate;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        _InfoTile(label: '현재 상태', value: plate.typeEnum?.label ?? plate.type),
        _InfoTile(label: '이용 지점', value: plate.area),
        _InfoTile(label: '주차 위치', value: plate.location),
        _InfoTile(label: '최근 시각', value: _formatDateTime(plate.updatedAt ?? plate.requestTime)),
      ],
    );
  }
}

class _InfoTile extends StatelessWidget {
  const _InfoTile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withOpacity(.45)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w800)),
          const SizedBox(height: 5),
          Text(value.trim().isEmpty ? '-' : value, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}

class _EmptyStatusCard extends StatelessWidget {
  const _EmptyStatusCard({required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: cs.outlineVariant.withOpacity(.55)),
      ),
      child: Column(
        children: [
          Icon(Icons.garage_outlined, color: cs.primary, size: 34),
          const SizedBox(height: 10),
          Text(
            '현재 주차 중 정보가 없습니다.',
            style: text.titleMedium?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            '번호판과 이용 지점이 맞는지 확인하거나 잠시 후 다시 새로고침해 주세요.',
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, fontWeight: FontWeight.w700, height: 1.35),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRefresh,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('다시 확인'),
          ),
        ],
      ),
    );
  }
}

String _statusLabel(PlateType? type) {
  switch (type) {
    case PlateType.parkingCompleted:
      return '주차 중';
    case PlateType.departureRequests:
      return '출차 요청됨';
    case PlateType.departureCompleted:
      return '출차 완료';
    case PlateType.parkingRequests:
      return '입차 진행 중';
    case null:
      return '정보 없음';
  }
}

IconData _statusIcon(PlateType? type, {required bool loading, required bool error}) {
  if (loading) return Icons.sync_rounded;
  if (error) return Icons.error_outline_rounded;
  switch (type) {
    case PlateType.parkingCompleted:
      return Icons.local_parking_rounded;
    case PlateType.departureRequests:
      return Icons.schedule_send_rounded;
    case PlateType.departureCompleted:
      return Icons.check_circle_rounded;
    case PlateType.parkingRequests:
      return Icons.login_rounded;
    case null:
      return Icons.help_outline_rounded;
  }
}

(Color, Color) _statusColors(ColorScheme cs, PlateType? type, {required bool loading, required bool error}) {
  if (error) return (cs.onErrorContainer, cs.errorContainer);
  if (loading) return (cs.onSecondaryContainer, cs.secondaryContainer);
  switch (type) {
    case PlateType.parkingCompleted:
      return (cs.onPrimaryContainer, cs.primaryContainer);
    case PlateType.departureRequests:
      return (cs.onTertiaryContainer, cs.tertiaryContainer);
    case PlateType.departureCompleted:
      return (cs.onSurfaceVariant, cs.surfaceContainerHigh);
    case PlateType.parkingRequests:
      return (cs.onSecondaryContainer, cs.secondaryContainer);
    case null:
      return (cs.onSurfaceVariant, cs.surfaceContainerHighest);
  }
}

String _formatDateTime(DateTime dt) {
  String two(int n) => n.toString().padLeft(2, '0');
  final d = dt.toLocal();
  return '${two(d.month)}/${two(d.day)} ${two(d.hour)}:${two(d.minute)}';
}
