import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../design_system/prompt_ui/prompt_ui_components.dart';
import '../../../../../design_system/prompt_ui/prompt_ui_theme.dart';
import '../../../../../app/utils/snackbar_helper.dart';
import '../../../widgets/ops_console_dialogs.dart';
import '../../../widgets/ops_console_widgets.dart';

class StatusMappingHelper extends StatefulWidget {
  const StatusMappingHelper({super.key});

  @override
  State<StatusMappingHelper> createState() => _StatusMappingHelperState();
}

class _AccountCounts {
  const _AccountCounts({
    required this.activeCount,
    required this.inactiveCount,
  });

  final int activeCount;
  final int inactiveCount;

  int get totalCount => activeCount + inactiveCount;

  Map<String, int> toMap() {
    return <String, int>{
      'activeCount': activeCount,
      'inactiveCount': inactiveCount,
      'totalCount': totalCount,
    };
  }
}

class _StatusMappingHelperState extends State<StatusMappingHelper> {
  static const int _maxLimit = 1 << 30;

  String? _selectedDivision;
  String? _selectedArea;

  List<String> _divisions = [];
  List<String> _areas = [];

  final TextEditingController _activeLimitCtrl = TextEditingController();
  final TextEditingController _totalLimitCtrl = TextEditingController();

  bool _busy = false;

  String? _progressLabel;
  int _progressDone = 0;
  int _progressTotal = 0;

  @override
  void initState() {
    super.initState();
    _loadDivisions();
  }

  @override
  void dispose() {
    _activeLimitCtrl.dispose();
    _totalLimitCtrl.dispose();
    super.dispose();
  }

  FirebaseFirestore get _fs => FirebaseFirestore.instance;

  String _showDocId(String division, String area) {
    final d = division.trim().isEmpty ? 'unknownDivision' : division.trim();
    final a = area.trim().isEmpty ? 'unknownArea' : area.trim();
    return '$d-$a';
  }

  DocumentReference<Map<String, dynamic>> _showDocRef(String division, String area) {
    final id = _showDocId(division, area);
    return _fs.collection('user_accounts_show').doc(id);
  }

  CollectionReference<Map<String, dynamic>> _showUsersCol(String division, String area) {
    return _showDocRef(division, area).collection('users');
  }

  int? _asInt(dynamic v) => v is int ? v : null;

  int _nonNegative(dynamic v) {
    final i = _asInt(v);
    if (i == null || i < 0) return 0;
    return i;
  }

  _AccountCounts _countsFromMeta(Map<String, dynamic> data) {
    final active = _nonNegative(data['activeCount']);
    final inactiveRaw = _asInt(data['inactiveCount']);
    final totalRaw = _asInt(data['totalCount']);
    var inactive = inactiveRaw == null || inactiveRaw < 0 ? 0 : inactiveRaw;
    if ((inactiveRaw == null || inactiveRaw < 0) && totalRaw != null && totalRaw >= active) {
      inactive = totalRaw - active;
    }
    return _AccountCounts(activeCount: active, inactiveCount: inactive);
  }

  Future<void> _loadDivisions() async {
    try {
      final snap = await _fs.collection('divisions').orderBy('name').get();

      final list = snap.docs
          .map((d) => (d.data()['name'] as String?)?.trim())
          .whereType<String>()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _divisions = list;
        _selectedDivision ??= _divisions.isNotEmpty ? _divisions.first : null;
      });

      await _loadAreas();
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '회사 목록 로드 실패: $e', usePromptUi: true);
    }
  }

  Future<void> _loadAreas() async {
    final division = _selectedDivision;
    if (division == null || division.trim().isEmpty) {
      if (!mounted) return;
      setState(() {
        _areas = [];
        _selectedArea = null;
      });
      return;
    }

    try {
      final snap = await _fs
          .collection('areas')
          .where('division', isEqualTo: division)
          .orderBy('name')
          .get();

      final list = snap.docs
          .map((d) => (d.data()['name'] as String?)?.trim())
          .whereType<String>()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _areas = list;
        _selectedArea = _areas.isNotEmpty ? _areas.first : null;
      });
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '지역 목록 로드 실패: $e', usePromptUi: true);
    }
  }

  int? _parseLimit(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    final v = int.tryParse(t);
    if (v == null) return null;
    if (v < 0) return 0;
    if (v > _maxLimit) return _maxLimit;
    return v;
  }

  Future<void> _saveLimits({
    required String division,
    required String area,
    required int activeLimit,
    required int totalLimit,
  }) async {
    final ref = _showDocRef(division, area);

    await ref.set(
      {
        'division': division,
        'area': area,
        'activeLimit': activeLimit,
        'totalLimit': totalLimit,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );
  }

  Future<_AccountCounts> _rebuildCountsForOne({
    required String division,
    required String area,
  }) async {
    final usersCol = _showUsersCol(division, area);

    final qSnap = await usersCol.get();

    var active = 0;
    var inactive = 0;
    for (final doc in qSnap.docs) {
      final data = doc.data();
      final isActive = (data['isActive'] as bool?) ?? true;
      if (isActive) {
        active += 1;
      } else {
        inactive += 1;
      }
    }

    final counts = _AccountCounts(activeCount: active, inactiveCount: inactive);

    await _showDocRef(division, area).set(
      {
        'division': division,
        'area': area,
        ...counts.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    return counts;
  }

  Future<void> _rebuildCountsForDivision(String division) async {
    setState(() {
      _busy = true;
      _progressLabel = '회사 전체 계정 수 리빌드 중: $division';
      _progressDone = 0;
      _progressTotal = 0;
    });

    try {
      final areasSnap = await _fs
          .collection('areas')
          .where('division', isEqualTo: division)
          .orderBy('name')
          .get();

      final areas = areasSnap.docs
          .map((d) => (d.data()['name'] as String?)?.trim())
          .whereType<String>()
          .toList()
        ..sort();

      if (!mounted) return;
      setState(() {
        _progressTotal = areas.length;
        _progressDone = 0;
      });

      for (final area in areas) {
        if (!mounted) return;
        setState(() {
          _progressLabel = '리빌드 진행: $division / $area';
        });

        await _rebuildCountsForOne(division: division, area: area);

        if (!mounted) return;
        setState(() {
          _progressDone += 1;
        });
      }

      if (!mounted) return;
      showSuccessSnackbar(context, '회사 "$division" 계정 수 리빌드 완료', usePromptUi: true);
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '회사 전체 리빌드 실패: $e', usePromptUi: true);
    } finally {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progressLabel = null;
        _progressDone = 0;
        _progressTotal = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = PromptUiTheme.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final division = _selectedDivision;
    final area = _selectedArea;

    final divisionDropdown = DropdownButtonFormField<String>(
      value: division,
      isExpanded: true,
      items: _divisions
          .map(
            (value) => DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _busy
          ? null
          : (value) async {
              setState(() {
                _selectedDivision = value;
                _areas = <String>[];
                _selectedArea = null;
                _activeLimitCtrl.clear();
                _totalLimitCtrl.clear();
              });
              await _loadAreas();
            },
      decoration: opsInputDecoration(
        context,
        label: '회사 선택',
        prefixIcon: const Icon(Icons.business_rounded),
      ),
    );

    final areaDropdown = DropdownButtonFormField<String>(
      value: area,
      isExpanded: true,
      items: _areas
          .map(
            (value) => DropdownMenuItem<String>(
              value: value,
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          )
          .toList(),
      onChanged: _busy
          ? null
          : (value) {
              setState(() {
                _selectedArea = value;
                _activeLimitCtrl.clear();
                _totalLimitCtrl.clear();
              });
            },
      decoration: opsInputDecoration(
        context,
        label: '지역 선택',
        prefixIcon: const Icon(Icons.location_on_rounded),
      ),
    );

    Widget buildMetaPanel() {
      if (division == null || area == null) {
        return const OpsEmptyState(
          icon: Icons.tune_rounded,
          title: '회사와 지역을 선택하세요',
          message: '선택한 운영 범위의 계정 제한과 현재 수량을 확인할 수 있습니다.',
        );
      }

      return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _showDocRef(division, area).snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final exists = snapshot.data?.exists ?? false;
          final activeLimit = data['activeLimit'];
          final totalLimit = data['totalLimit'];
          final counts = _countsFromMeta(data);
          final activeLimitInt = activeLimit is int ? activeLimit : null;
          final totalLimitInt = totalLimit is int ? totalLimit : null;
          final updatedValue = data['updatedAt'];
          final updatedAt =
              updatedValue is Timestamp ? updatedValue.toDate() : null;

          if (_activeLimitCtrl.text.trim().isEmpty && activeLimitInt != null) {
            _activeLimitCtrl.text = '$activeLimitInt';
          }
          if (_totalLimitCtrl.text.trim().isEmpty && totalLimitInt != null) {
            _totalLimitCtrl.text = '$totalLimitInt';
          }

          final activeWarning =
              activeLimitInt != null && counts.activeCount > activeLimitInt;
          final totalWarning =
              totalLimitInt != null && counts.totalCount > totalLimitInt;

          return OpsWorkSection(
            title: '계정 리밋 상태',
            subtitle: 'user_accounts_show/${_showDocId(division, area)}',
            icon: Icons.manage_accounts_rounded,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OpsStatusBadge(
                      label: exists ? '메타 연결됨' : '저장 시 생성',
                      color: exists ? tokens.success : tokens.warning,
                    ),
                    if (updatedAt != null)
                      OpsInfoPill(
                        icon: Icons.schedule_rounded,
                        text: updatedAt.toString(),
                      ),
                  ],
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final width = constraints.maxWidth;
                    final cardWidth = width < 560 ? width : (width - 20) / 3;
                    return Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        SizedBox(
                          width: cardWidth,
                          height: 92,
                          child: OpsMetricCard(
                            metric: OpsMetric(
                              label: '활성 계정',
                              value:
                                  '${counts.activeCount} / ${activeLimitInt ?? '-'}',
                              icon: Icons.person_rounded,
                              color: activeWarning ? tokens.danger : tokens.success,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          height: 92,
                          child: OpsMetricCard(
                            metric: OpsMetric(
                              label: '비활성 계정',
                              value: '${counts.inactiveCount}',
                              icon: Icons.person_off_rounded,
                              color: tokens.textSecondary,
                            ),
                          ),
                        ),
                        SizedBox(
                          width: cardWidth,
                          height: 92,
                          child: OpsMetricCard(
                            metric: OpsMetric(
                              label: '전체 계정',
                              value:
                                  '${counts.totalCount} / ${totalLimitInt ?? '-'}',
                              icon: Icons.groups_rounded,
                              color: totalWarning ? tokens.danger : tokens.info,
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                if (activeWarning || totalWarning) ...[
                  const SizedBox(height: 12),
                  OpsInlineMessage(
                    message: activeWarning && totalWarning
                        ? '활성 계정과 전체 계정 수가 설정한 리밋을 초과했습니다.'
                        : activeWarning
                            ? '활성 계정 수가 activeLimit을 초과했습니다.'
                            : '전체 계정 수가 totalLimit을 초과했습니다.',
                    danger: true,
                    icon: Icons.warning_amber_rounded,
                  ),
                ],
                const SizedBox(height: 14),
                TextField(
                  controller: _activeLimitCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                  decoration: opsInputDecoration(
                    context,
                    label: '활성 계정 제한',
                    prefixIcon: const Icon(Icons.person_rounded),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _totalLimitCtrl,
                  keyboardType: TextInputType.number,
                  enabled: !_busy,
                  decoration: opsInputDecoration(
                    context,
                    label: '전체 계정 제한',
                    prefixIcon: const Icon(Icons.groups_rounded),
                  ),
                ),
                const SizedBox(height: 12),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final narrow = constraints.maxWidth < 520;
                    final actions = <Widget>[
                      OpsActionButton(
                        label: '리밋 저장',
                        icon: Icons.save_rounded,
                        onPressed: _busy
                            ? null
                            : () async {
                                final activeValue =
                                    _parseLimit(_activeLimitCtrl.text);
                                final totalValue =
                                    _parseLimit(_totalLimitCtrl.text);
                                if (activeValue == null) {
                                  showFailedSnackbar(
                                    context,
                                    '활성 계정 제한값이 올바르지 않습니다.',
                                    usePromptUi: true,
                                  );
                                  return;
                                }
                                if (totalValue == null) {
                                  showFailedSnackbar(
                                    context,
                                    '전체 계정 제한값이 올바르지 않습니다.',
                                    usePromptUi: true,
                                  );
                                  return;
                                }
                                if (activeValue > totalValue) {
                                  showFailedSnackbar(
                                    context,
                                    '활성 계정 제한은 전체 계정 제한보다 클 수 없습니다.',
                                    usePromptUi: true,
                                  );
                                  return;
                                }

                                setState(() => _busy = true);
                                try {
                                  await _saveLimits(
                                    division: division,
                                    area: area,
                                    activeLimit: activeValue,
                                    totalLimit: totalValue,
                                  );
                                  if (!mounted) return;
                                  showSuccessSnackbar(
                                    context,
                                    '리밋 저장을 완료했습니다.',
                                    usePromptUi: true,
                                  );
                                } catch (error) {
                                  if (!mounted) return;
                                  showFailedSnackbar(
                                    context,
                                    '저장 실패: $error',
                                    usePromptUi: true,
                                  );
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                      ),
                      OpsActionButton(
                        label: '카운트 리빌드',
                        icon: Icons.refresh_rounded,
                        tonal: true,
                        onPressed: _busy
                            ? null
                            : () async {
                                setState(() => _busy = true);
                                try {
                                  final rebuilt = await _rebuildCountsForOne(
                                    division: division,
                                    area: area,
                                  );
                                  if (!mounted) return;
                                  showSuccessSnackbar(
                                    context,
                                    '리빌드 완료: 활성 ${rebuilt.activeCount}, 비활성 ${rebuilt.inactiveCount}, 전체 ${rebuilt.totalCount}',
                                    usePromptUi: true,
                                  );
                                } catch (error) {
                                  if (!mounted) return;
                                  showFailedSnackbar(
                                    context,
                                    '리빌드 실패: $error',
                                    usePromptUi: true,
                                  );
                                } finally {
                                  if (mounted) setState(() => _busy = false);
                                }
                              },
                      ),
                    ];
                    if (narrow) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          actions[0],
                          const SizedBox(height: 8),
                          actions[1],
                        ],
                      );
                    }
                    return Row(
                      children: [
                        Expanded(child: actions[0]),
                        const SizedBox(width: 8),
                        Expanded(child: actions[1]),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                OpsActionButton(
                  label: '회사 전체 카운트 리빌드',
                  icon: Icons.playlist_add_check_rounded,
                  tonal: true,
                  onPressed: _busy
                      ? null
                      : () async {
                          final confirmed = await showOpsConfirmDialog(
                            context: context,
                            title: '회사 전체 리빌드',
                            message:
                                '선택된 회사의 모든 지역에 대해 활성, 비활성, 전체 계정 수를 재집계합니다.',
                            confirmLabel: '실행',
                            icon: Icons.playlist_add_check_rounded,
                          );
                          if (!confirmed) return;
                          await _rebuildCountsForDivision(division);
                        },
                ),
              ],
            ),
          );
        },
      );
    }

    return ColoredBox(
      color: tokens.canvas,
      child: Stack(
        children: [
          ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              16,
              16,
              24 + MediaQuery.viewPaddingOf(context).bottom,
            ),
            children: [
              PromptAnimatedReveal(
                child: OpsConsoleHeader(
                  title: '계정 리밋 설정',
                  subtitle: '회사와 지역별 계정 생성 제한과 집계 상태를 관리합니다.',
                  icon: Icons.tune_rounded,
                ),
              ),
              const SizedBox(height: 12),
              PromptAnimatedReveal(
                delay: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 45),
                child: OpsCommandPanel(
                  children: [
                    const OpsSectionTitle(
                      title: '운영 범위',
                      subtitle: '회사와 지역을 순서대로 선택하세요.',
                      icon: Icons.account_tree_rounded,
                    ),
                    const SizedBox(height: 12),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 520) {
                          return Column(
                            children: [
                              divisionDropdown,
                              const SizedBox(height: 10),
                              areaDropdown,
                            ],
                          );
                        }
                        return Row(
                          children: [
                            Expanded(child: divisionDropdown),
                            const SizedBox(width: 10),
                            Expanded(child: areaDropdown),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              if (_progressLabel != null) ...[
                const SizedBox(height: 12),
                PromptAnimatedReveal(
                  child: OpsPanel(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OpsSectionTitle(
                          title: _progressLabel!,
                          subtitle: _progressTotal > 0
                              ? '$_progressDone / $_progressTotal'
                              : null,
                          icon: Icons.sync_rounded,
                        ),
                        const SizedBox(height: 12),
                        LinearProgressIndicator(
                          value: _progressTotal > 0
                              ? (_progressDone / _progressTotal)
                                  .clamp(0.0, 1.0)
                              : null,
                          color: tokens.accent,
                          backgroundColor: tokens.surfaceOverlay,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              PromptAnimatedReveal(
                delay: reduceMotion
                    ? Duration.zero
                    : const Duration(milliseconds: 90),
                child: buildMetaPanel(),
              ),
            ],
          ),
          Positioned.fill(
            child: IgnorePointer(
              ignoring: !_busy,
              child: AnimatedOpacity(
                opacity: _busy ? 1 : 0,
                duration: reduceMotion
                    ? Duration.zero
                    : PromptUiMotion.selection,
                child: ColoredBox(
                  color: tokens.scrim.withOpacity(.1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
