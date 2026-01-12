import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'plate_state.dart';

class FilterPlate extends ChangeNotifier {
  final PlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

 FilterPlate(this._plateState);

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";
  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
