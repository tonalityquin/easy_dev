import 'package:flutter/foundation.dart';

@immutable
class ViewRowData {
  final String plateId;
  final String plateNumber;
  final String location;
  final DateTime? primaryAt;
  final DateTime? updatedAt;
  final DateTime? createdAt;
  final bool isSelected;
  final String? selectedBy;

  const ViewRowData({
    required this.plateId,
    required this.plateNumber,
    required this.location,
    required this.primaryAt,
    required this.updatedAt,
    required this.createdAt,
    this.isSelected = false,
    this.selectedBy,
  });
}

class ViewDocRowsStore extends ChangeNotifier {
  final Map<String, List<ViewRowData>> _rowsByKey = <String, List<ViewRowData>>{};
  final Map<String, int> _revByKey = <String, int>{};
  String _companyScope = '';

  void switchCompanyScope(String companyId) {
    final next = companyId.trim();
    if (_companyScope == next) return;
    _companyScope = next;
    _rowsByKey.clear();
    _revByKey.clear();
    debugPrint('[ViewDocRowsStore] company_scope_changed company=$next');
    notifyListeners();
  }

  String _k(String collection, String area) => '${collection.trim()}|${area.trim()}';

  int revision({required String collection, required String area}) {
    return _revByKey[_k(collection, area)] ?? 0;
  }

  List<ViewRowData> rows({required String collection, required String area}) {
    final v = _rowsByKey[_k(collection, area)];
    if (v == null) return const <ViewRowData>[];
    return v;
  }

  void setRows({
    required String collection,
    required String area,
    required String companyId,
    required List<ViewRowData> rows,
    String? source,
  }) {
    final c = collection.trim();
    final a = area.trim();
    final company = companyId.trim();
    if (c.isEmpty || a.isEmpty || company.isEmpty) return;
    if (_companyScope != company) {
      debugPrint('[ViewDocRowsStore] stale_company_rows_ignored company=$company active=$_companyScope');
      return;
    }
    final key = _k(c, a);
    _rowsByKey[key] = List<ViewRowData>.unmodifiable(rows);
    _revByKey[key] = (_revByKey[key] ?? 0) + 1;
    debugPrint('[ViewDocRowsStore] setRows $c/$a rows=${rows.length} rev=${_revByKey[key]} source=${source ?? ''}');
    notifyListeners();
  }
}
