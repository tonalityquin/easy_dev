import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'normal_plate_state.dart';

class NormalFilterPlate extends ChangeNotifier {
  final NormalPlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

  NormalFilterPlate(this._plateState);

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
