import 'package:flutter/material.dart';
import '../preview_package/parking_status_preview_card_area.dart';
import 'real_time_tab_controller.dart';

class RealTimeStatusPreviewBody extends StatefulWidget {
  final RealTimeTabController controller;
  final String area;
  final List<ParkingStatusOverlaySpec> overlay;

  const RealTimeStatusPreviewBody({
    super.key,
    required this.controller,
    required this.area,
    required this.overlay,
  });

  @override
  State<RealTimeStatusPreviewBody> createState() =>
      _RealTimeStatusPreviewBodyState();
}

class _RealTimeStatusPreviewBodyState extends State<RealTimeStatusPreviewBody>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    widget.controller.bind(_refreshFromUser);
  }

  @override
  void dispose() {
    widget.controller.unbind();
    super.dispose();
  }

  Future<void> _refreshFromUser() async {}

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return ParkingStatusPreviewCardArea(
      area: widget.area,
      overlay: widget.overlay,
    );
  }
}