import '../../../../features/location/domain/models/location_model.dart';

String plateParkingOverviewLocation(
  String raw, {
  Iterable<LocationModel> locations = const <LocationModel>[],
}) {
  final value = raw.trim();
  if (value.isEmpty) return '';
  final segments = _parkingLocationSegments(value);
  if (segments.length < 3) return value;
  if (plateParkingLocationIsTower(value, locations: locations)) {
    return '${segments[0]} - ${segments[1]}';
  }
  final slotMatch = RegExp(r'(\d+)').firstMatch(segments[2]);
  if (slotMatch == null) {
    final slotSegment = segments[2].split('·').first.trim();
    return '${segments[0]} - ${segments[1]} - $slotSegment';
  }
  return '${segments[0]} - ${segments[1]} - 슬롯 ${slotMatch.group(1)}';
}

bool plateParkingLocationIsTower(
  String raw, {
  required Iterable<LocationModel> locations,
}) {
  final segments = _parkingLocationSegments(raw.trim());
  if (segments.length < 2) return false;
  final parentName = _parkingLocationKey(segments[0]);
  final childName = _parkingLocationKey(segments[1]);
  if (parentName.isEmpty || childName.isEmpty) return false;
  final snapshot = locations.toList(growable: false);
  final parentKeys = <String>{parentName};
  for (final location in snapshot) {
    if (location.isCompositeChild) continue;
    if (_parkingLocationKey(location.locationName) != parentName) continue;
    final id = _parkingLocationKey(location.id);
    final name = _parkingLocationKey(location.locationName);
    if (id.isNotEmpty) parentKeys.add(id);
    if (name.isNotEmpty) parentKeys.add(name);
  }
  for (final location in snapshot) {
    if (!location.isCompositeChild || !location.isTowerChild) continue;
    if (_parkingLocationKey(location.locationName) != childName) continue;
    final parent = _parkingLocationKey(location.parent ?? '');
    final parentId = _parkingLocationKey(location.parentId ?? '');
    if (parentKeys.contains(parent) || parentKeys.contains(parentId)) {
      return true;
    }
  }
  return false;
}

List<String> _parkingLocationSegments(String raw) {
  if (raw.isEmpty) return const <String>[];
  return raw
      .split(' - ')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
}

String _parkingLocationKey(String raw) => raw.trim().toLowerCase();
