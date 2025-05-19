import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../repositories/plate/plate_repository.dart';
import '../../states/area/area_state.dart';
import '../../models/location_model.dart';

class ParkingLocationDialog extends StatelessWidget {
  final TextEditingController locationController;
  final Function(String) onLocationSelected;

  const ParkingLocationDialog({
    super.key,
    required this.locationController,
    required this.onLocationSelected,
  });

  @override
  Widget build(BuildContext context) {
    final currentArea = context.watch<AreaState>().currentArea;

    return ScaleTransitionDialog(
      child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: const [
            Icon(Icons.location_on, color: Colors.green),
            SizedBox(width: 8),
            Text('주차 구역 선택', style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        content: FutureBuilder<List<LocationModel>>(
          future: context.read<PlateRepository>().getAvailableLocations(currentArea),
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }

            if (!snapshot.hasData || snapshot.data!.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(8.0),
                child: Text('사용 가능한 주차 구역이 없습니다.'),
              );
            }

            final locations = snapshot.data!;
            return SizedBox(
              width: double.maxFinite,
              height: 300,
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: locations.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final location = locations[index];
                  final isComposite = location.type == 'composite';

                  final displayName = isComposite
                      ? '${location.parent} - ${location.locationName}'
                      : location.locationName;

                  return ListTile(
                    title: Text(displayName),
                    leading: Icon(
                      isComposite ? Icons.layers : Icons.place,
                      color: isComposite ? Colors.blueAccent : Colors.grey,
                    ),
                    onTap: () {
                      onLocationSelected(displayName); // 전달도 수정된 이름으로
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            );
          },
        ),
      ),
    );
  }
}

class ScaleTransitionDialog extends StatefulWidget {
  final Widget child;

  const ScaleTransitionDialog({super.key, required this.child});

  @override
  State<ScaleTransitionDialog> createState() => _ScaleTransitionDialogState();
}

class _ScaleTransitionDialogState extends State<ScaleTransitionDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}
