import '../../../../app/models/capability.dart';

enum PlateEditorWorkspace {
  overview,
  vehicleIdentity,
  parking,
  camera,
  sector,
  variableBilling,
  regularBilling,
  memo,
}

class PlateEditorPolicy {
  const PlateEditorPolicy({
    required this.area,
    required this.hasBill,
    required this.hasSector,
  });

  final String area;
  final bool hasBill;
  final bool hasSector;

  factory PlateEditorPolicy.fromCapabilities({
    required String area,
    required CapSet capabilities,
  }) {
    return PlateEditorPolicy(
      area: area.trim(),
      hasBill: capabilities.contains(Capability.bill),
      hasSector: capabilities.contains(Capability.sector),
    );
  }

  List<PlateEditorWorkspace> get railWorkspaces => <PlateEditorWorkspace>[
        PlateEditorWorkspace.parking,
        PlateEditorWorkspace.camera,
        if (hasSector) PlateEditorWorkspace.sector,
        if (hasBill) PlateEditorWorkspace.variableBilling,
        if (hasBill) PlateEditorWorkspace.regularBilling,
        PlateEditorWorkspace.memo,
      ];

  PlateEditorWorkspace get defaultWorkspace => PlateEditorWorkspace.overview;

  bool supports(PlateEditorWorkspace workspace) {
    switch (workspace) {
      case PlateEditorWorkspace.sector:
        return hasSector;
      case PlateEditorWorkspace.variableBilling:
      case PlateEditorWorkspace.regularBilling:
        return hasBill;
      case PlateEditorWorkspace.overview:
      case PlateEditorWorkspace.vehicleIdentity:
      case PlateEditorWorkspace.parking:
      case PlateEditorWorkspace.camera:
      case PlateEditorWorkspace.memo:
        return true;
    }
  }

  PlateEditorWorkspace fallbackFor(PlateEditorWorkspace workspace) {
    if (supports(workspace)) return workspace;
    return PlateEditorWorkspace.overview;
  }

  String get signature => '$area|bill=$hasBill|sector=$hasSector';
}
