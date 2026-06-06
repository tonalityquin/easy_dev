import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../location/applications/location_state.dart';
import '../../../location/domain/models/location_model.dart';
import '../../../tablet/domain/models/two_d/tablet_grid_2d_preview.dart'
    show
        ParkingGridOverlay,
        ParkingSlotStatus,
        TabletGrid2dPreview,
        parkingOverlayCanonicalChildKey;
import '../../../../shared/plate/domain/models/plate_model.dart';

@immutable
class PersonalParkingLocationDetails {
  final String full;
  final String parent;
  final String child;
  final String slot;

  const PersonalParkingLocationDetails({
    required this.full,
    required this.parent,
    required this.child,
    required this.slot,
  });

  const PersonalParkingLocationDetails.empty()
      : full = '미지정',
        parent = '',
        child = '',
        slot = '';

  String get fullDisplay => full.trim().isEmpty ? '미지정' : full.trim();
}

Future<void> showPersonalDepartureRequestedSuccessDialog(
  BuildContext context,
  PlateModel plate,
) async {
  final details = parsePersonalParkingLocation(plate.location);

  await showDialog<void>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    builder: (_) {
      return PersonalDepartureRequestSuccessDialog(
        plate: plate,
        details: details,
      );
    },
  );
}

PersonalParkingLocationDetails parsePersonalParkingLocation(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty || trimmed == '미지정') {
    return const PersonalParkingLocationDetails.empty();
  }

  final segments = splitPersonalLocationSegments(trimmed);
  if (segments.isEmpty) {
    return PersonalParkingLocationDetails(
      full: trimmed,
      parent: trimmed,
      child: '',
      slot: '',
    );
  }

  final parent = segments[0];
  final child = segments.length >= 2 ? segments[1] : '';
  final slot = segments.length >= 3 ? segments.sublist(2).join(' - ') : '';
  final full = <String>[parent, child, slot]
      .where((e) => e.trim().isNotEmpty)
      .join(' - ');

  return PersonalParkingLocationDetails(
    full: full.isEmpty ? trimmed : full,
    parent: parent,
    child: child,
    slot: slot,
  );
}

List<String> splitPersonalLocationSegments(String raw) {
  final value = raw.trim();
  if (value.isEmpty) return const <String>[];
  return value
      .split(' - ')
      .map((e) => e.trim())
      .where((e) => e.isNotEmpty)
      .toList(growable: false);
}

class PersonalDepartureRequestSuccessDialog extends StatefulWidget {
  final PlateModel plate;
  final PersonalParkingLocationDetails details;

  const PersonalDepartureRequestSuccessDialog({
    super.key,
    required this.plate,
    required this.details,
  });

  @override
  State<PersonalDepartureRequestSuccessDialog> createState() =>
      _PersonalDepartureRequestSuccessDialogState();
}

class _PersonalDepartureRequestSuccessDialogState
    extends State<PersonalDepartureRequestSuccessDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progressController;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _progressController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    )
      ..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          _closeDialog();
        }
      })
      ..forward();
  }

  @override
  void dispose() {
    _progressController.dispose();
    super.dispose();
  }

  void _closeDialog() {
    if (_closing || !mounted) return;
    _closing = true;
    Navigator.of(context, rootNavigator: true).pop();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final mq = MediaQuery.of(context);
    final isPhone = mq.size.shortestSide < 600;

    final dialogWidth =
        ((isPhone ? mq.size.width - 24 : 860.0).clamp(320.0, 860.0)).toDouble();
    final dialogHeight =
        ((isPhone ? mq.size.height * 0.66 : 640.0).clamp(420.0, 700.0))
            .toDouble();

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: isPhone ? 12 : 24,
        vertical: 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerLowest,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: cs.outline.withOpacity(.12)),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: PersonalDepartureRequestFocusedGrid(
                      area: widget.plate.area,
                      details: widget.details,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                '현재 고객님의 차량 위치를 표시해드립니다.\n차량은 사전에 안내받은 위치에 준비될 예정입니다.',
                textAlign: TextAlign.center,
                style: (text.titleMedium ?? const TextStyle()).copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.center,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 320),
                  child: AnimatedBuilder(
                    animation: _progressController,
                    builder: (context, _) {
                      return ClipRRect(
                        borderRadius: BorderRadius.circular(999),
                        child: LinearProgressIndicator(
                          minHeight: 8,
                          value: _progressController.value,
                          valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                          backgroundColor: cs.outlineVariant.withOpacity(.28),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Align(
                alignment: Alignment.center,
                child: FilledButton.icon(
                  onPressed: _closeDialog,
                  icon: const Icon(Icons.close),
                  label: const Text('닫기'),
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(140, 48),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                    textStyle: (text.titleMedium ?? const TextStyle()).copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class PersonalDepartureRequestFocusedGrid extends StatelessWidget {
  final String area;
  final PersonalParkingLocationDetails details;

  const PersonalDepartureRequestFocusedGrid({
    super.key,
    required this.area,
    required this.details,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (details.parent.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '위치 정보가 없어 2D 그리드를 표시할 수 없습니다.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                ),
          ),
        ),
      );
    }

    final liveLocations = List<LocationModel>.of(
      context.watch<LocationState>().locations,
    );

    final focusedLocations = _resolveFocusedLocations(liveLocations);
    if (focusedLocations.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            '주차 구역 2D 그리드를 불러오지 못했습니다.\n잠시 후 다시 시도해 주세요.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
          ),
        ),
      );
    }

    return ColoredBox(
      color: cs.surfaceContainerLowest,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: TabletGrid2dPreview(
          locations: focusedLocations,
          overlay: _buildOverlay(),
        ),
      ),
    );
  }

  List<LocationModel> _resolveFocusedLocations(List<LocationModel> all) {
    final resolvedArea = area.trim();
    final parentKey = _dialogNameKey(details.parent);
    if (parentKey.isEmpty) return const <LocationModel>[];

    LocationModel? parentLocation;
    for (final location in all) {
      if (!_matchesAreaLooseForDialog(resolvedArea, location.area)) continue;
      if (!_isCompositeParentTypeForDialog(location.type)) continue;
      if (_dialogNameKey(location.locationName) != parentKey) continue;
      parentLocation = location;
      break;
    }

    if (parentLocation == null) return const <LocationModel>[];

    final aliases = _parentAliasesForDialog(parentLocation);
    final children = <LocationModel>[];

    for (final location in all) {
      if (!_matchesAreaLooseForDialog(resolvedArea, location.area)) continue;
      if (!_isCompositeChildTypeForDialog(location.type)) continue;
      final parentRefKey = _dialogNameKey(location.parent ?? '');
      if (parentRefKey.isEmpty || !aliases.contains(parentRefKey)) continue;
      children.add(location);
    }

    children.sort((a, b) => a.locationName.compareTo(b.locationName));

    return <LocationModel>[parentLocation, ...children];
  }

  ParkingGridOverlay _buildOverlay() {
    final parentKey = _dialogNameKey(details.parent);
    final childKey = parkingOverlayCanonicalChildKey(details.child);
    if (parentKey.isEmpty || childKey.isEmpty) {
      return const ParkingGridOverlay.empty();
    }

    final slotNo = _dialogParseFirstInt(details.slot);
    if (slotNo != null) {
      return ParkingGridOverlay(
        slotStatusByKey: <String, ParkingSlotStatus>{
          '$parentKey|$childKey|$slotNo': ParkingSlotStatus.departureRequest,
        },
        groupStatusByKey: const <String, ParkingSlotStatus>{},
      );
    }

    return ParkingGridOverlay(
      slotStatusByKey: const <String, ParkingSlotStatus>{},
      groupStatusByKey: <String, ParkingSlotStatus>{
        '$parentKey|$childKey': ParkingSlotStatus.departureRequest,
      },
    );
  }
}

String _dialogNormalizeName(String raw) =>
    raw.trim().replaceAll(RegExp(r'\s+'), ' ');

String _dialogNameKey(String raw) => _dialogNormalizeName(raw).toLowerCase();

int? _dialogParseFirstInt(String raw) {
  final match = RegExp(r'(\d+)').firstMatch(raw);
  if (match == null) return null;
  return int.tryParse(match.group(1) ?? '');
}

bool _isCompositeParentTypeForDialog(String? type) {
  final value = (type ?? '').trim().toLowerCase();
  return value == 'composite_parent' ||
      value.replaceAll(RegExp(r'[_\-\s]'), '') == 'compositeparent';
}

bool _isCompositeChildTypeForDialog(String? type) {
  final value = (type ?? '').trim().toLowerCase();
  if (value == 'composite_child' || value == 'composite') return true;
  final packed = value.replaceAll(RegExp(r'[_\-\s]'), '');
  return packed == 'compositechild' || packed == 'composite';
}

bool _matchesAreaLooseForDialog(String parentArea, String childArea) {
  final pa = parentArea.trim();
  final ca = childArea.trim();
  if (pa.isEmpty) return true;
  if (ca.isEmpty) return true;
  return pa == ca;
}

Set<String> _parentAliasesForDialog(LocationModel parent) {
  final out = <String>{};

  void addValue(Object? value) {
    final key = _dialogNameKey((value ?? '').toString());
    if (key.isNotEmpty) out.add(key);
  }

  addValue(parent.id);
  addValue(parent.locationName);

  try {
    addValue((parent as dynamic).locationId);
  } catch (_) {}

  return out;
}
