import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../../../app/utils/snackbar_helper.dart';

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
      showFailedSnackbar(context, '회사 목록 로드 실패: $e');
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
      showFailedSnackbar(context, '지역 목록 로드 실패: $e');
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
      showSuccessSnackbar(context, '✅ 회사 "$division" 계정 수 리빌드 완료');
    } catch (e) {
      if (!mounted) return;
      showFailedSnackbar(context, '❌ 회사 전체 리빌드 실패: $e');
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
    final divisionDropdown = DropdownButtonFormField<String>(
      value: _selectedDivision,
      isExpanded: true,
      items: _divisions
          .map(
            (e) => DropdownMenuItem(
          value: e,
          child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      )
          .toList(),
      onChanged: _busy
          ? null
          : (v) async {
        setState(() {
          _selectedDivision = v;
          _areas = [];
          _selectedArea = null;
          _activeLimitCtrl.clear();
          _totalLimitCtrl.clear();
        });
        await _loadAreas();
      },
      decoration: const InputDecoration(
        labelText: '회사(division) 선택',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );

    final areaDropdown = DropdownButtonFormField<String>(
      value: _selectedArea,
      isExpanded: true,
      items: _areas
          .map(
            (e) => DropdownMenuItem(
          value: e,
          child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      )
          .toList(),
      onChanged: _busy
          ? null
          : (v) {
        setState(() {
          _selectedArea = v;
          _activeLimitCtrl.clear();
          _totalLimitCtrl.clear();
        });
      },
      decoration: const InputDecoration(
        labelText: '지역(area) 선택',
        border: OutlineInputBorder(),
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );

    final division = _selectedDivision;
    final area = _selectedArea;

    final showMeta = (division == null || area == null)
        ? const SizedBox.shrink()
        : StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _showDocRef(division, area).snapshots(),
      builder: (context, snap) {
        final data = snap.data?.data() ?? <String, dynamic>{};
        final exists = snap.data?.exists ?? false;

        final activeLimit = data['activeLimit'];
        final totalLimit = data['totalLimit'];
        final counts = _countsFromMeta(data);

        final int? activeLimitInt = activeLimit is int ? activeLimit : null;
        final int? totalLimitInt = totalLimit is int ? totalLimit : null;

        DateTime? updatedAt;
        final ua = data['updatedAt'];
        if (ua is Timestamp) {
          updatedAt = ua.toDate();
        }

        if (_activeLimitCtrl.text.trim().isEmpty && activeLimitInt != null) {
          _activeLimitCtrl.text = '$activeLimitInt';
        }
        if (_totalLimitCtrl.text.trim().isEmpty && totalLimitInt != null) {
          _totalLimitCtrl.text = '$totalLimitInt';
        }

        final activeWarn = activeLimitInt != null && counts.activeCount > activeLimitInt;
        final totalWarn = totalLimitInt != null && counts.totalCount > totalLimitInt;

        return Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            border: Border.all(color: Colors.black12),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '메타 문서: user_accounts_show/${_showDocId(division, area)}',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      exists ? '상태: 존재함' : '상태: 없음(저장 시 생성됨)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: exists ? Colors.black87 : Colors.orange[800],
                      ),
                    ),
                  ),
                  if (updatedAt != null)
                    Text(
                      'updatedAt: ${updatedAt.toString()}',
                      style: const TextStyle(fontSize: 11, color: Colors.black54),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '활성: ${counts.activeCount} / ${activeLimitInt ?? '(미설정)'}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: activeWarn ? Colors.redAccent : Colors.black87,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '비활성: ${counts.inactiveCount}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '전체: ${counts.totalCount} / ${totalLimitInt ?? '(미설정)'}',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: totalWarn ? Colors.redAccent : Colors.black87,
                ),
              ),
              if (activeWarn)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '주의: 활성 계정 수가 activeLimit을 초과합니다.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              if (totalWarn)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '주의: 전체 계정 수가 totalLimit을 초과합니다.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _activeLimitCtrl,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'activeLimit 활성 계정 제한',
                  hintText: '예: 30',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _totalLimitCtrl,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'totalLimit 전체 계정 제한',
                  hintText: '예: 50',
                  border: OutlineInputBorder(),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.save),
                      label: const Text('리밋 저장'),
                      onPressed: _busy
                          ? null
                          : () async {
                        final activeValue = _parseLimit(_activeLimitCtrl.text);
                        final totalValue = _parseLimit(_totalLimitCtrl.text);
                        if (activeValue == null) {
                          showFailedSnackbar(context, 'activeLimit 값이 올바르지 않습니다.');
                          return;
                        }
                        if (totalValue == null) {
                          showFailedSnackbar(context, 'totalLimit 값이 올바르지 않습니다.');
                          return;
                        }
                        if (activeValue > totalValue) {
                          showFailedSnackbar(context, 'activeLimit은 totalLimit보다 클 수 없습니다.');
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
                          showSuccessSnackbar(context, '✅ 리밋 저장 완료');
                        } catch (e) {
                          if (!mounted) return;
                          showFailedSnackbar(context, '❌ 저장 실패: $e');
                        } finally {
                          if (!mounted) return;
                          setState(() => _busy = false);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.refresh),
                    label: const Text('카운트 리빌드'),
                    onPressed: _busy
                        ? null
                        : () async {
                      setState(() => _busy = true);
                      try {
                        final c = await _rebuildCountsForOne(
                          division: division,
                          area: area,
                        );
                        if (!mounted) return;
                        showSuccessSnackbar(
                          context,
                          '✅ 리빌드 완료 (활성=${c.activeCount}, 비활성=${c.inactiveCount}, 전체=${c.totalCount})',
                        );
                      } catch (e) {
                        if (!mounted) return;
                        showFailedSnackbar(context, '❌ 리빌드 실패: $e');
                      } finally {
                        if (!mounted) return;
                        setState(() => _busy = false);
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                icon: const Icon(Icons.playlist_add_check),
                label: const Text('회사 전체 카운트 리빌드'),
                onPressed: _busy
                    ? null
                    : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('회사 전체 리빌드'),
                      content: const Text(
                        '선택된 회사의 모든 지역(area)에 대해 활성, 비활성, 전체 계정 수를 재집계합니다.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('취소'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('실행'),
                        ),
                      ],
                    ),
                  ) ??
                      false;
                  if (!ok) return;
                  await _rebuildCountsForDivision(division);
                },
              ),
            ],
          ),
        );
      },
    );

    return AbsorbPointer(
      absorbing: _busy,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'user_accounts_show/{division-area} 메타의 activeLimit, totalLimit 설정 및 계정 수 리빌드 용도입니다.',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (context, c) {
                final narrow = c.maxWidth < 360;
                if (narrow) {
                  return Column(
                    children: [
                      divisionDropdown,
                      const SizedBox(height: 12),
                      areaDropdown,
                    ],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: divisionDropdown),
                    const SizedBox(width: 12),
                    Expanded(child: areaDropdown),
                  ],
                );
              },
            ),
            const SizedBox(height: 16),
            if (_progressLabel != null)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.04),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_progressLabel!, style: const TextStyle(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 8),
                    if (_progressTotal > 0)
                      LinearProgressIndicator(
                        value: (_progressDone / _progressTotal).clamp(0.0, 1.0),
                      ),
                    const SizedBox(height: 6),
                    if (_progressTotal > 0)
                      Text('$_progressDone / $_progressTotal', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
            if (_progressLabel != null) const SizedBox(height: 12),
            Expanded(
              child: (division == null || area == null)
                  ? const Center(child: Text('회사와 지역을 선택하세요.'))
                  : SingleChildScrollView(child: showMeta),
            ),
            if (_busy) const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}