import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../../../../../app/utils/status_dialog.dart';


class _UserAccountsTabCounts {
  const _UserAccountsTabCounts({
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

class UserAccountsTab extends StatefulWidget {
  final String? selectedDivision;
  final String? selectedArea;
  final ValueChanged<String?> onDivisionChanged;
  final ValueChanged<String?> onAreaChanged;

  const UserAccountsTab({
    super.key,
    required this.selectedDivision,
    required this.selectedArea,
    required this.onDivisionChanged,
    required this.onAreaChanged,
  });

  @override
  State<UserAccountsTab> createState() => _UserAccountsTabState();
}

class _UserAccountsTabState extends State<UserAccountsTab> {
  static const List<String> _roles = <String>[
    'dev',
    'adminBillMonthly',
    'adminBillMonthlyTablet',
    'adminBill',
    'adminBillTablet',
    'adminCommon',
    'adminCommonTablet',
    'userLocationMonthly',
    'userMonthly',
    'userCommon',
    'fieldCommon',
  ];

  final Map<String, Map<String, dynamic>> _editedUsers = <String, Map<String, dynamic>>{};
  final Set<String> _savingIds = <String>{};
  bool _creating = false;
  int _refreshTick = 0;

  Map<String, dynamic> _copyUser(Map<String, dynamic> d) => <String, dynamic>{
        'name': d['name'] ?? '',
        'phone': d['phone'] ?? '',
        'email': d['email'] ?? '',
        'password': d['password'] ?? '',
        'divisions': List<String>.from(d['divisions'] ?? const <String>[]),
        'areas': List<String>.from(d['areas'] ?? const <String>[]),
        'role': d['role'] ?? 'fieldCommon',
        'modes': List<String>.from(d['modes'] ?? const <String>[]),
        'position': d['position'] ?? '',
        'currentArea': d['currentArea'],
        'selectedArea': d['selectedArea'],
        'englishSelectedAreaName': d['englishSelectedAreaName'],
        'startTime': d['startTime'],
        'endTime': d['endTime'],
        'startTimeByWeekday': Map<String, dynamic>.from(d['startTimeByWeekday'] ?? const <String, dynamic>{}),
        'endTimeByWeekday': Map<String, dynamic>.from(d['endTimeByWeekday'] ?? const <String, dynamic>{}),
        'fixedHolidays': List<String>.from(d['fixedHolidays'] ?? const <String>[]),
        'isSaved': d['isSaved'] ?? false,
        'isSelected': d['isSelected'] ?? false,
        'isWorking': d['isWorking'] ?? false,
        'isActive': d['isActive'] ?? true,
        'createdAt': d['createdAt'],
        'updatedAt': d['updatedAt'],
      };

  Future<List<String>> fetchDivisions() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .get(const GetOptions(source: Source.server));


    return snapshot.docs
        .map((doc) => (doc.data()['division'] ?? '').toString().trim())
        .where((division) => division.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>> getAreasByDivisions(List<String> divisions) async {
    if (divisions.isEmpty) return <String>[];
    final fs = FirebaseFirestore.instance;
    final set = <String>{};

    for (var i = 0; i < divisions.length; i += 10) {
      final end = math.min(i + 10, divisions.length);
      final chunk = divisions.sublist(i, end);
      final qs = await fs
          .collection('areas')
          .where('division', whereIn: chunk)
          .get(const GetOptions(source: Source.server));


      for (final d in qs.docs) {
        final name = (d.data()['name'] ?? '').toString().trim();
        if (name.isNotEmpty) set.add(name);
      }
    }
    return set.toList()..sort();
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchAreasForDivision(
    String division,
  ) async {
    final qs = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get(const GetOptions(source: Source.server));


    return qs;
  }

  Future<List<String>> _fetchAreaNamesForDivision(String division) async {
    final snapshot = await _fetchAreasForDivision(division);
    return snapshot.docs
        .map((doc) => (doc.data()['name'] ?? '').toString().trim())
        .where((area) => area.isNotEmpty)
        .toSet()
        .toList()
      ..sort();
  }

  Future<String?> _fetchEnglishNameByArea(String division, String area) async {
    final docId = '${division.trim()}-${area.trim()}';
    try {
      final snap = await FirebaseFirestore.instance
          .collection('areas')
          .doc(docId)
          .get(const GetOptions(source: Source.server));


      final data = snap.data();
      final englishName = (data?['englishName'] ?? '').toString().trim();
      return englishName.isEmpty ? null : englishName;
    } catch (_) {
      return null;
    }
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchUsersForArea(
    String area,
  ) async {
    final qs = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('areas', arrayContains: area)
        .get(const GetOptions(source: Source.server));


    return qs;
  }

  String _showDocId(String? division, String? area) {
    final d = (division ?? '').trim().isEmpty ? 'unknownDivision' : (division ?? '').trim();
    final a = (area ?? '').trim().isEmpty ? 'unknownArea' : (area ?? '').trim();
    return '$d-$a';
  }

  int _normalizeLimit(dynamic v) {
    if (v is int && v >= 0) return v;
    return 1 << 30;
  }


  String? _limitValueFromError(Object e, String key) {
    final raw = e.toString();
    final idx = raw.indexOf(key);
    if (idx < 0) return null;
    final rest = raw.substring(idx + key.length).trim();
    final end = rest.indexOf(RegExp(r'[^0-9]'));
    final value = end < 0 ? rest : rest.substring(0, end);
    return value.trim().isEmpty ? null : value.trim();
  }

  String? _activeLimitFromError(Object e) {
    return _limitValueFromError(e, 'ACTIVE_LIMIT_REACHED:');
  }

  String? _totalLimitFromError(Object e) {
    return _limitValueFromError(e, 'TOTAL_LIMIT_REACHED:');
  }

  Future<void> _showAccountLimitFailureDialog(
    Object e, {
    required String fallbackTitle,
    required String activeTitle,
    required String totalTitle,
  }) async {
    final activeLimit = _activeLimitFromError(e);
    if (activeLimit != null) {
      await StatusDialog.showFailure(
        context,
        title: activeTitle,
        description:
            '선택한 지역의 활성 계정 한도에 도달했습니다. 활성 계정은 최대 ${activeLimit}개까지만 사용할 수 있습니다. 기존 활성 계정을 비활성화하거나 리밋 설정에서 활성 한도를 늘린 뒤 다시 시도하세요.',
      );
      return;
    }

    final totalLimit = _totalLimitFromError(e);
    if (totalLimit != null) {
      await StatusDialog.showFailure(
        context,
        title: totalTitle,
        description:
            '선택한 지역의 전체 계정 생성 한도에 도달했습니다. 활성 계정과 비활성 계정을 합쳐 최대 ${totalLimit}개까지만 생성할 수 있습니다. 기존 계정을 삭제하거나 리밋 설정에서 전체 한도를 늘린 뒤 다시 시도하세요.',
      );
      return;
    }

    await StatusDialog.showFailure(
      context,
      title: fallbackTitle,
      description: '계정 정보를 저장하는 중 문제가 발생했습니다. 입력값과 네트워크 상태를 확인한 뒤 다시 시도하세요.',
    );
  }

  int? _asInt(dynamic v) => v is int ? v : null;

  Map<String, dynamic> _userAccountsPayload(Map<String, dynamic> data) {
    final payload = Map<String, dynamic>.from(data);
    payload.remove('id');
    payload.remove('isActive');
    payload.remove('disabledAt');
    payload.remove('updatedAt');
    return payload;
  }

  int _nonNegative(dynamic v) {
    final i = _asInt(v);
    if (i == null || i < 0) return 0;
    return i;
  }

  _UserAccountsTabCounts _countsFromMeta(Map<String, dynamic> data) {
    final active = _nonNegative(data['activeCount']);
    final inactiveRaw = _asInt(data['inactiveCount']);
    final totalRaw = _asInt(data['totalCount']);
    var inactive = inactiveRaw == null || inactiveRaw < 0 ? 0 : inactiveRaw;
    if ((inactiveRaw == null || inactiveRaw < 0) && totalRaw != null && totalRaw >= active) {
      inactive = totalRaw - active;
    }
    return _UserAccountsTabCounts(activeCount: active, inactiveCount: inactive);
  }

  bool _metaNeedsCountCompute(Map<String, dynamic> data, bool strict) {
    if (strict) return true;
    final active = _asInt(data['activeCount']);
    final inactive = _asInt(data['inactiveCount']);
    final total = _asInt(data['totalCount']);
    if (active == null || active < 0) return true;
    if (inactive == null || inactive < 0) return true;
    if (total == null || total < 0) return true;
    return total != active + inactive;
  }

  Future<_UserAccountsTabCounts> _syncAccountCounts({
    required DocumentReference<Map<String, dynamic>> showDocRef,
    required String division,
    required String area,
    required bool strict,
  }) async {
    try {
      final metaSnap = await showDocRef.get(const GetOptions(source: Source.server));
      final meta = metaSnap.data() ?? <String, dynamic>{};


      if (!_metaNeedsCountCompute(meta, strict)) {
        return _countsFromMeta(meta);
      }

      final qs = await showDocRef.collection('users').get(const GetOptions(source: Source.server));
      var active = 0;
      var inactive = 0;
      for (final doc in qs.docs) {
        final data = doc.data();
        final isActive = (data['isActive'] as bool?) ?? true;
        if (isActive) {
          active += 1;
        } else {
          inactive += 1;
        }
      }
      final counts = _UserAccountsTabCounts(activeCount: active, inactiveCount: inactive);


      await showDocRef.set(
        <String, dynamic>{
          'division': division,
          'area': area,
          ...counts.toMap(),
          'updatedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );


      return counts;
    } catch (_) {
      return const _UserAccountsTabCounts(activeCount: 0, inactiveCount: 0);
    }
  }

  Future<void> _saveChanges(
    String oldId,
    Map<String, dynamic> oldData,
    Map<String, dynamic> newData,
  ) async {
    String firstListValue(Map<String, dynamic> data, String key, String fallback) {
      final list = List.from(data[key] ?? const []);
      if (list.isEmpty) return fallback;
      final value = list.first.toString().trim();
      return value.isEmpty ? fallback : value;
    }

    final phone = (oldData['phone'] ?? '').toString();
    final String newArea = firstListValue(newData, 'areas', 'default');
    final String newDivision = firstListValue(newData, 'divisions', 'unknownDivision');
    final String oldArea = firstListValue(oldData, 'areas', newArea);
    final String oldDivision = firstListValue(oldData, 'divisions', newDivision);
    final String newId = '$phone-$newArea';
    final String oldShowId = _showDocId(oldDivision, oldArea);
    final String newShowId = _showDocId(newDivision, newArea);
    final bool idChanged = oldId != newId;
    final bool showChanged = oldShowId != newShowId;
    final bool moved = idChanged || showChanged;

    final fs = FirebaseFirestore.instance;
    final oldShowDocRef = fs.collection('user_accounts_show').doc(oldShowId);
    final newShowDocRef = fs.collection('user_accounts_show').doc(newShowId);
    final oldShowUserDocRef = oldShowDocRef.collection('users').doc(oldId);
    final newShowUserDocRef = newShowDocRef.collection('users').doc(newId);

    try {
      await _syncAccountCounts(
        showDocRef: newShowDocRef,
        division: newDivision,
        area: newArea,
        strict: true,
      );
      if (moved) {
        await _syncAccountCounts(
          showDocRef: oldShowDocRef,
          division: oldDivision,
          area: oldArea,
          strict: true,
        );
      }

      await fs.runTransaction((tx) async {
        final oldRef = fs.collection('user_accounts').doc(oldId);
        final newRef = fs.collection('user_accounts').doc(newId);

        final oldSnap = await tx.get(oldRef);
        if (!oldSnap.exists) {
          throw Exception('원본 계정이 존재하지 않습니다.');
        }

        if (idChanged) {
          final newSnap = await tx.get(newRef);
            if (newSnap.exists) {
            throw Exception('동일 ID가 이미 존재합니다: $newId');
          }
        }

        final newShowSnap = await tx.get(newShowDocRef);
        final newShowData = newShowSnap.data() ?? <String, dynamic>{};
        final newCounts0 = _countsFromMeta(newShowData);
        final newActiveLimit = _normalizeLimit(newShowData['activeLimit']);
        final newTotalLimit = _normalizeLimit(newShowData['totalLimit']);

        final newShowUserSnap = await tx.get(newShowUserDocRef);
        final newShowUserData = newShowUserSnap.data() ?? <String, dynamic>{};
        final newShowUserExists = newShowUserSnap.exists;
        final newShowUserActive = (newShowUserData['isActive'] as bool?) ?? false;

        final payload = _userAccountsPayload(newData)
          ..['createdAt'] = oldSnap.data()?['createdAt'] ?? FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();

        if (!moved) {
          final targetActive = newShowUserExists
              ? newShowUserActive
              : ((newData['isActive'] as bool?) ?? true);
          var counts1 = newCounts0;
          if (!newShowUserExists) {
            if (newCounts0.totalCount >= newTotalLimit) {
              throw StateError('TOTAL_LIMIT_REACHED:$newTotalLimit');
            }
            if (targetActive && newCounts0.activeCount >= newActiveLimit) {
              throw StateError('ACTIVE_LIMIT_REACHED:$newActiveLimit');
            }
            counts1 = _UserAccountsTabCounts(
              activeCount: newCounts0.activeCount + (targetActive ? 1 : 0),
              inactiveCount: newCounts0.inactiveCount + (targetActive ? 0 : 1),
            );
          }

          final showPayload = Map<String, dynamic>.from(newData)
            ..remove('id')
            ..['createdAt'] = newShowUserData['createdAt'] ?? oldSnap.data()?['createdAt'] ?? FieldValue.serverTimestamp()
            ..['updatedAt'] = FieldValue.serverTimestamp()
            ..['isActive'] = targetActive;
          showPayload['disabledAt'] = targetActive
              ? FieldValue.delete()
              : (newShowUserData['disabledAt'] ?? FieldValue.serverTimestamp());

          tx.update(oldRef, payload);
          tx.set(
            newShowDocRef,
            <String, dynamic>{
              'division': newDivision,
              'area': newArea,
              ...counts1.toMap(),
              'updatedAt': FieldValue.serverTimestamp(),
            },
            SetOptions(merge: true),
          );
          tx.set(newShowUserDocRef, showPayload, SetOptions(merge: true));
          return;
        }

        final oldShowSnap = await tx.get(oldShowDocRef);
        final oldShowData = oldShowSnap.data() ?? <String, dynamic>{};
        final oldCounts0 = _countsFromMeta(oldShowData);

        final oldShowUserSnap = await tx.get(oldShowUserDocRef);
        final oldShowUserData = oldShowUserSnap.data() ?? <String, dynamic>{};
        final oldShowUserExists = oldShowUserSnap.exists;
        final oldShowUserActive = (oldShowUserData['isActive'] as bool?) ?? false;
        final targetActive = oldShowUserExists
            ? oldShowUserActive
            : (newShowUserExists ? newShowUserActive : ((newData['isActive'] as bool?) ?? true));

        final oldActiveDelta = oldShowUserExists && oldShowUserActive ? -1 : 0;
        final oldInactiveDelta = oldShowUserExists && !oldShowUserActive ? -1 : 0;
        final newActiveDelta = targetActive
            ? (newShowUserExists && newShowUserActive ? 0 : 1)
            : (newShowUserExists && newShowUserActive ? -1 : 0);
        final newInactiveDelta = targetActive
            ? (newShowUserExists && !newShowUserActive ? -1 : 0)
            : (newShowUserExists && !newShowUserActive ? 0 : 1);
        final newTotalDelta = newShowUserExists ? 0 : 1;

        if (newTotalDelta > 0 && newCounts0.totalCount >= newTotalLimit) {
          throw StateError('TOTAL_LIMIT_REACHED:$newTotalLimit');
        }
        if (newActiveDelta > 0 && newCounts0.activeCount >= newActiveLimit) {
          throw StateError('ACTIVE_LIMIT_REACHED:$newActiveLimit');
        }

        final oldCounts1 = _UserAccountsTabCounts(
          activeCount: (oldCounts0.activeCount + oldActiveDelta) < 0 ? 0 : oldCounts0.activeCount + oldActiveDelta,
          inactiveCount: (oldCounts0.inactiveCount + oldInactiveDelta) < 0 ? 0 : oldCounts0.inactiveCount + oldInactiveDelta,
        );
        final newCounts1 = _UserAccountsTabCounts(
          activeCount: (newCounts0.activeCount + newActiveDelta) < 0 ? 0 : newCounts0.activeCount + newActiveDelta,
          inactiveCount: (newCounts0.inactiveCount + newInactiveDelta) < 0 ? 0 : newCounts0.inactiveCount + newInactiveDelta,
        );

        final showPayload = Map<String, dynamic>.from(newData)
          ..remove('id')
          ..['createdAt'] = oldShowUserData['createdAt'] ?? newShowUserData['createdAt'] ?? oldSnap.data()?['createdAt'] ?? FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp()
          ..['isActive'] = targetActive;
        showPayload['disabledAt'] = targetActive
            ? FieldValue.delete()
            : (oldShowUserData['disabledAt'] ?? newShowUserData['disabledAt'] ?? FieldValue.serverTimestamp());

        if (idChanged) {
          tx.set(newRef, payload);
          tx.delete(oldRef);
        } else {
          tx.update(oldRef, payload);
        }

        if (oldShowUserExists) {
          tx.delete(oldShowUserDocRef);
        }
        tx.set(newShowUserDocRef, showPayload, SetOptions(merge: true));
        tx.set(
          newShowDocRef,
          <String, dynamic>{
            'division': newDivision,
            'area': newArea,
            ...newCounts1.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        tx.set(
          oldShowDocRef,
          <String, dynamic>{
            'division': oldDivision,
            'area': oldArea,
            ...oldCounts1.toMap(),
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
      });


      if (!mounted) return;

      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.userAccountSaveSuccess,
      );

      if (!mounted) return;

      setState(() {
        _editedUsers.remove(oldId);
        _refreshTick++;
      });
    } catch (e) {
      debugPrint('❌ 계정 저장 실패: $e');
      if (!mounted) return;

      await _showAccountLimitFailureDialog(
        e,
        fallbackTitle: StatusDialog.userAccountSaveFailed,
        activeTitle: '계정 저장 불가',
        totalTitle: '계정 저장 불가',
      );
    }
  }

  Future<void> _openCreateDialog(List<String> divisionList) async {
    if (_creating) return;

    final draft = await showDialog<_CreateUserAccountDraft>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => _CreateUserAccountDialog(
        divisionList: divisionList,
        roleList: _roles,
        initialDivision: widget.selectedDivision,
        initialArea: widget.selectedArea,
        fetchAreasForDivision: _fetchAreaNamesForDivision,
      ),
    );

    if (draft == null) return;
    await _createAccount(draft);
  }

  Future<void> _createAccount(_CreateUserAccountDraft draft) async {
    if (_creating) return;

    setState(() => _creating = true);

    final fs = FirebaseFirestore.instance;
    final id = draft.documentId;
    final showId = _showDocId(draft.division, draft.area);
    final userRef = fs.collection('user_accounts').doc(id);
    final showDocRef = fs.collection('user_accounts_show').doc(showId);
    final showUserDocRef = showDocRef.collection('users').doc(id);

    try {
      final englishName = await _fetchEnglishNameByArea(draft.division, draft.area) ?? draft.area;
      await _syncAccountCounts(
        showDocRef: showDocRef,
        division: draft.division,
        area: draft.area,
        strict: true,
      );

      await fs.runTransaction((tx) async {
        final userSnap = await tx.get(userRef);
        if (userSnap.exists) {
          throw Exception('동일 ID가 이미 존재합니다: $id');
        }

        final showSnap = await tx.get(showDocRef);
        final showData = showSnap.data() ?? <String, dynamic>{};
        final activeLimit = _normalizeLimit(showData['activeLimit']);
        final totalLimit = _normalizeLimit(showData['totalLimit']);
        final counts = _countsFromMeta(showData);

        if (counts.activeCount >= activeLimit) {
          throw StateError('ACTIVE_LIMIT_REACHED:$activeLimit');
        }
        if (counts.totalCount >= totalLimit) {
          throw StateError('TOTAL_LIMIT_REACHED:$totalLimit');
        }

        final accountMap = draft.toUserAccountsMap(englishName)
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();

        final showMap = draft.toShowUserMap(englishName)
          ..['createdAt'] = FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();

        tx.set(userRef, accountMap);
        tx.set(
          showDocRef,
          <String, dynamic>{
            'division': draft.division,
            'area': draft.area,
            'activeCount': counts.activeCount + 1,
            'inactiveCount': counts.inactiveCount,
            'totalCount': counts.totalCount + 1,
            'updatedAt': FieldValue.serverTimestamp(),
          },
          SetOptions(merge: true),
        );
        tx.set(showUserDocRef, showMap, SetOptions(merge: true));
      });


      if (!mounted) return;

      if (widget.selectedDivision != draft.division) {
        widget.onDivisionChanged(draft.division);
      }
      if (widget.selectedArea != draft.area) {
        widget.onAreaChanged(draft.area);
      }

      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.userAccountSaveSuccess,
      );

      if (!mounted) return;
      setState(() => _refreshTick++);
    } catch (e) {
      debugPrint('❌ 계정 생성 실패: $e');
      if (!mounted) return;

      await _showAccountLimitFailureDialog(
        e,
        fallbackTitle: StatusDialog.userAccountSaveFailed,
        activeTitle: '계정 생성 불가',
        totalTitle: '계정 생성 불가',
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Widget _buildCreateButton({required List<String> divisionList}) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _creating ? null : () => _openCreateDialog(divisionList),
        icon: _creating
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.person_add_alt_1),
        label: Text(_creating ? '계정 생성 중' : '신규 계정 생성'),
      ),
    );
  }

  Widget _buildUserList({required List<String> divisionList}) {
    return Expanded(
      child: widget.selectedArea == null
          ? const Center(child: Text('지역을 선택하세요.'))
          : FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
              key: ValueKey<String>('${widget.selectedArea}-$_refreshTick'),
              future: _fetchUsersForArea(widget.selectedArea!),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                  return const Center(child: Text('해당 지역에 계정이 없습니다.'));
                }

                final docs = snapshot.data!.docs;
                return ListView.builder(
                  itemCount: docs.length,
                  itemBuilder: (context, index) {
                    final doc = docs[index];
                    final data = doc.data();
                    final id = doc.id;
                    final base = _editedUsers[id] ?? _copyUser(data);
                    final updated = _copyUser(base);

                    return Card(
                      margin: const EdgeInsets.symmetric(vertical: 6),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${updated['name']} ($id)',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...(updated['divisions'] as List<String>).map((division) {
                                  return InputChip(
                                    label: Text(division),
                                    onDeleted: () {
                                      setState(() {
                                        final list = List<String>.from(updated['divisions']);
                                        list.remove(division);
                                        updated['divisions'] = list;
                                        _editedUsers[id] = _copyUser(updated);
                                      });
                                    },
                                  );
                                }),
                                ActionChip(
                                  label: const Text('+ 추가'),
                                  onPressed: () async {
                                    final toAdd = await showDialog<String>(
                                      context: context,
                                      builder: (_) => SimpleDialog(
                                        title: const Text('Division 추가'),
                                        children: divisionList
                                            .where((d) => !(updated['divisions'] as List).contains(d))
                                            .map(
                                              (d) => SimpleDialogOption(
                                                onPressed: () => Navigator.pop(context, d),
                                                child: Text(d),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    );

                                    if (toAdd != null) {
                                      setState(() {
                                        final list = List<String>.from(updated['divisions']);
                                        list.add(toAdd);
                                        updated['divisions'] = list;
                                        _editedUsers[id] = _copyUser(updated);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                ...(updated['areas'] as List<String>).map((area) {
                                  return InputChip(
                                    label: Text(area),
                                    onDeleted: () {
                                      setState(() {
                                        final list = List<String>.from(updated['areas']);
                                        list.remove(area);
                                        updated['areas'] = list;
                                        _editedUsers[id] = _copyUser(updated);
                                      });
                                    },
                                  );
                                }),
                                ActionChip(
                                  label: const Text('+ 추가'),
                                  onPressed: () async {
                                    final areas = await getAreasByDivisions(
                                      List<String>.from(updated['divisions']),
                                    );
                                    if (!mounted) return;
                                    final toAdd = await showDialog<String>(
                                      context: context,
                                      builder: (_) => SimpleDialog(
                                        title: const Text('Area 추가'),
                                        children: areas
                                            .where((a) => !(updated['areas'] as List).contains(a))
                                            .map(
                                              (a) => SimpleDialogOption(
                                                onPressed: () => Navigator.pop(context, a),
                                                child: Text(a),
                                              ),
                                            )
                                            .toList(),
                                      ),
                                    );

                                    if (toAdd != null) {
                                      setState(() {
                                        final list = List<String>.from(updated['areas']);
                                        list.add(toAdd);
                                        updated['areas'] = list;
                                        _editedUsers[id] = _copyUser(updated);
                                      });
                                    }
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                const Text('Role: '),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: _roles.contains(updated['role']) ? updated['role'] : _roles.last,
                                    items: _roles
                                        .map(
                                          (role) => DropdownMenuItem(
                                            value: role,
                                            child: Text(role),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          updated['role'] = val;
                                          _editedUsers[id] = _copyUser(updated);
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            if ((updated['modes'] as List<String>).isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text("허용 모드: ${(updated['modes'] as List<String>).join(', ')}"),
                            ],
                            if ((updated['position'] ?? '').toString().trim().isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text("직책: ${updated['position']}"),
                            ],
                            const SizedBox(height: 12),
                            ElevatedButton.icon(
                              onPressed: _savingIds.contains(id)
                                  ? null
                                  : () async {
                                      setState(() => _savingIds.add(id));
                                      await _saveChanges(id, data, updated);
                                      if (!mounted) return;
                                      setState(() => _savingIds.remove(id));
                                    },
                              icon: const Icon(Icons.save),
                              label: const Text('저장'),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<String>>(
        key: ValueKey<int>(_refreshTick),
        future: fetchDivisions(),
        builder: (context, divisionSnapshot) {
          if (divisionSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!divisionSnapshot.hasData || divisionSnapshot.data!.isEmpty) {
            return const Text('등록된 회사가 없습니다.');
          }

          final divisionList = divisionSnapshot.data!;
          final selectedDivision = divisionList.contains(widget.selectedDivision) ? widget.selectedDivision : null;

          return Column(
            children: [
              DropdownButtonFormField<String>(
                value: selectedDivision,
                items: divisionList
                    .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                    .toList(),
                onChanged: (value) async {
                  widget.onDivisionChanged(value);
                  widget.onAreaChanged(null);
                },
                decoration: const InputDecoration(labelText: '회사 선택'),
              ),
              const SizedBox(height: 12),
              selectedDivision == null
                  ? const Text('회사를 먼저 선택하세요.')
                  : FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                      future: _fetchAreasForDivision(selectedDivision),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                          return const Text('등록된 지역이 없습니다.');
                        }

                        final areas = snapshot.data!.docs
                            .map((e) => (e.data()['name'] ?? '').toString().trim())
                            .where((area) => area.isNotEmpty)
                            .toSet()
                            .toList()
                          ..sort();

                        return DropdownButtonFormField<String>(
                          value: areas.contains(widget.selectedArea) ? widget.selectedArea : null,
                          items: areas
                              .map(
                                (area) => DropdownMenuItem(
                                  value: area,
                                  child: Text(area),
                                ),
                              )
                              .toList(),
                          onChanged: widget.onAreaChanged,
                          decoration: const InputDecoration(labelText: '지역 선택'),
                        );
                      },
                    ),
              const SizedBox(height: 12),
              _buildCreateButton(divisionList: divisionList),
              const SizedBox(height: 12),
              _buildUserList(divisionList: divisionList),
            ],
          );
        },
      ),
    );
  }
}

class _CreateUserAccountDraft {
  _CreateUserAccountDraft({
    required this.name,
    required this.phone,
    required this.email,
    required this.password,
    required this.division,
    required this.area,
    required this.role,
    required this.modes,
    required this.position,
    required this.startTimeByWeekday,
    required this.endTimeByWeekday,
  });

  static const List<String> weekdays = <String>['월', '화', '수', '목', '금', '토', '일'];

  final String name;
  final String phone;
  final String email;
  final String password;
  final String division;
  final String area;
  final String role;
  final List<String> modes;
  final String position;
  final Map<String, TimeOfDay?> startTimeByWeekday;
  final Map<String, TimeOfDay?> endTimeByWeekday;

  String get documentId => '$phone-$area';

  Map<String, int>? _timeToMap(TimeOfDay? time) {
    if (time == null) return null;
    return <String, int>{'hour': time.hour, 'minute': time.minute};
  }

  TimeOfDay? _pickRepresentative(Map<String, TimeOfDay?> map) {
    final todayIndex = DateTime.now().weekday - 1;
    if (todayIndex >= 0 && todayIndex < weekdays.length) {
      final value = map[weekdays[todayIndex]];
      if (value != null) return value;
    }
    for (final day in weekdays) {
      final value = map[day];
      if (value != null) return value;
    }
    return null;
  }

  Map<String, dynamic> _encodeWeekdayMap(Map<String, TimeOfDay?> map) {
    final out = <String, dynamic>{};
    for (final day in weekdays) {
      out[day] = _timeToMap(map[day]);
    }
    return out;
  }

  Map<String, dynamic> toUserAccountsMap(String englishSelectedAreaName) {
    return <String, dynamic>{
      'areas': <String>[area],
      'currentArea': area,
      'divisions': <String>[division],
      'modes': modes,
      'email': email,
      'endTime': _timeToMap(_pickRepresentative(endTimeByWeekday)),
      'englishSelectedAreaName': englishSelectedAreaName,
      'fixedHolidays': const <String>[],
      'isSaved': false,
      'isSelected': false,
      'isWorking': false,
      'name': name,
      'password': password,
      'phone': phone,
      'position': position,
      'role': role,
      'selectedArea': area,
      'startTime': _timeToMap(_pickRepresentative(startTimeByWeekday)),
      'startTimeByWeekday': _encodeWeekdayMap(startTimeByWeekday),
      'endTimeByWeekday': _encodeWeekdayMap(endTimeByWeekday),
    };
  }

  Map<String, dynamic> toShowUserMap(String englishSelectedAreaName) {
    return <String, dynamic>{
      ...toUserAccountsMap(englishSelectedAreaName),
      'isActive': true,
    };
  }
}

class _CreateUserAccountDialog extends StatefulWidget {
  const _CreateUserAccountDialog({
    required this.divisionList,
    required this.roleList,
    required this.initialDivision,
    required this.initialArea,
    required this.fetchAreasForDivision,
  });

  final List<String> divisionList;
  final List<String> roleList;
  final String? initialDivision;
  final String? initialArea;
  final Future<List<String>> Function(String division) fetchAreasForDivision;

  @override
  State<_CreateUserAccountDialog> createState() => _CreateUserAccountDialogState();
}

class _CreateUserAccountDialogState extends State<_CreateUserAccountDialog> {
  static const List<String> _days = <String>['월', '화', '수', '목', '금', '토', '일'];
  static const List<String> _availableModes = <String>['single', 'double', 'triple', 'minor'];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final TextEditingController _positionController = TextEditingController();

  String? _selectedDivision;
  String? _selectedArea;
  String _selectedRole = 'fieldCommon';
  final Set<String> _selectedModes = <String>{'single'};
  Map<String, TimeOfDay?> _startByDay = <String, TimeOfDay?>{};
  Map<String, TimeOfDay?> _endByDay = <String, TimeOfDay?>{};
  List<String> _areaList = <String>[];
  bool _loadingAreas = false;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _selectedDivision = widget.divisionList.contains(widget.initialDivision)
        ? widget.initialDivision
        : (widget.divisionList.isNotEmpty ? widget.divisionList.first : null);
    _selectedRole = widget.roleList.contains('fieldCommon')
        ? 'fieldCommon'
        : (widget.roleList.isNotEmpty ? widget.roleList.last : 'fieldCommon');
    _passwordController.text = _generateRandomPassword();
    _startByDay = <String, TimeOfDay?>{
      for (final day in _days) day: (day == '토' || day == '일') ? null : const TimeOfDay(hour: 9, minute: 0),
    };
    _endByDay = <String, TimeOfDay?>{
      for (final day in _days) day: (day == '토' || day == '일') ? null : const TimeOfDay(hour: 18, minute: 0),
    };
    _loadAreas(keepInitialArea: true);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  String _generateRandomPassword() {
    final random = math.Random();
    return (10000 + random.nextInt(90000)).toString();
  }

  String _normalizedPhone() => _phoneController.text.replaceAll(RegExp(r'\D'), '').trim();

  String _documentIdPreview() {
    final phone = _normalizedPhone();
    final area = (_selectedArea ?? '').trim();
    if (phone.isEmpty || area.isEmpty) return '-';
    return '$phone-$area';
  }

  bool _isValidEmailLocalPart(String input) {
    return RegExp(r'^[a-zA-Z0-9._-]+$').hasMatch(input.trim());
  }

  int _toMinutes(TimeOfDay time) => time.hour * 60 + time.minute;

  String _formatTime(TimeOfDay? time) {
    if (time == null) return '--:--';
    return '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _loadAreas({bool keepInitialArea = false}) async {
    final division = _selectedDivision;
    if (division == null || division.trim().isEmpty) {
      setState(() {
        _areaList = <String>[];
        _selectedArea = null;
      });
      return;
    }

    setState(() => _loadingAreas = true);
    final areas = await widget.fetchAreasForDivision(division);
    if (!mounted) return;

    setState(() {
      _areaList = areas;
      final candidate = keepInitialArea ? widget.initialArea : _selectedArea;
      _selectedArea = areas.contains(candidate) ? candidate : (areas.isNotEmpty ? areas.first : null);
      _loadingAreas = false;
    });
  }

  Future<void> _pickTime(String day, {required bool isStart}) async {
    final current = isStart ? _startByDay[day] : _endByDay[day];
    final initial = current ?? (isStart ? const TimeOfDay(hour: 9, minute: 0) : const TimeOfDay(hour: 18, minute: 0));
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      helpText: isStart ? '$day 출근 시간' : '$day 퇴근 시간',
      confirmText: '확인',
      cancelText: '취소',
      builder: (ctx, child) {
        final mq = MediaQuery.of(ctx);
        return MediaQuery(
          data: mq.copyWith(alwaysUse24HourFormat: true),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;

    setState(() {
      _errorText = null;
      if (isStart) {
        _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = picked;
      } else {
        _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = picked;
      }
    });
  }

  void _clearDay(String day) {
    setState(() {
      _errorText = null;
      _startByDay = Map<String, TimeOfDay?>.of(_startByDay)..[day] = null;
      _endByDay = Map<String, TimeOfDay?>.of(_endByDay)..[day] = null;
    });
  }

  String? _validate() {
    final name = _nameController.text.trim();
    final phone = _normalizedPhone();
    final emailLocal = _emailController.text.trim();
    final password = _passwordController.text.trim();

    if (name.isEmpty) return '이름을 입력하세요';
    if (!RegExp(r'^\d{9,}$').hasMatch(phone)) return '전화번호를 숫자 9자리 이상으로 입력하세요';
    if (emailLocal.isEmpty || !_isValidEmailLocalPart(emailLocal)) return '이메일을 다시 확인하세요';
    if (password.isEmpty) return '비밀번호를 입력하세요';
    if ((_selectedDivision ?? '').trim().isEmpty) return '회사를 선택하세요';
    if ((_selectedArea ?? '').trim().isEmpty) return '지역을 선택하세요';
    if (_selectedModes.isEmpty) return '허용 모드를 1개 이상 선택하세요';

    var hasWorkingDay = false;
    for (final day in _days) {
      final start = _startByDay[day];
      final end = _endByDay[day];
      final hasStart = start != null;
      final hasEnd = end != null;
      if (hasStart != hasEnd) return '$day 요일의 출근/퇴근 시간을 모두 입력하세요';
      if (start != null && end != null) {
        hasWorkingDay = true;
        if (_toMinutes(start) > _toMinutes(end)) {
          return '$day 요일의 출근/퇴근 시간을 다시 확인하세요';
        }
      }
    }

    if (!hasWorkingDay) return '최소 1개 요일의 근무 시간을 입력하세요';
    return null;
  }

  void _submit() {
    final error = _validate();
    if (error != null) {
      setState(() => _errorText = error);
      return;
    }

    Navigator.of(context).pop(
      _CreateUserAccountDraft(
        name: _nameController.text.trim(),
        phone: _normalizedPhone(),
        email: '${_emailController.text.trim()}@gmail.com',
        password: _passwordController.text.trim(),
        division: _selectedDivision!.trim(),
        area: _selectedArea!.trim(),
        role: _selectedRole,
        modes: _selectedModes.toList(growable: false)..sort(),
        position: _positionController.text.trim(),
        startTimeByWeekday: Map<String, TimeOfDay?>.from(_startByDay),
        endTimeByWeekday: Map<String, TimeOfDay?>.from(_endByDay),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    TextInputType? keyboardType,
    bool readOnly = false,
    Widget? suffixIcon,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      readOnly: readOnly,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        suffixIcon: suffixIcon,
      ),
    );
  }

  Widget _buildModeSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('허용 모드', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _availableModes.map((mode) {
            final selected = _selectedModes.contains(mode);
            return FilterChip(
              label: Text(mode),
              selected: selected,
              onSelected: (value) {
                setState(() {
                  _errorText = null;
                  if (value) {
                    _selectedModes.add(mode);
                  } else {
                    _selectedModes.remove(mode);
                  }
                });
              },
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildWeekdayEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('요일별 근무 시간', style: TextStyle(fontWeight: FontWeight.w800)),
        const SizedBox(height: 8),
        for (final day in _days)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(day, style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    Expanded(
                      child: Text(
                        _startByDay[day] != null && _endByDay[day] != null
                            ? '${_formatTime(_startByDay[day])} ~ ${_formatTime(_endByDay[day])}'
                            : '휴무',
                      ),
                    ),
                    TextButton(
                      onPressed: () => _clearDay(day),
                      child: const Text('비우기'),
                    ),
                  ],
                ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(day, isStart: true),
                        icon: const Icon(Icons.login),
                        label: Text('출근 ${_formatTime(_startByDay[day])}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickTime(day, isStart: false),
                        icon: const Icon(Icons.logout),
                        label: Text('퇴근 ${_formatTime(_endByDay[day])}'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return AlertDialog(
      title: const Text('신규 계정 생성'),
      content: SizedBox(
        width: 560,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_errorText != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: cs.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _errorText!,
                    style: TextStyle(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
              ],
              _buildTextField(
                controller: _nameController,
                label: '이름',
                onChanged: (_) => setState(() => _errorText = null),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _phoneController,
                label: '전화번호',
                keyboardType: TextInputType.phone,
                onChanged: (_) => setState(() => _errorText = null),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emailController,
                label: '이메일 아이디(@gmail.com 제외)',
                keyboardType: TextInputType.emailAddress,
                onChanged: (_) => setState(() => _errorText = null),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _passwordController,
                label: '비밀번호',
                suffixIcon: IconButton(
                  tooltip: '비밀번호 재생성',
                  onPressed: () => setState(() => _passwordController.text = _generateRandomPassword()),
                  icon: const Icon(Icons.refresh),
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _selectedDivision,
                decoration: const InputDecoration(
                  labelText: '회사',
                  border: OutlineInputBorder(),
                ),
                items: widget.divisionList
                    .map((division) => DropdownMenuItem<String>(
                          value: division,
                          child: Text(division),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _errorText = null;
                    _selectedDivision = value;
                    _selectedArea = null;
                  });
                  _loadAreas();
                },
              ),
              const SizedBox(height: 12),
              _loadingAreas
                  ? const Center(child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(),
                    ))
                  : DropdownButtonFormField<String>(
                      value: _areaList.contains(_selectedArea) ? _selectedArea : null,
                      decoration: const InputDecoration(
                        labelText: '지역',
                        border: OutlineInputBorder(),
                      ),
                      items: _areaList
                          .map((area) => DropdownMenuItem<String>(
                                value: area,
                                child: Text(area),
                              ))
                          .toList(),
                      onChanged: (value) => setState(() {
                        _errorText = null;
                        _selectedArea = value;
                      }),
                    ),
              const SizedBox(height: 8),
              Text(
                '생성 문서 ID: ${_documentIdPreview()}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: widget.roleList.contains(_selectedRole) ? _selectedRole : widget.roleList.last,
                decoration: const InputDecoration(
                  labelText: 'Role',
                  border: OutlineInputBorder(),
                ),
                items: widget.roleList
                    .map((role) => DropdownMenuItem<String>(
                          value: role,
                          child: Text(role),
                        ))
                    .toList(),
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _errorText = null;
                    _selectedRole = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _positionController,
                label: '직책(선택)',
                onChanged: (_) => setState(() => _errorText = null),
              ),
              const SizedBox(height: 12),
              _buildModeSelector(),
              const SizedBox(height: 12),
              _buildWeekdayEditor(),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('취소'),
        ),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('생성'),
        ),
      ],
    );
  }
}
