import 'package:flutter/material.dart';
import '../../enums/plate_type.dart';
import '../../models/plate_model.dart';
import 'triple_plate_state.dart';

class TripleFilterPlate extends ChangeNotifier {
  final TriplePlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

  TripleFilterPlate(this._plateState);

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
