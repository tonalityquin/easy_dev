import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate_repository.dart';
import '../../states/area_state.dart';

class ParkingLocationDialog extends StatelessWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const ParkingLocationDialog({
    Key? key,
    required this.locationController,
    required this.onLocationSelected,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea;
    return AlertDialog(
      title: const Text('주차 구역 선택'),
      content: FutureBuilder<List<String>>(
        future: context.read<PlateRepository>().getAvailableLocations(currentArea),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('사용 가능한 주차 구역이 없습니다.'));
          }
          final locations = snapshot.data!;
          return SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: locations.map((location) {
                return ListTile(
                  title: Text(location),
                  onTap: () {
                    onLocationSelected(location);
                    Navigator.pop(context);
                  },
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }
}
