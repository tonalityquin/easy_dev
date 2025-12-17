// lib/screens/secondary_package/dev_mode_package/area_management_package/status_mapping_helper.dart
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../../utils/snackbar_helper.dart';
import '../../../../../utils/usage/usage_reporter.dart';

class StatusMappingHelper extends StatefulWidget {
  const StatusMappingHelper({super.key});

  @override
  State<StatusMappingHelper> createState() => _StatusMappingHelperState();
}

class _StatusMappingHelperState extends State<StatusMappingHelper> {
  static const int _maxLimit = 1 << 30;

  // 선택 상태
  String? _selectedDivision;
  String? _selectedArea;

  // 드롭다운 소스
  List<String> _divisions = [];
  List<String> _areas = [];

  // activeLimit 입력
  final TextEditingController _limitCtrl = TextEditingController();

  bool _busy = false;

  // 리빌드 진행 표시(division 전체 리빌드 등)
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
    _limitCtrl.dispose();
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

  Future<void> _loadDivisions() async {
    try {
      final snap = await _fs.collection('divisions').orderBy('name').get();

      // ✅ UsageReporter: read (divisions)
      try {
        await UsageReporter.instance.report(
          area: 'StatusMappingHelper',
          action: 'read',
          n: snap.docs.isEmpty ? 1 : snap.docs.length,
          source: 'StatusMappingHelper._loadDivisions.divisions.get',
        );
      } catch (_) {}

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

      // ✅ UsageReporter: read (areas by division)
      try {
        await UsageReporter.instance.report(
          area: division,
          action: 'read',
          n: snap.docs.isEmpty ? 1 : snap.docs.length,
          source: 'StatusMappingHelper._loadAreas.areas.get',
        );
      } catch (_) {}

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

  Future<void> _saveActiveLimit({
    required String division,
    required String area,
    required int activeLimit,
  }) async {
    final ref = _showDocRef(division, area);
    final showId = _showDocId(division, area);

    await ref.set(
      {
        'division': division,
        'area': area,
        'activeLimit': activeLimit,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // ✅ UsageReporter: write
    try {
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'StatusMappingHelper._saveActiveLimit.user_accounts_show.set:$showId',
      );
    } catch (_) {}
  }

  /// ✅ 레거시/정합성 보정: show/users에서 isActive==true를 재집계하여
  /// user_accounts_show/{division-area}.activeCount를 갱신한다.
  Future<int> _rebuildActiveCountForOne({
    required String division,
    required String area,
  }) async {
    final showId = _showDocId(division, area);
    final usersCol = _showUsersCol(division, area);

    // active 사용자 재집계 (레거시 데이터가 많으면 비용 큼)
    final qSnap = await usersCol.where('isActive', isEqualTo: true).get();

    // ✅ UsageReporter: read (active users fetched)
    try {
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: qSnap.docs.isEmpty ? 1 : qSnap.docs.length,
        source: 'StatusMappingHelper._rebuildActiveCountForOne.showUsers.query:$showId',
      );
    } catch (_) {}

    final count = qSnap.docs.length;

    await _showDocRef(division, area).set(
      {
        'division': division,
        'area': area,
        'activeCount': count,
        'updatedAt': FieldValue.serverTimestamp(),
      },
      SetOptions(merge: true),
    );

    // ✅ UsageReporter: write (meta update)
    try {
      await UsageReporter.instance.report(
        area: area,
        action: 'write',
        n: 1,
        source: 'StatusMappingHelper._rebuildActiveCountForOne.meta.set:$showId',
      );
    } catch (_) {}

    return count;
  }

  /// ✅ 레거시 데이터가 많을 때: division 내 모든 area에 대해 activeCount 재빌드
  /// (areas 컬렉션을 기준으로 showId를 만들고 순차 처리)
  Future<void> _rebuildActiveCountForDivision(String division) async {
    setState(() {
      _busy = true;
      _progressLabel = '회사 전체(activeCount) 리빌드 중: $division';
      _progressDone = 0;
      _progressTotal = 0;
    });

    try {
      final areasSnap = await _fs
          .collection('areas')
          .where('division', isEqualTo: division)
          .orderBy('name')
          .get();

      // ✅ UsageReporter: read (areas list)
      try {
        await UsageReporter.instance.report(
          area: division,
          action: 'read',
          n: areasSnap.docs.isEmpty ? 1 : areasSnap.docs.length,
          source: 'StatusMappingHelper._rebuildActiveCountForDivision.areas.get',
        );
      } catch (_) {}

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

        await _rebuildActiveCountForOne(division: division, area: area);

        if (!mounted) return;
        setState(() {
          _progressDone += 1;
        });
      }

      if (!mounted) return;
      showSuccessSnackbar(context, '✅ 회사 "$division" activeCount 리빌드 완료');
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
          .map((e) => DropdownMenuItem(
        value: e,
        child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      onChanged: _busy
          ? null
          : (v) async {
        setState(() {
          _selectedDivision = v;
          _areas = [];
          _selectedArea = null;
          _limitCtrl.clear();
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
          .map((e) => DropdownMenuItem(
        value: e,
        child: Text(e, maxLines: 1, overflow: TextOverflow.ellipsis),
      ))
          .toList(),
      onChanged: _busy
          ? null
          : (v) {
        setState(() {
          _selectedArea = v;
          _limitCtrl.clear();
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
        final activeCount = data['activeCount'];

        final int? limitInt = (activeLimit is int) ? activeLimit : null;
        final int? countInt = (activeCount is int) ? activeCount : null;

        // updatedAt 표시(옵션)
        DateTime? updatedAt;
        final ua = data['updatedAt'];
        if (ua is Timestamp) {
          updatedAt = ua.toDate();
        }

        // ✅ UsageReporter: read (meta snapshot)
        if (snap.hasData) {
          try {
            UsageReporter.instance.report(
              area: area,
              action: 'read',
              n: 1,
              source: 'StatusMappingHelper.showMeta.stream:$division-$area',
            );
          } catch (_) {}
        }

        // limit 필드가 비어 있으면, 표시용으로 컨트롤러를 자동 채움(단, 사용자가 직접 수정 중이면 덮지 않도록 단순 조건)
        if (_limitCtrl.text.trim().isEmpty && limitInt != null) {
          _limitCtrl.text = '$limitInt';
        }

        final warn = (limitInt != null && countInt != null && countInt > limitInt);

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
              const SizedBox(height: 8),

              Text(
                'activeCount: ${countInt ?? '(미설정)'}   /   activeLimit: ${limitInt ?? '(미설정)'}',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: warn ? Colors.redAccent : Colors.black87,
                ),
              ),
              if (warn)
                const Padding(
                  padding: EdgeInsets.only(top: 6),
                  child: Text(
                    '주의: activeCount가 activeLimit을 초과합니다. 제한을 상향하거나 비활성화를 진행하세요.',
                    style: TextStyle(color: Colors.redAccent, fontSize: 12),
                  ),
                ),
              const SizedBox(height: 12),

              TextField(
                controller: _limitCtrl,
                keyboardType: TextInputType.number,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'activeLimit (정수)',
                  hintText: '예: 30',
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
                      label: const Text('activeLimit 저장'),
                      onPressed: _busy
                          ? null
                          : () async {
                        final v = _parseLimit(_limitCtrl.text);
                        if (v == null) {
                          showFailedSnackbar(context, 'activeLimit 값이 올바르지 않습니다.');
                          return;
                        }

                        setState(() => _busy = true);
                        try {
                          await _saveActiveLimit(
                            division: division,
                            area: area,
                            activeLimit: v,
                          );
                          if (!mounted) return;
                          showSuccessSnackbar(context, '✅ activeLimit 저장 완료 (N=$v)');
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
                    label: const Text('activeCount 리빌드'),
                    onPressed: _busy
                        ? null
                        : () async {
                      setState(() => _busy = true);
                      try {
                        final c = await _rebuildActiveCountForOne(
                          division: division,
                          area: area,
                        );
                        if (!mounted) return;
                        showSuccessSnackbar(context, '✅ activeCount 리빌드 완료 (activeCount=$c)');
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
                label: const Text('회사 전체 activeCount 리빌드'),
                onPressed: _busy
                    ? null
                    : () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (_) => AlertDialog(
                      title: const Text('회사 전체 리빌드'),
                      content: const Text(
                        '선택된 회사의 모든 지역(area)에 대해 activeCount를 재집계합니다.\n'
                            '레거시 데이터가 많거나 users가 많은 경우 시간이 오래 걸릴 수 있습니다.',
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
                  await _rebuildActiveCountForDivision(division);
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
                '이 화면은 더 이상 location_limits를 사용하지 않습니다.\n'
                    'user_accounts_show/{division-area} 메타의 activeLimit 설정 및 activeCount 리빌드(재집계) 용도입니다.',
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
                  : SingleChildScrollView(
                child: showMeta,
              ),
            ),

            if (_busy) const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
          ],
        ),
      ),
    );
  }
}
