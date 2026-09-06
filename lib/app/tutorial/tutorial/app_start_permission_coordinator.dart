import 'package:flutter/foundation.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart';
import 'package:permission_handler/permission_handler.dart';

class AppStartPermissionCoordinator extends ChangeNotifier {
  AppStartPermissionCoordinator();

  final Map<int, PermissionStatus> _statuses = <int, PermissionStatus>{};
  bool? _overlayGranted;
  bool _busy = false;

  bool get busy => _busy;

  PermissionStatus? statusForStep(int step) => _statuses[step];

  bool? get overlayGranted => _overlayGranted;

  Future<void> refreshSteps(Iterable<int> steps) async {
    for (final step in steps) {
      await refreshStep(step);
    }
  }

  Future<void> refreshStep(int step) async {
    switch (step) {
      case 2:
        _statuses[step] = await Permission.notification.status;
        break;
      case 3:
        _statuses[step] = await Permission.locationWhenInUse.status;
        break;
      case 4:
        _statuses[step] = await Permission.ignoreBatteryOptimizations.status;
        break;
      case 5:
        _statuses[step] = await Permission.camera.status;
        break;
      case 6:
        _overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
        break;
      case 7:
        _statuses[step] = await Permission.microphone.status;
        break;
      default:
        throw ArgumentError.value(step, 'step');
    }
    notifyListeners();
  }

  Future<bool> requestStep(int step) async {
    if (_busy) return isGranted(step);
    _busy = true;
    notifyListeners();
    try {
      switch (step) {
        case 2:
          _statuses[step] = await Permission.notification.request();
          break;
        case 3:
          _statuses[step] = await Permission.locationWhenInUse.request();
          break;
        case 4:
          _statuses[step] =
              await Permission.ignoreBatteryOptimizations.request();
          break;
        case 5:
          _statuses[step] = await Permission.camera.request();
          break;
        case 6:
          final alreadyGranted =
              await FlutterOverlayWindow.isPermissionGranted();
          if (!alreadyGranted) {
            await FlutterOverlayWindow.requestPermission();
          }
          _overlayGranted = await FlutterOverlayWindow.isPermissionGranted();
          break;
        case 7:
          _statuses[step] = await Permission.microphone.request();
          break;
        default:
          throw ArgumentError.value(step, 'step');
      }
      notifyListeners();
      return isGranted(step);
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  Future<void> openSettingsForStep(int step) async {
    if (step == 6) {
      await FlutterOverlayWindow.requestPermission();
      return;
    }
    await openAppSettings();
  }

  bool isGranted(int step) {
    if (step == 6) return _overlayGranted == true;
    return _statuses[step]?.isGranted == true;
  }

  bool shouldOpenSettings(int step) {
    if (step == 6) return true;
    final status = _statuses[step];
    if (status == null) return false;
    return status.isPermanentlyDenied || status.isRestricted;
  }

  String statusLabel(int step) {
    if (step == 6) {
      if (_overlayGranted == null) return '확인 전';
      return _overlayGranted == true ? '허용됨' : '미허용';
    }
    final status = _statuses[step];
    if (status == null) return '확인 전';
    if (status.isGranted) return '허용됨';
    if (status.isPermanentlyDenied) return '영구 거부됨';
    if (status.isDenied) return '거부됨';
    if (status.isRestricted) return '제한됨';
    if (status.isLimited) return '제한됨';
    return status.toString();
  }

  String actionLabel(int step) {
    if (isGranted(step)) return '설정 완료';
    if (step == 6) return '시스템 설정 열기';
    if (shouldOpenSettings(step)) return '설정에서 허용';
    return '권한 허용';
  }
}
