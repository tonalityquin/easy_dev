
import '../../../../../app/models/capability.dart';

class AreaRecord {
  final String name;
  final String division;
  final CapSet capabilities;
  final List<String> modes;
  final bool isHeadquarter;

  const AreaRecord({
    required this.name,
    required this.division,
    required this.capabilities,
    this.modes = const <String>[],
    this.isHeadquarter = false,
  });
}

abstract interface class AreaRepository {
  Future<bool> isHeadquarter({
    required String division,
    required String area,
  });

  Future<AreaRecord?> getAreaByName(String areaName);

  Future<List<AreaRecord>> getAreasByDivision(String division);

  Future<List<String>> getAreaNamesByDivision(String division);
}
