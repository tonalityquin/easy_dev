import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../../../app/usage/usage_reporter.dart';
import '../../../../../app/utils/status_dialog.dart';

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
  final List<String> roles = ['dev', 'officer', 'fieldLeader', 'fielder'];
  final Map<String, Map<String, dynamic>> _editedUsers = {};
  final Set<String> _savingIds = {};

  Map<String, dynamic> _copyUser(Map<String, dynamic> d) => {
    'name': d['name'],
    'phone': d['phone'],
    'email': d['email'],
    'password': d['password'],
    'divisions': List<String>.from(d['divisions'] ?? const []),
    'areas': List<String>.from(d['areas'] ?? const []),
    'role': d['role'] ?? 'fielder',
    'isWorking': d['isWorking'] ?? false,
    'createdAt': d['createdAt'],
  };

  Future<List<String>> fetchDivisions() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .get(const GetOptions(source: Source.server));

    try {
      final n = snapshot.docs.isEmpty ? 1 : snapshot.docs.length;
      await UsageReporter.instance.report(
        area: 'unknown',
        action: 'read',
        n: n,
        source: 'UserAccountsTab.fetchDivisions.areas.get',
      );
    } catch (_) {}

    return snapshot.docs
        .map((doc) => doc['division'] as String)
        .toSet()
        .toList()
      ..sort();
  }

  Future<List<String>> getAreasByDivisions(List<String> divisions) async {
    if (divisions.isEmpty) return [];
    final fs = FirebaseFirestore.instance;
    final set = <String>{};

    for (var i = 0; i < divisions.length; i += 10) {
      final end = math.min(i + 10, divisions.length);
      final chunk = divisions.sublist(i, end);
      final qs = await fs
          .collection('areas')
          .where('division', whereIn: chunk)
          .get(const GetOptions(source: Source.server));

      try {
        final n = qs.docs.isEmpty ? 1 : qs.docs.length;
        await UsageReporter.instance.report(
          area: 'unknown',
          action: 'read',
          n: n,
          source: 'UserAccountsTab.getAreasByDivisions.chunk(${chunk.length})',
        );
      } catch (_) {}

      for (final d in qs.docs) {
        set.add(d['name'] as String);
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

    try {
      final n = qs.docs.isEmpty ? 1 : qs.docs.length;
      await UsageReporter.instance.report(
        area: 'unknown',
        action: 'read',
        n: n,
        source: 'UserAccountsTab._fetchAreasForDivision.get',
      );
    } catch (_) {}

    return qs;
  }

  Future<QuerySnapshot<Map<String, dynamic>>> _fetchUsersForArea(
      String area,
      ) async {
    final qs = await FirebaseFirestore.instance
        .collection('user_accounts')
        .where('areas', arrayContains: area)
        .get(const GetOptions(source: Source.server));

    try {
      final n = qs.docs.isEmpty ? 1 : qs.docs.length;
      await UsageReporter.instance.report(
        area: area,
        action: 'read',
        n: n,
        source: 'UserAccountsTab._fetchUsersForArea.get',
      );
    } catch (_) {}

    return qs;
  }

  Future<void> _saveChanges(
      String oldId,
      Map<String, dynamic> oldData,
      Map<String, dynamic> newData,
      ) async {
    final phone = oldData['phone'] as String;
    final List areas = List.from(newData['areas'] ?? const []);
    final String newArea = areas.isNotEmpty ? areas.first as String : 'default';
    final String newId = '$phone-$newArea';

    final fs = FirebaseFirestore.instance;
    bool didCreate = false;
    bool didUpdate = false;
    bool didDelete = false;
    int readOps = 0;

    try {
      await fs.runTransaction((tx) async {
        final oldRef = fs.collection('user_accounts').doc(oldId);
        final newRef = fs.collection('user_accounts').doc(newId);

        final oldSnap = await tx.get(oldRef);
        readOps += 1;
        if (!oldSnap.exists) {
          throw Exception('원본 계정이 존재하지 않습니다.');
        }

        final payload = Map<String, dynamic>.from(newData)
          ..['createdAt'] =
              oldSnap.data()?['createdAt'] ?? FieldValue.serverTimestamp()
          ..['updatedAt'] = FieldValue.serverTimestamp();

        if (newId == oldId) {
          tx.update(oldRef, payload);
          didUpdate = true;
        } else {
          final newSnap = await tx.get(newRef);
          readOps += 1;
          if (newSnap.exists) {
            throw Exception('동일 ID가 이미 존재합니다: $newId');
          }
          tx.set(newRef, payload);
          tx.delete(oldRef);
          didCreate = true;
          didDelete = true;
        }
      });

      try {
        if (readOps > 0) {
          await UsageReporter.instance.report(
            area: newArea,
            action: 'read',
            n: readOps,
            source: 'UserAccountsTab._saveChanges.tx.get',
          );
        }
        if (didUpdate) {
          await UsageReporter.instance.report(
            area: newArea,
            action: 'write',
            n: 1,
            source: 'UserAccountsTab._saveChanges.update',
          );
        }
        if (didCreate) {
          await UsageReporter.instance.report(
            area: newArea,
            action: 'write',
            n: 1,
            source: 'UserAccountsTab._saveChanges.create',
          );
        }
        if (didDelete) {
          await UsageReporter.instance.report(
            area: newArea,
            action: 'delete',
            n: 1,
            source: 'UserAccountsTab._saveChanges.deleteOld',
          );
        }
      } catch (_) {}

      if (!mounted) return;

      await StatusDialog.showSuccess(
        context,
        title: StatusDialog.userAccountSaveSuccess,
      );

      if (!mounted) return;

      setState(() {
        _editedUsers.remove(oldId);
      });
    } catch (e) {
      debugPrint('❌ 계정 저장 실패: $e');
      if (!mounted) return;

      await StatusDialog.showFailure(
        context,
        title: StatusDialog.userAccountSaveFailed,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<List<String>>(
        future: fetchDivisions(),
        builder: (context, divisionSnapshot) {
          if (divisionSnapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!divisionSnapshot.hasData || divisionSnapshot.data!.isEmpty) {
            return const Text('등록된 회사가 없습니다.');
          }

          final divisionList = divisionSnapshot.data!;
          final selectedDivision = divisionList.contains(widget.selectedDivision)
              ? widget.selectedDivision
              : null;

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
                    return const Center(
                      child: CircularProgressIndicator(),
                    );
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('등록된 지역이 없습니다.');
                  }

                  final areas = snapshot.data!.docs
                      .map((e) => e['name'] as String)
                      .toSet()
                      .toList()
                    ..sort();

                  return DropdownButtonFormField<String>(
                    value: areas.contains(widget.selectedArea)
                        ? widget.selectedArea
                        : null,
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
              Expanded(
                child: widget.selectedArea == null
                    ? const Center(child: Text('지역을 선택하세요.'))
                    : FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  future: _fetchUsersForArea(widget.selectedArea!),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(
                        child: Text('해당 지역에 계정이 없습니다.'),
                      );
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
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${updated['name']} ($id)',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ...(updated['divisions'] as List<String>)
                                        .map((division) {
                                      return InputChip(
                                        label: Text(division),
                                        onDeleted: () {
                                          setState(() {
                                            final list = List<String>.from(
                                              updated['divisions'],
                                            );
                                            list.remove(division);
                                            updated['divisions'] = list;
                                            _editedUsers[id] =
                                                _copyUser(updated);
                                          });
                                        },
                                      );
                                    }),
                                    ActionChip(
                                      label: const Text('+ 추가'),
                                      onPressed: () async {
                                        final allDivisions = divisionList;

                                        final toAdd = await showDialog<String>(
                                          context: context,
                                          builder: (_) => SimpleDialog(
                                            title: const Text('Division 추가'),
                                            children: allDivisions
                                                .where(
                                                  (d) => !(updated[
                                              'divisions'] as List)
                                                  .contains(d),
                                            )
                                                .map(
                                                  (d) => SimpleDialogOption(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                      context,
                                                      d,
                                                    ),
                                                child: Text(d),
                                              ),
                                            )
                                                .toList(),
                                          ),
                                        );

                                        if (toAdd != null) {
                                          setState(() {
                                            final list = List<String>.from(
                                              updated['divisions'],
                                            );
                                            list.add(toAdd);
                                            updated['divisions'] = list;
                                            _editedUsers[id] =
                                                _copyUser(updated);
                                          });
                                        }
                                      },
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ...(updated['areas'] as List<String>)
                                        .map((area) {
                                      return InputChip(
                                        label: Text(area),
                                        onDeleted: () {
                                          setState(() {
                                            final list = List<String>.from(
                                              updated['areas'],
                                            );
                                            list.remove(area);
                                            updated['areas'] = list;
                                            _editedUsers[id] =
                                                _copyUser(updated);
                                          });
                                        },
                                      );
                                    }),
                                    ActionChip(
                                      label: const Text('+ 추가'),
                                      onPressed: () async {
                                        final areas =
                                        await getAreasByDivisions(
                                          List<String>.from(
                                            updated['divisions'],
                                          ),
                                        );
                                        final toAdd = await showDialog<String>(
                                          context: context,
                                          builder: (_) => SimpleDialog(
                                            title: const Text('Area 추가'),
                                            children: areas
                                                .where(
                                                  (a) => !(updated['areas']
                                              as List)
                                                  .contains(a),
                                            )
                                                .map(
                                                  (a) => SimpleDialogOption(
                                                onPressed: () =>
                                                    Navigator.pop(
                                                      context,
                                                      a,
                                                    ),
                                                child: Text(a),
                                              ),
                                            )
                                                .toList(),
                                          ),
                                        );

                                        if (toAdd != null) {
                                          setState(() {
                                            final list = List<String>.from(
                                              updated['areas'],
                                            );
                                            list.add(toAdd);
                                            updated['areas'] = list;
                                            _editedUsers[id] =
                                                _copyUser(updated);
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
                                        value: roles.contains(updated['role'])
                                            ? updated['role']
                                            : roles.first,
                                        items: roles
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
                                              _editedUsers[id] =
                                                  _copyUser(updated);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
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
              ),
            ],
          );
        },
      ),
    );
  }
}
