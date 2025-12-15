import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'lite_plate_state.dart';

class LiteFilterPlate extends ChangeNotifier {
  final LitePlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

  LiteFilterPlate(this._plateState);

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  void clearLocationSearchQuery() {
    _locationQuery = null;
    notifyListeners();
  }
  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
