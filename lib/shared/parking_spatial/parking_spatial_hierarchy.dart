import '../../features/location/domain/models/location_model.dart';

class ParkingSpatialHierarchyGroup {
  const ParkingSpatialHierarchyGroup({
    required this.parentName,
    required this.parentSource,
    required this.children,
  });

  final String parentName;
  final LocationModel? parentSource;
  final List<LocationModel> children;
}

int _naturalCompareToken(String a, String b) {
  final ai = int.tryParse(a);
  final bi = int.tryParse(b);
  if (ai != null && bi != null) {
    final comparison = ai.compareTo(bi);
    if (comparison != 0) return comparison;
    return a.length.compareTo(b.length);
  }
  final lowerA = a.toLowerCase();
  final lowerB = b.toLowerCase();
  final insensitive = lowerA.compareTo(lowerB);
  if (insensitive != 0) return insensitive;
  return a.compareTo(b);
}

List<String> _naturalTokens(String value) {
  final output = <String>[];
  final buffer = StringBuffer();
  bool? numeric;
  for (var index = 0; index < value.length; index++) {
    final character = value[index];
    final digit = RegExp(r'\d').hasMatch(character);
    if (numeric == null || numeric == digit) {
      buffer.write(character);
      numeric = digit;
      continue;
    }
    output.add(buffer.toString());
    buffer
      ..clear()
      ..write(character);
    numeric = digit;
  }
  if (buffer.isNotEmpty) output.add(buffer.toString());
  return output;
}

int parkingSpatialNaturalCompare(String a, String b) {
  final tokensA = _naturalTokens(a.trim());
  final tokensB = _naturalTokens(b.trim());
  final length = tokensA.length < tokensB.length
      ? tokensA.length
      : tokensB.length;
  for (var index = 0; index < length; index++) {
    final comparison = _naturalCompareToken(tokensA[index], tokensB[index]);
    if (comparison != 0) return comparison;
  }
  return tokensA.length.compareTo(tokensB.length);
}


int parkingSpatialCapacityForChild(LocationModel location) {
  if (location.childSlots.isNotEmpty) return location.childSlots.length;
  return location.capacity;
}

List<ParkingSpatialHierarchyGroup> resolveParkingSpatialHierarchy(
  List<LocationModel> locations, {
  Comparator<String>? parentComparator,
}) {
  final childrenByParent = <String, List<LocationModel>>{};
  final parentByReference = <String, LocationModel>{};
  final parentNames = <String>{};

  for (final location in locations) {
    if (location.isCompositeParent) {
      final name = location.locationName.trim();
      final id = location.id.trim();
      if (name.isNotEmpty) {
        parentNames.add(name);
        parentByReference[name] = location;
      }
      if (id.isNotEmpty) {
        parentByReference[id] = location;
      }
      continue;
    }
    if (!location.isCompositeChild) continue;
    final parent = (location.parent ?? '').trim();
    final child = location.locationName.trim();
    if (parent.isEmpty || child.isEmpty) continue;
    parentNames.add(parent);
    childrenByParent.putIfAbsent(parent, () => <LocationModel>[]).add(location);
  }

  final compareParent = parentComparator ?? parkingSpatialNaturalCompare;
  final orderedParents = parentNames.toList()..sort(compareParent);
  return <ParkingSpatialHierarchyGroup>[
    for (final parentName in orderedParents)
      ParkingSpatialHierarchyGroup(
        parentName: parentName,
        parentSource: parentByReference[parentName],
        children: List<LocationModel>.unmodifiable(
          List<LocationModel>.of(
            childrenByParent[parentName] ?? const <LocationModel>[],
          )..sort(
              (a, b) => parkingSpatialNaturalCompare(
                a.locationName,
                b.locationName,
              ),
            ),
        ),
      ),
  ];
}
