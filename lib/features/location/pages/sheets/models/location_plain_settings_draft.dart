class LocationPlainSettingsDraft {
  const LocationPlainSettingsDraft({
    required this.name,
    required this.capacity,
  });

  final String name;
  final int capacity;

  LocationPlainSettingsDraft copyWith({
    String? name,
    int? capacity,
  }) {
    return LocationPlainSettingsDraft(
      name: name ?? this.name,
      capacity: capacity ?? this.capacity,
    );
  }

  LocationPlainSettingsDraft detached() {
    return LocationPlainSettingsDraft(
      name: name,
      capacity: capacity,
    );
  }
}
