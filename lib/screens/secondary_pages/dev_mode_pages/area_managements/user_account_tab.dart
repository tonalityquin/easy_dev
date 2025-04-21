import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

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

  Future<List<String>> fetchDivisions() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .get(const GetOptions(source: Source.server));

    return snapshot.docs
        .map((doc) => doc['division'] as String)
        .toSet()
        .toList();
  }

  Future<List<String>> getAreasByDivisions(List<String> divisions) async {
    if (divisions.isEmpty) return [];

    final areaQuery = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', whereIn: divisions)
        .get(const GetOptions(source: Source.server));

    return areaQuery.docs
        .map((doc) => doc['name'] as String)
        .toSet()
        .toList();
  }

  Future<void> _saveChanges(String oldId, Map<String, dynamic> oldData, Map<String, dynamic> newData) async {
    final phone = oldData['phone'];
    final newArea = (newData['areas'] as List).isNotEmpty ? newData['areas'][0] : 'default';
    final newId = '$phone-$newArea';

    try {
      if (newId != oldId) {
        await FirebaseFirestore.instance.collection('user_accounts').doc(newId).set(newData);
        await FirebaseFirestore.instance.collection('user_accounts').doc(oldId).delete();
      } else {
        await FirebaseFirestore.instance.collection('user_accounts').doc(oldId).update(newData);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('✅ ${newData['name']} 정보 저장 완료')),
      );

      setState(() {
        _editedUsers.remove(oldId);
      });
    } catch (e) {
      debugPrint('❌ 계정 저장 실패: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ 저장 실패: $e')),
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
                  if (value != null) {
                    final areas = await getAreasByDivisions([value]);
                    if (areas.isNotEmpty) {
                      widget.onAreaChanged(areas.first);
                    } else {
                      widget.onAreaChanged(null);
                    }
                  }
                },
                decoration: const InputDecoration(labelText: '회사 선택'),
              ),
              const SizedBox(height: 12),
              selectedDivision == null
                  ? const Text('회사를 먼저 선택하세요.')
                  : FutureBuilder<QuerySnapshot>(
                future: FirebaseFirestore.instance
                    .collection('areas')
                    .where('division', isEqualTo: selectedDivision)
                    .get(const GetOptions(source: Source.server)),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                    return const Text('등록된 지역이 없습니다.');
                  }

                  final areas = snapshot.data!.docs
                      .map((e) => e['name'] as String)
                      .toSet()
                      .toList();

                  return DropdownButtonFormField<String>(
                    value: areas.contains(widget.selectedArea) ? widget.selectedArea : null,
                    items: areas
                        .map((area) => DropdownMenuItem(value: area, child: Text(area)))
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
                    : FutureBuilder<QuerySnapshot>(
                  future: FirebaseFirestore.instance
                      .collection('user_accounts')
                      .where('areas', arrayContains: widget.selectedArea)
                      .get(),
                  builder: (context, snapshot) {
                    if (snapshot.connectionState == ConnectionState.waiting) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
                      return const Center(child: Text('해당 지역에 계정이 없습니다.'));
                    }

                    final docs = snapshot.data!.docs;

                    return ListView(
                      children: docs.map((doc) {
                        final data = doc.data() as Map<String, dynamic>;
                        final id = doc.id;

                        final updated = _editedUsers[id] ?? {
                          'name': data['name'],
                          'phone': data['phone'],
                          'email': data['email'],
                          'password': data['password'],
                          'divisions': List<String>.from(data['divisions'] ?? []),
                          'areas': List<String>.from(data['areas'] ?? []),
                          'role': data['role'] ?? 'fielder',
                          'isWorking': data['isWorking'] ?? false,
                          'createdAt': data['createdAt'],
                        };

                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('${updated['name']} ($id)',
                                    style: const TextStyle(fontWeight: FontWeight.bold)),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  children: [
                                    ...(updated['divisions'] as List<String>).map((division) {
                                      return InputChip(
                                        label: Text(division),
                                        onDeleted: () {
                                          setState(() {
                                            updated['divisions'].remove(division);
                                            _editedUsers[id] = Map.from(updated);
                                          });
                                        },
                                      );
                                    }),
                                    ActionChip(
                                      label: const Text('+ 추가'),
                                      onPressed: () async {
                                        final snapshot = await FirebaseFirestore.instance
                                            .collection('areas')
                                            .get(const GetOptions(source: Source.server));
                                        final allDivisions = snapshot.docs
                                            .map((doc) => doc['division'] as String)
                                            .toSet()
                                            .toList();

                                        final toAdd = await showDialog<String>(
                                          context: context,
                                          builder: (_) => SimpleDialog(
                                            title: const Text('Division 추가'),
                                            children: allDivisions
                                                .where((d) => !(updated['divisions'] as List).contains(d))
                                                .map((d) => SimpleDialogOption(
                                              onPressed: () => Navigator.pop(context, d),
                                              child: Text(d),
                                            ))
                                                .toList(),
                                          ),
                                        );

                                        if (toAdd != null) {
                                          setState(() {
                                            updated['divisions'].add(toAdd);
                                            _editedUsers[id] = Map.from(updated);
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
                                    ...(updated['areas'] as List<String>).map((area) {
                                      return InputChip(
                                        label: Text(area),
                                        onDeleted: () {
                                          setState(() {
                                            updated['areas'].remove(area);
                                            _editedUsers[id] = Map.from(updated);
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
                                        final toAdd = await showDialog<String>(
                                          context: context,
                                          builder: (_) => SimpleDialog(
                                            title: const Text('Area 추가'),
                                            children: areas
                                                .where((a) => !(updated['areas'] as List).contains(a))
                                                .map((a) => SimpleDialogOption(
                                              onPressed: () => Navigator.pop(context, a),
                                              child: Text(a),
                                            ))
                                                .toList(),
                                          ),
                                        );

                                        if (toAdd != null) {
                                          setState(() {
                                            updated['areas'].add(toAdd);
                                            _editedUsers[id] = Map.from(updated);
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
                                        value: roles.contains(updated['role']) ? updated['role'] : roles.first,
                                        items: roles
                                            .map((role) => DropdownMenuItem(
                                          value: role,
                                          child: Text(role),
                                        ))
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              updated['role'] = val;
                                              _editedUsers[id] = Map.from(updated);
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                ElevatedButton.icon(
                                  onPressed: () => _saveChanges(id, data, updated),
                                  icon: const Icon(Icons.save),
                                  label: const Text('저장'),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
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
