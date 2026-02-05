import 'package:flutter/foundation.dart';

@immutable
sealed class LocationDraft {
  const LocationDraft();
}

@immutable
final class SingleLocationDraft extends LocationDraft {
  final String name;
  final int capacity;

  const SingleLocationDraft({
    required this.name,
    required this.capacity,
  });
}

@immutable
final class CompositeSubDraft {
  final String name;
  final int capacity;

  const CompositeSubDraft({
    required this.name,
    required this.capacity,
  });
}

@immutable
final class CompositeLocationDraft extends LocationDraft {
  final String parent;
  final List<CompositeSubDraft> subs;

  const CompositeLocationDraft({
    required this.parent,
    required this.subs,
  });

  int get totalCapacity => subs.fold<int>(0, (sum, s) => sum + s.capacity);
}
