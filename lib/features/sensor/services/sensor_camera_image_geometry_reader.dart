import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:image/image.dart' as img;

class SensorCameraCalibrationFrame {
  const SensorCameraCalibrationFrame({
    required this.bytes,
    required this.size,
  });

  final Uint8List bytes;
  final Size size;
}

class SensorCameraImageGeometryReader {
  const SensorCameraImageGeometryReader();

  Future<Size> readOrientedSize(String path) async {
    final oriented = await _readOrientedImage(path);
    return Size(
      oriented.width.toDouble(),
      oriented.height.toDouble(),
    );
  }

  Future<SensorCameraCalibrationFrame> readOrientedFrame(String path) async {
    final oriented = await _readOrientedImage(path);
    final bytes = Uint8List.fromList(
      img.encodeJpg(oriented, quality: 92),
    );
    return SensorCameraCalibrationFrame(
      bytes: bytes,
      size: Size(
        oriented.width.toDouble(),
        oriented.height.toDouble(),
      ),
    );
  }

  Future<img.Image> _readOrientedImage(String path) async {
    final bytes = await File(path).readAsBytes();
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw StateError('Sensor camera image decode failed.');
    }
    final oriented = img.bakeOrientation(decoded);
    if (oriented.width <= 0 || oriented.height <= 0) {
      throw StateError('Sensor camera image size is invalid.');
    }
    return oriented;
  }
}
