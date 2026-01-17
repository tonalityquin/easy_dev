import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'double_plate_state.dart';

class DoubleFilterPlate extends ChangeNotifier {
  final DoublePlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

  DoubleFilterPlate(this._plateState);

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
