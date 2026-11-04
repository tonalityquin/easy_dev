import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app/models/capability.dart';
import '../../../../../design_system/common_ui/common_ui_components.dart';
import '../../../../../design_system/common_ui/common_ui_theme.dart';
import '../../../widgets/ops_console_widgets.dart';

class DevAreaModePolicy {
  const DevAreaModePolicy._();

  static const List<String> canonicalModes = <String>[
    'single',
    'double',
    'triple',
    'minor',
  ];

  static const Set<String> headquarterModes = <String>{
    'single',
    'double',
    'triple',
    'minor',
  };

  static bool isCanonical(String value) {
    return canonicalModes.contains(value.trim().toLowerCase());
  }

  static bool areCanonical(Iterable<String> values) {
    final normalized = values.map((value) => value.trim().toLowerCase()).where((value) => value.isNotEmpty).toList();
    return normalized.isNotEmpty && normalized.every(canonicalModes.contains);
  }

  static Set<String> normalizeModes(Iterable<String> values) {
    final normalized = <String>{};
    for (final raw in values) {
      switch (raw.trim().toLowerCase()) {
        case 'single':
          normalized.add('single');
          break;
        case 'double':
        case 'lite':
        case 'light':
          normalized.add('double');
          break;
        case 'triple':
          normalized.add('triple');
          break;
        case 'minor':
          normalized.add('minor');
          break;
      }
    }
    return normalized;
  }

  static String label(String value) {
    switch (value.trim().toLowerCase()) {
      case 'single':
        return 'Single';
      case 'double':
        return 'Double';
      case 'triple':
        return 'Triple';
      case 'minor':
        return 'Minor';
      case 'lite':
      case 'light':
        return 'Lite';
      case 'service':
        return 'Service';
      default:
        return value.trim();
    }
  }
}

class DevAreaSettingsDraft {
  const DevAreaSettingsDraft({
    required this.englishName,
    required this.modes,
    required this.capabilities,
    required this.activeLimit,
    required this.totalLimit,
  });

  final String englishName;
  final Set<String> modes;
  final Set<Capability> capabilities;
  final int? activeLimit;
  final int? totalLimit;

  List<String> get modeKeys {
    final values = DevAreaModePolicy.normalizeModes(modes).toList()..sort();
    return values;
  }

  List<String> get capabilityKeys {
    final values = capabilities.map((value) => value.key).toSet().toList()..sort();
    return values;
  }

  Map<String, dynamic> areaPayload({
    required String name,
    required String division,
    required bool isHeadquarter,
    bool includeCreatedAt = true,
  }) {
    return _areaPayload(
      name: name,
      division: division,
      isHeadquarter: isHeadquarter,
      modeKeys: modeKeys,
      includeCreatedAt: includeCreatedAt,
    );
  }

  Map<String, dynamic> headquarterAreaPayload({
    required String name,
    required String division,
    bool includeCreatedAt = true,
  }) {
    final values = DevAreaModePolicy.headquarterModes.toList()..sort();
    return _areaPayload(
      name: name,
      division: division,
      isHeadquarter: true,
      modeKeys: values,
      includeCreatedAt: includeCreatedAt,
    );
  }

  Map<String, dynamic> _areaPayload({
    required String name,
    required String division,
    required bool isHeadquarter,
    required List<String> modeKeys,
    required bool includeCreatedAt,
  }) {
    return <String, dynamic>{
      'name': name.trim(),
      'englishName': englishName.trim(),
      'division': division.trim(),
      'modes': modeKeys,
      'capabilities': capabilityKeys,
      'isHeadquarter': isHeadquarter,
      if (includeCreatedAt) 'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> accountMetaPayload({
    required String division,
    required String area,
    required int activeCount,
    required int inactiveCount,
  }) {
    return <String, dynamic>{
      'division': division.trim(),
      'area': area.trim(),
      'activeCount': activeCount,
      'inactiveCount': inactiveCount,
      'totalCount': activeCount + inactiveCount,
      if (activeLimit != null) 'activeLimit': activeLimit,
      if (totalLimit != null) 'totalLimit': totalLimit,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}

class DivisionCreateRequest {
  const DivisionCreateRequest({
    required this.name,
    required this.settings,
  });

  final String name;
  final DevAreaSettingsDraft settings;
}

class DevAreaListItem {
  const DevAreaListItem({
    required this.documentId,
    required this.name,
    required this.englishName,
    required this.division,
    required this.modes,
    required this.capabilities,
    required this.isHeadquarter,
    required this.hasEnglishNameField,
    required this.hasModesField,
    required this.hasCapabilitiesField,
    required this.hasIsHeadquarterField,
  });

  final String documentId;
  final String name;
  final String englishName;
  final String division;
  final List<String> modes;
  final Set<Capability> capabilities;
  final bool isHeadquarter;
  final bool hasEnglishNameField;
  final bool hasModesField;
  final bool hasCapabilitiesField;
  final bool hasIsHeadquarterField;

  bool get hasCanonicalModes => DevAreaModePolicy.areCanonical(modes);

  bool get schemaComplete =>
      hasEnglishNameField &&
      hasModesField &&
      hasCanonicalModes &&
      hasCapabilitiesField &&
      hasIsHeadquarterField &&
      englishName.isNotEmpty;

  factory DevAreaListItem.fromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final rawModes = data['modes'];
    final modes = rawModes is Iterable
        ? rawModes
            .map((value) => value.toString().trim().toLowerCase())
            .where((value) => value.isNotEmpty)
            .toSet()
            .toList(growable: false)
        : const <String>[];
    return DevAreaListItem(
      documentId: doc.id,
      name: (data['name'] ?? '').toString().trim(),
      englishName: (data['englishName'] ?? '').toString().trim(),
      division: (data['division'] ?? '').toString().trim(),
      modes: modes,
      capabilities: Cap.fromDynamic(data['capabilities']),
      isHeadquarter: data['isHeadquarter'] == true,
      hasEnglishNameField: data.containsKey('englishName'),
      hasModesField: data.containsKey('modes'),
      hasCapabilitiesField: data.containsKey('capabilities'),
      hasIsHeadquarterField: data.containsKey('isHeadquarter'),
    );
  }
}

class DevManagementValidation {
  const DevManagementValidation._();

  static String normalizeName(String value) {
    return value.trim().replaceAll('/', '-').replaceAll(RegExp(r'\s+'), ' ');
  }

  static int? parseOptionalLimit(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return null;
    final parsed = int.tryParse(normalized);
    if (parsed == null || parsed < 0 || parsed > (1 << 30)) return -1;
    return parsed;
  }

  static String? validateLimits({
    required String activeText,
    required String totalText,
  }) {
    final active = parseOptionalLimit(activeText);
    final total = parseOptionalLimit(totalText);
    if (active == -1) return '활성 계정 제한값을 확인하세요.';
    if (total == -1) return '전체 계정 제한값을 확인하세요.';
    final eitherConfigured = active != null || total != null;
    if (eitherConfigured && (active == null || total == null)) {
      return '계정 제한은 활성과 전체 값을 함께 입력하세요.';
    }
    if (active != null && total != null && active > total) {
      return '활성 계정 제한은 전체 계정 제한보다 클 수 없습니다.';
    }
    return null;
  }

  static String? validateAreaSettings({
    required String englishName,
    required Set<String> modes,
    required String activeLimit,
    required String totalLimit,
  }) {
    if (englishName.trim().isEmpty) return '영문 이름을 입력하세요.';
    if (modes.isEmpty) return '운영 모드를 1개 이상 선택하세요.';
    if (!DevAreaModePolicy.areCanonical(modes)) return '운영 모드를 다시 선택하세요.';
    return validateLimits(activeText: activeLimit, totalText: totalLimit);
  }
}

class DevAreaSettingsFields extends StatelessWidget {
  const DevAreaSettingsFields({
    super.key,
    required this.englishNameController,
    required this.activeLimitController,
    required this.totalLimitController,
    required this.selectedModes,
    required this.selectedCapabilities,
    required this.onModesChanged,
    required this.onCapabilitiesChanged,
    this.showModeSelector = true,
    this.enabled = true,
  });

  final TextEditingController englishNameController;
  final TextEditingController activeLimitController;
  final TextEditingController totalLimitController;
  final Set<String> selectedModes;
  final Set<Capability> selectedCapabilities;
  final ValueChanged<Set<String>> onModesChanged;
  final ValueChanged<Set<Capability>> onCapabilitiesChanged;
  final bool showModeSelector;
  final bool enabled;

  Widget _sectionLabel(BuildContext context, String text, IconData icon) {
    final tokens = CommonUiTheme.of(context);
    return Row(
      children: [
        Icon(icon, size: 17, color: tokens.iconSecondary),
        const SizedBox(width: 7),
        Text(
          text,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final tokens = CommonUiTheme.of(context);
    final sortedModes = selectedModes.toList()..sort();
    final sortedCapabilityKeys = selectedCapabilities.map((value) => value.key).toList()..sort();
    final selectedCapabilityLabel = selectedCapabilities.isEmpty ? '기능 없음' : Cap.human(selectedCapabilities);
    final selectedModeLabel = sortedModes.isEmpty
        ? '운영 모드 미선택'
        : sortedModes.map(DevAreaModePolicy.label).join(' · ');

    final modeSection = Column(
      key: const ValueKey<String>('dev_area_mode_selector'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 14),
        _sectionLabel(context, '운영 모드', Icons.widgets_rounded),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: DevAreaModePolicy.canonicalModes.map((mode) {
            final selected = selectedModes.contains(mode);
            return FilterChip(
              label: Text(DevAreaModePolicy.label(mode)),
              selected: selected,
              onSelected: enabled
                  ? (value) {
                      final next = Set<String>.of(selectedModes);
                      if (value) {
                        next.add(mode);
                      } else {
                        next.remove(mode);
                      }
                      onModesChanged(next);
                    }
                  : null,
            );
          }).toList(growable: false),
        ),
        const SizedBox(height: 8),
        AnimatedSwitcher(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
          switchInCurve: CommonUiMotion.enter,
          switchOutCurve: CommonUiMotion.exit,
          child: Text(
            selectedModeLabel,
            key: ValueKey<String>(sortedModes.join(',')),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CommonAnimatedReveal(
          child: TextField(
            controller: englishNameController,
            enabled: enabled,
            textInputAction: TextInputAction.next,
            decoration: opsInputDecoration(
              context,
              label: '영문 이름',
              prefixIcon: const Icon(Icons.translate_rounded),
            ),
          ),
        ),
        AnimatedSize(
          duration: reduceMotion ? Duration.zero : CommonUiMotion.component,
          curve: CommonUiMotion.enter,
          alignment: Alignment.topCenter,
          child: showModeSelector ? modeSection : const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        CommonAnimatedReveal(
          delay: reduceMotion ? Duration.zero : const Duration(milliseconds: 35),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel(context, '기능', Icons.extension_rounded),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: Capability.values.map((capability) {
                  final selected = selectedCapabilities.contains(capability);
                  return FilterChip(
                    label: Text(capability.label),
                    selected: selected,
                    onSelected: enabled
                        ? (value) {
                            final next = Set<Capability>.of(selectedCapabilities);
                            if (value) {
                              next.add(capability);
                            } else {
                              next.remove(capability);
                            }
                            onCapabilitiesChanged(next);
                          }
                        : null,
                  );
                }).toList(growable: false),
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: reduceMotion ? Duration.zero : CommonUiMotion.selection,
                switchInCurve: CommonUiMotion.enter,
                switchOutCurve: CommonUiMotion.exit,
                child: Text(
                  selectedCapabilityLabel,
                  key: ValueKey<String>(sortedCapabilityKeys.join(',')),
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: tokens.textSecondary,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CommonAnimatedReveal(
          delay: reduceMotion ? Duration.zero : const Duration(milliseconds: 60),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _sectionLabel(context, '계정 정책', Icons.manage_accounts_rounded),
              const SizedBox(height: 8),
              LayoutBuilder(
                builder: (context, constraints) {
                  final narrow = constraints.maxWidth < 430;
                  final activeField = TextField(
                    controller: activeLimitController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    textInputAction: narrow ? TextInputAction.next : TextInputAction.done,
                    decoration: opsInputDecoration(
                      context,
                      label: '활성 계정 제한',
                      prefixIcon: const Icon(Icons.person_rounded),
                    ),
                  );
                  final totalField = TextField(
                    controller: totalLimitController,
                    enabled: enabled,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.done,
                    decoration: opsInputDecoration(
                      context,
                      label: '전체 계정 제한',
                      prefixIcon: const Icon(Icons.groups_rounded),
                    ),
                  );
                  if (narrow) {
                    return Column(
                      children: [
                        activeField,
                        const SizedBox(height: 10),
                        totalField,
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: activeField),
                      const SizedBox(width: 10),
                      Expanded(child: totalField),
                    ],
                  );
                },
              ),
              const SizedBox(height: 8),
              Text(
                '두 값을 비우면 리밋 미설정 상태로 저장됩니다.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: tokens.textSecondary,
                      height: 1.35,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
