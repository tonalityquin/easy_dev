import 'package:flutter/material.dart';
import 'offline_auth_service.dart';

/// 오프라인 모드 진입 게이트:
/// - 세션이 있으면 offlineHome 으로 즉시 이동
/// - 없으면 login으로 이동
class OfflineEntryGate extends StatefulWidget {
  const OfflineEntryGate({
    super.key,
    this.offlineHomeRoute,
    this.offlineHomeBuilder,
    this.loginRoute,
    this.loginBuilder,
  }) : assert(offlineHomeRoute != null || offlineHomeBuilder != null,
  'offlineHomeRoute 또는 offlineHomeBuilder 중 하나는 필요합니다.'),
        assert(loginRoute != null || loginBuilder != null,
        'loginRoute 또는 loginBuilder 중 하나는 필요합니다.');

  final String? offlineHomeRoute;
  final WidgetBuilder? offlineHomeBuilder;

  final String? loginRoute;
  final WidgetBuilder? loginBuilder;

  @override
  State<OfflineEntryGate> createState() => _OfflineEntryGateState();
}

class _OfflineEntryGateState extends State<OfflineEntryGate> {
  @override
  void initState() {
    super.initState();
    _decide();
  }

  Future<void> _decide() async {
    final has = await OfflineAuthService.instance.hasSession();
    if (!mounted) return;

    if (has) {
      if (widget.offlineHomeRoute != null) {
        Navigator.pushReplacementNamed(context, widget.offlineHomeRoute!);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: widget.offlineHomeBuilder!),
        );
      }
    } else {
      if (widget.loginRoute != null) {
        Navigator.pushReplacementNamed(context, widget.loginRoute!);
      } else {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: widget.loginBuilder!),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}
