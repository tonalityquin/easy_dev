class PlateStatusSearchResult {
  final String docId;
  final String path;
  final Map<String, dynamic> data;

  const PlateStatusSearchResult({
    required this.docId,
    required this.path,
    required this.data,
  });

  String? stringValue(String key) {
    final value = data[key];
    if (value == null) return null;
    final text = value.toString().trim();
    return text.isEmpty ? null : text;
  }

  List<MapEntry<String, dynamic>> orderedEntries() {
    final priority = <String>[
      'plateNumber',
      'plateDocId',
      'platesDocId',
      'plateKey',
      'plate_four_digit',
      'area',
      'monthKey',
      'customStatus',
      'statusList',
      'createdBy',
      'createdAt',
      'updatedAt',
      'expireAt',
      'source',
      'statusScope',
    ];

    final entries = <MapEntry<String, dynamic>>[];
    final used = <String>{};

    for (final key in priority) {
      if (data.containsKey(key)) {
        entries.add(MapEntry<String, dynamic>(key, data[key]));
        used.add(key);
      }
    }

    final rest = data.entries.where((e) => !used.contains(e.key)).toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    entries.addAll(rest);
    return entries;
  }
}
