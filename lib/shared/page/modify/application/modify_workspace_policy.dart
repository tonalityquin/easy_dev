import '../../../../app/models/capability.dart';

enum ModifyWorkspace {
  overview,
  vehicleIdentity,
  parking,
  camera,
  sector,
  billing,
  memo,
}

class ModifyWorkspacePolicy {
  const ModifyWorkspacePolicy({
    required this.area,
    required this.hasBill,
    required this.hasSector,
  });

  final String area;
  final bool hasBill;
  final bool hasSector;

  factory ModifyWorkspacePolicy.fromCapabilities({
    required String area,
    required CapSet capabilities,
  }) {
    return ModifyWorkspacePolicy(
      area: area.trim(),
      hasBill: capabilities.contains(Capability.bill),
      hasSector: capabilities.contains(Capability.sector),
    );
  }

  List<ModifyWorkspace> get railWorkspaces => <ModifyWorkspace>[
        ModifyWorkspace.parking,
        ModifyWorkspace.camera,
        if (hasSector) ModifyWorkspace.sector,
        if (hasBill) ModifyWorkspace.billing,
        ModifyWorkspace.memo,
      ];

  ModifyWorkspace get defaultWorkspace => ModifyWorkspace.overview;

  bool supports(ModifyWorkspace workspace) {
    switch (workspace) {
      case ModifyWorkspace.sector:
        return hasSector;
      case ModifyWorkspace.billing:
        return hasBill;
      case ModifyWorkspace.overview:
      case ModifyWorkspace.vehicleIdentity:
      case ModifyWorkspace.parking:
      case ModifyWorkspace.camera:
      case ModifyWorkspace.memo:
        return true;
    }
  }

  ModifyWorkspace fallbackFor(ModifyWorkspace workspace) {
    if (supports(workspace)) return workspace;
    return ModifyWorkspace.overview;
  }

  String get signature => '$area|bill=$hasBill|sector=$hasSector';
}
