import 'package:flutter/material.dart';
import '../../domain/enums/plate_type.dart';
import '../../domain/models/plate_model.dart';
import '../triple/triple_plate_state.dart';
class MinorFilterPlate extends ChangeNotifier {
  final TriplePlateState _plateState;

  String? _searchQuery;
  String? _locationQuery;

  MinorFilterPlate(this._plateState);

  String get searchQuery => _searchQuery ?? "";

  String get locationQuery => _locationQuery ?? "";

  List<PlateModel> getPlates(PlateType type) {
    return _plateState.dataOfType(type);
  }
}
