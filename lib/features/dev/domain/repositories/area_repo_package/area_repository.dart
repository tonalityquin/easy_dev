import '../../../../../app/models/capability.dart';

class AreaRecord {
  final String name;
  final String division;
  final String email;
  final String invite;
  final String communication;
  final CapSet capabilities;
  final List<String> modes;
  final bool isHeadquarter;

  const AreaRecord({
    required this.name,
    required this.division,
    required this.email,
    this.invite = '',
    this.communication = '',
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

  Future<AreaRecord?> getAreaByName(
    String areaName, {
    String? division,
  });

  Future<List<AreaRecord>> getAreasByDivision(String division);

  Future<List<String>> getAreaNamesByDivision(String division);
}
