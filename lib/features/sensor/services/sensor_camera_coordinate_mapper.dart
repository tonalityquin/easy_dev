import 'dart:ui';

import 'package:flutter/painting.dart';

class SensorCameraCoordinateMapper {
  const SensorCameraCoordinateMapper({
    required this.previewSourceSize,
    required this.viewportSize,
    this.cameraImageSize,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
  });

  final Size previewSourceSize;
  final Size viewportSize;
  final Size? cameraImageSize;
  final BoxFit fit;
  final Alignment alignment;

  bool get isPreviewValid =>
      previewSourceSize.width > 0 &&
      previewSourceSize.height > 0 &&
      viewportSize.width > 0 &&
      viewportSize.height > 0;

  bool get isCameraImageReady {
    final size = cameraImageSize;
    return isPreviewValid &&
        size != null &&
        size.width > 0 &&
        size.height > 0;
  }

  bool get isValid => isCameraImageReady;

  Rect get previewSourceRect {
    if (!isPreviewValid) return Rect.zero;
    final fitted = applyBoxFit(fit, previewSourceSize, viewportSize);
    return alignment.inscribe(
      fitted.source,
      Offset.zero & previewSourceSize,
    );
  }

  Rect get viewportDestinationRect {
    if (!isPreviewValid) return Rect.zero;
    final fitted = applyBoxFit(fit, previewSourceSize, viewportSize);
    return alignment.inscribe(
      fitted.destination,
      Offset.zero & viewportSize,
    );
  }

  Rect get cameraImageSourceRectForPreview {
    final imageSize = cameraImageSize;
    if (!isCameraImageReady || imageSize == null) return Rect.zero;
    final fitted = applyBoxFit(BoxFit.cover, imageSize, previewSourceSize);
    return alignment.inscribe(
      fitted.source,
      Offset.zero & imageSize,
    );
  }

  Rect get previewDestinationRectForCameraImage {
    final imageSize = cameraImageSize;
    if (!isCameraImageReady || imageSize == null) return Rect.zero;
    final fitted = applyBoxFit(BoxFit.cover, imageSize, previewSourceSize);
    return alignment.inscribe(
      fitted.destination,
      Offset.zero & previewSourceSize,
    );
  }

  Offset viewportToPreviewNormalized(Offset viewportPoint) {
    if (!isPreviewValid) return const Offset(0.5, 0.5);
    final source = previewSourceRect;
    final destination = viewportDestinationRect;
    if (source.isEmpty || destination.isEmpty) {
      return const Offset(0.5, 0.5);
    }
    final destinationX =
        ((viewportPoint.dx - destination.left) / destination.width)
            .clamp(0.0, 1.0)
            .toDouble();
    final destinationY =
        ((viewportPoint.dy - destination.top) / destination.height)
            .clamp(0.0, 1.0)
            .toDouble();
    final previewX = source.left + source.width * destinationX;
    final previewY = source.top + source.height * destinationY;
    return Offset(
      (previewX / previewSourceSize.width).clamp(0.0, 1.0).toDouble(),
      (previewY / previewSourceSize.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  Offset previewNormalizedToViewport(Offset previewPoint) {
    if (!isPreviewValid) return Offset.zero;
    final source = previewSourceRect;
    final destination = viewportDestinationRect;
    if (source.isEmpty || destination.isEmpty) return Offset.zero;
    final previewX = previewPoint.dx * previewSourceSize.width;
    final previewY = previewPoint.dy * previewSourceSize.height;
    final sourceX = (previewX - source.left) / source.width;
    final sourceY = (previewY - source.top) / source.height;
    return Offset(
      destination.left + destination.width * sourceX,
      destination.top + destination.height * sourceY,
    );
  }

  Offset previewNormalizedToCameraImageNormalized(Offset previewPoint) {
    final imageSize = cameraImageSize;
    if (!isCameraImageReady || imageSize == null) {
      return const Offset(0.5, 0.5);
    }
    final source = cameraImageSourceRectForPreview;
    final destination = previewDestinationRectForCameraImage;
    if (source.isEmpty || destination.isEmpty) {
      return const Offset(0.5, 0.5);
    }
    final previewX = previewPoint.dx * previewSourceSize.width;
    final previewY = previewPoint.dy * previewSourceSize.height;
    final destinationX = ((previewX - destination.left) / destination.width)
        .clamp(0.0, 1.0)
        .toDouble();
    final destinationY = ((previewY - destination.top) / destination.height)
        .clamp(0.0, 1.0)
        .toDouble();
    final cameraX = source.left + source.width * destinationX;
    final cameraY = source.top + source.height * destinationY;
    return Offset(
      (cameraX / imageSize.width).clamp(0.0, 1.0).toDouble(),
      (cameraY / imageSize.height).clamp(0.0, 1.0).toDouble(),
    );
  }

  Offset viewportToCameraImageNormalized(Offset viewportPoint) {
    return previewNormalizedToCameraImageNormalized(
      viewportToPreviewNormalized(viewportPoint),
    );
  }

  Offset cameraImageNormalizedToPreviewNormalized(Offset cameraPoint) {
    final imageSize = cameraImageSize;
    if (!isCameraImageReady || imageSize == null) return Offset.zero;
    final source = cameraImageSourceRectForPreview;
    final destination = previewDestinationRectForCameraImage;
    if (source.isEmpty || destination.isEmpty) return Offset.zero;
    final cameraX = cameraPoint.dx * imageSize.width;
    final cameraY = cameraPoint.dy * imageSize.height;
    final sourceX = (cameraX - source.left) / source.width;
    final sourceY = (cameraY - source.top) / source.height;
    final previewX = destination.left + destination.width * sourceX;
    final previewY = destination.top + destination.height * sourceY;
    return Offset(
      previewX / previewSourceSize.width,
      previewY / previewSourceSize.height,
    );
  }

  Offset cameraImageNormalizedToViewport(Offset cameraPoint) {
    if (!isCameraImageReady) return Offset.zero;
    return previewNormalizedToViewport(
      cameraImageNormalizedToPreviewNormalized(cameraPoint),
    );
  }

  Rect cameraImageNormalizedRectToViewport(Rect cameraRect) {
    if (!isCameraImageReady || cameraRect.isEmpty) return Rect.zero;
    final topLeft = cameraImageNormalizedToViewport(cameraRect.topLeft);
    final bottomRight =
        cameraImageNormalizedToViewport(cameraRect.bottomRight);
    final mapped = Rect.fromLTRB(
      topLeft.dx < bottomRight.dx ? topLeft.dx : bottomRight.dx,
      topLeft.dy < bottomRight.dy ? topLeft.dy : bottomRight.dy,
      topLeft.dx < bottomRight.dx ? bottomRight.dx : topLeft.dx,
      topLeft.dy < bottomRight.dy ? bottomRight.dy : topLeft.dy,
    );
    return mapped.intersect(Offset.zero & viewportSize);
  }

  List<Offset> cameraImageNormalizedPolygonToViewport(
    List<Offset> cameraPoints,
  ) {
    if (!isCameraImageReady) return const <Offset>[];
    return cameraPoints
        .map(cameraImageNormalizedToViewport)
        .toList(growable: false);
  }

  List<Offset> viewportPolygonToCameraImageNormalized(
    List<Offset> viewportPoints,
  ) {
    if (!isCameraImageReady) return const <Offset>[];
    return viewportPoints
        .map(viewportToCameraImageNormalized)
        .toList(growable: false);
  }

  bool isCameraImagePointVisible(Offset cameraPoint) {
    if (!isCameraImageReady) return false;
    final viewportPoint = cameraImageNormalizedToViewport(cameraPoint);
    return (Offset.zero & viewportSize).contains(viewportPoint);
  }

  Map<String, Object?> diagnostics() {
    final previewSource = previewSourceRect;
    final viewportDestination = viewportDestinationRect;
    final cameraSource = cameraImageSourceRectForPreview;
    final previewDestination = previewDestinationRectForCameraImage;
    final imageSize = cameraImageSize;
    return <String, Object?>{
      'fit': fit.name,
      'geometryReady': isCameraImageReady,
      'previewSourceWidth': previewSourceSize.width.round(),
      'previewSourceHeight': previewSourceSize.height.round(),
      'cameraWidth': imageSize?.width.round(),
      'cameraHeight': imageSize?.height.round(),
      'viewportWidth': viewportSize.width.round(),
      'viewportHeight': viewportSize.height.round(),
      'previewCropLeft': previewSource.left.toStringAsFixed(2),
      'previewCropTop': previewSource.top.toStringAsFixed(2),
      'previewCropWidth': previewSource.width.toStringAsFixed(2),
      'previewCropHeight': previewSource.height.toStringAsFixed(2),
      'viewportDestinationLeft': viewportDestination.left.toStringAsFixed(2),
      'viewportDestinationTop': viewportDestination.top.toStringAsFixed(2),
      'viewportDestinationWidth': viewportDestination.width.toStringAsFixed(2),
      'viewportDestinationHeight': viewportDestination.height.toStringAsFixed(2),
      'cameraCropLeft': cameraSource.left.toStringAsFixed(2),
      'cameraCropTop': cameraSource.top.toStringAsFixed(2),
      'cameraCropWidth': cameraSource.width.toStringAsFixed(2),
      'cameraCropHeight': cameraSource.height.toStringAsFixed(2),
      'cameraPreviewDestinationLeft': previewDestination.left.toStringAsFixed(2),
      'cameraPreviewDestinationTop': previewDestination.top.toStringAsFixed(2),
      'cameraPreviewDestinationWidth': previewDestination.width.toStringAsFixed(2),
      'cameraPreviewDestinationHeight': previewDestination.height.toStringAsFixed(2),
    };
  }
}
