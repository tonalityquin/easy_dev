import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../../widgets/navigation/secondary_role_navigation.dart';
import '../../../widgets/navigation/secondary_mini_navigation.dart';
import '../../../states/area_state.dart';
import 'location_management_pages/location_setting.dart';
import '../../../widgets/container/location_container.dart';

class LocationManagement extends StatefulWidget {
  const LocationManagement({Key? key}) : super(key: key);

  @override
  State<LocationManagement> createState() => _LocationManagementState();
}

class _LocationManagementState extends State<LocationManagement> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final List<Map<String, String>> _locations = [];
  final Map<String, bool> _selectedLocations = {};
  bool _isLoading = true;

  List<IconData> _navigationIcons = [
    Icons.add,
    Icons.circle,
    Icons.settings,
  ];

  /// Firestore에서 데이터 가져오기
  Future<void> _fetchLocations() async {
    try {
      final snapshot = await _firestore.collection('locations').get();
      if (snapshot.docs.isEmpty) {
        setState(() {
          _locations.clear();
          _selectedLocations.clear();
          _isLoading = false;
        });
        return;
      }

      final fetchedLocations = <Map<String, String>>[];
      final fetchedSelectedLocations = <String, bool>{};

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final id = doc.id;

        fetchedLocations.add({
          'id': id,
          'locationName': data['locationName'] ?? '',
          'area': data['area'] ?? '',
        });

        fetchedSelectedLocations[id] = data['isSelected'] == true;
      }

      setState(() {
        _locations
          ..clear()
          ..addAll(fetchedLocations);
        _selectedLocations
          ..clear()
          ..addAll(fetchedSelectedLocations);
        _updateIcons();
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching locations: $e');
      setState(() {
        _isLoading = false;
      });
    }
  }

  /// Firestore에 주차 구역 추가
  Future<void> _addLocation(String locationName, String area) async {
    try {
      final docRef = _firestore.collection('locations').doc(locationName);
      await docRef.set({
        'locationName': locationName,
        'area': area,
        'isSelected': false,
      });

      setState(() {
        _locations.add({
          'id': locationName,
          'locationName': locationName,
          'area': area,
        });
        _selectedLocations[locationName] = false;
        _updateIcons();
      });
    } catch (e) {
      debugPrint('Error adding location: $e');
    }
  }

  /// 선택 상태 토글
  Future<void> _toggleSelection(String id) async {
    final currentState = _selectedLocations[id] ?? false;
    try {
      // Firestore에서 상태 업데이트
      await _firestore.collection('locations').doc(id).update({
        'isSelected': !currentState,
      });

      // 상태 변경 및 아이콘 업데이트
      setState(() {
        _selectedLocations[id] = !currentState;
        _updateIcons();
      });
    } catch (e) {
      debugPrint('Error toggling selection: $e');
    }
  }

  /// 아이콘 상태 업데이트
  void _updateIcons() {
    if (_selectedLocations.values.contains(true)) {
      _navigationIcons = [Icons.lock, Icons.delete, Icons.edit];
    } else {
      _navigationIcons = [Icons.add, Icons.circle, Icons.settings];
    }
  }

  @override
  void initState() {
    super.initState();
    _fetchLocations();
  }

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea;

    // 현재 지역과 일치하는 데이터만 필터링
    final filteredLocations = _locations.where((location) => location['area'] == currentArea).toList();

    return Scaffold(
      appBar: const SecondaryRoleNavigation(),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : filteredLocations.isEmpty
              ? const Center(child: Text('No locations in this area.'))
              : ListView.builder(
                  itemCount: filteredLocations.length,
                  itemBuilder: (context, index) {
                    final location = filteredLocations[index];
                    final isSelected = _selectedLocations[location['id']] ?? false;
                    return LocationContainer(
                      location: location['locationName']!,
                      isSelected: isSelected,
                      onTap: () {
                        debugPrint('Tapped on location: ${location['locationName']}');
                        _toggleSelection(location['id']!);
                      },
                    );
                  },
                ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: _navigationIcons,
        onIconTapped: (index) {
          final selectedIds = _selectedLocations.keys.where((id) => _selectedLocations[id] == true).toList();

          if (_navigationIcons[index] == Icons.add) {
            showDialog(
              context: context,
              builder: (BuildContext dialogContext) {
                final currentArea = Provider.of<AreaState>(dialogContext, listen: false).currentArea;
                return LocationSetting(
                  onSave: (locationName) => _addLocation(locationName, currentArea),
                );
              },
            );
          } else if (_navigationIcons[index] == Icons.delete && selectedIds.isNotEmpty) {
            for (final id in selectedIds) {
              _firestore.collection('locations').doc(id).delete().then((_) {
                setState(() {
                  _locations.removeWhere((location) => location['id'] == id);
                  _selectedLocations.remove(id);
                  _updateIcons();
                });
              }).catchError((error) {
                debugPrint('Error deleting location: $error');
              });
            }
          }
        },
      ),
    );
  }
}
