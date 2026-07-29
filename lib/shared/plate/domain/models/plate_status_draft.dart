class PlateStatusDraft {
  PlateStatusDraft({required String customStatus})
      : customStatus = customStatus.trim();

  final String customStatus;

  factory PlateStatusDraft.fromMap(Map<String, dynamic>? data) {
    return PlateStatusDraft(
      customStatus: data?['customStatus']?.toString() ?? '',
    );
  }

  bool get isEmpty => customStatus.isEmpty;

  bool sameAs(PlateStatusDraft other) => customStatus == other.customStatus;
}
