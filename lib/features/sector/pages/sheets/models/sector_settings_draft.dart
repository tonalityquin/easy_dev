class SectorSettingsDraft {
  const SectorSettingsDraft({required this.name});

  final String name;

  SectorSettingsDraft copyWith({String? name}) {
    return SectorSettingsDraft(name: name ?? this.name);
  }

  SectorSettingsDraft detached() {
    return SectorSettingsDraft(name: name);
  }
}
