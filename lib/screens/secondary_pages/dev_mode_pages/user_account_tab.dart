import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class UserAccountsTab extends StatefulWidget {
  final List<String> divisionList;
  final String? selectedDivision;
  final String? selectedArea;
  final ValueChanged<String?> onDivisionChanged;
  final ValueChanged<String?> onAreaChanged;

  const UserAccountsTab({
    super.key,
    required this.divisionList,
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

  Future<List<String>> getAreasByDivision(String division) async {
    final snapshot = await FirebaseFirestore.instance
        .collection('areas')
        .where('division', isEqualTo: division)
        .get();
    return snapshot.docs.map((doc) => doc['name'] as String).toSet().toList();
  }

  Future<void> _saveChanges(String oldId, Map<String, dynamic> oldData, Map<String, dynamic> newData) async {
    final phone = oldData['phone'];
    final newArea = newData['area'] as String;
    final newId = '$phone-$newArea';

    final firestore = FirebaseFirestore.instance;

    await firestore.collection('user_accounts').doc(newId).set(newData);
    await firestore.collection('user_accounts').doc(oldId).delete();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('✅ ${newData['name']} 정보 저장 완료')),
    );

    setState(() {
      _editedUsers.remove(oldId);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          DropdownButtonFormField<String>(
            value: widget.divisionList.contains(widget.selectedDivision)
                ? widget.selectedDivision
                : null,
            items: widget.divisionList
                .map((div) => DropdownMenuItem(value: div, child: Text(div)))
                .toList(),
            onChanged: widget.onDivisionChanged,
            decoration: const InputDecoration(labelText: '회사 선택'),
          ),
          const SizedBox(height: 12),
          widget.selectedDivision == null
              ? const Text('회사를 먼저 선택하세요.')
              : FutureBuilder<QuerySnapshot>(
            future: FirebaseFirestore.instance
                .collection('areas')
                .where('division', isEqualTo: widget.selectedDivision)
                .get(),
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
                value: areas.contains(widget.selectedArea)
                    ? widget.selectedArea
                    : null,
                items: areas
                    .map((area) =>
                    DropdownMenuItem(value: area, child: Text(area)))
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
                  .where('area', isEqualTo: widget.selectedArea)
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

                    final String name = data['name'] ?? '';
                    final String phone = data['phone'] ?? '';
                    final String currentDivision = data['division'] ?? '';
                    final String currentArea = data['area'] ?? '';
                    final String currentRole = data['role'] ?? 'fielder';

                    final updated = _editedUsers[id] ?? {
                      'name': name,
                      'phone': phone,
                      'email': data['email'],
                      'password': data['password'],
                      'division': currentDivision,
                      'area': currentArea,
                      'role': currentRole,
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
                            Text('$name ($id)', style: const TextStyle(fontWeight: FontWeight.bold)),
                            const SizedBox(height: 8),

                            // Division
                            Row(
                              children: [
                                const Text('Division: '),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: widget.divisionList.contains(updated['division'])
                                        ? updated['division']
                                        : null,
                                    items: widget.divisionList
                                        .map((div) => DropdownMenuItem(
                                      value: div,
                                      child: Text(div),
                                    ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _editedUsers[id] = {
                                            ...updated,
                                            'division': val,
                                          };
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),

                            // Area
                            FutureBuilder<List<String>>(
                              future: getAreasByDivision(updated['division']),
                              builder: (context, areaSnapshot) {
                                if (!areaSnapshot.hasData) return const SizedBox.shrink();
                                final areaList = areaSnapshot.data!.toSet().toList();
                                return Row(
                                  children: [
                                    const Text('Area: '),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: DropdownButton<String>(
                                        isExpanded: true,
                                        value: areaList.contains(updated['area'])
                                            ? updated['area']
                                            : null,
                                        items: areaList
                                            .map((area) => DropdownMenuItem(
                                          value: area,
                                          child: Text(area),
                                        ))
                                            .toList(),
                                        onChanged: (val) {
                                          if (val != null) {
                                            setState(() {
                                              _editedUsers[id] = {
                                                ...updated,
                                                'area': val,
                                              };
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                  ],
                                );
                              },
                            ),
                            const SizedBox(height: 8),

                            // Role
                            Row(
                              children: [
                                const Text('Role: '),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: roles.contains(updated['role']) ? updated['role'] : null,
                                    items: roles
                                        .map((role) => DropdownMenuItem(
                                      value: role,
                                      child: Text(role),
                                    ))
                                        .toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() {
                                          _editedUsers[id] = {
                                            ...updated,
                                            'role': val,
                                          };
                                        });
                                      }
                                    },
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),

                            // 저장 버튼
                            ElevatedButton.icon(
                              onPressed: () {
                                _saveChanges(id, data, updated);
                              },
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
      ),
    );
  }
}
