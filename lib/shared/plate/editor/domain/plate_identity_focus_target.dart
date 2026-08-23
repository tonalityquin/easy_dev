enum PlateIdentityFocusTarget {
  front,
  middle,
  back,
}

PlateIdentityFocusTarget? resolveNextPlateIdentityFocusTarget({
  required String front,
  required String middle,
  required String back,
  required int requiredFrontLength,
}) {
  final normalizedFront = front.trim();
  final normalizedMiddle = middle.trim();
  final normalizedBack = back.trim();

  if (normalizedFront.length != requiredFrontLength ||
      !RegExp(r'^\d+$').hasMatch(normalizedFront)) {
    return PlateIdentityFocusTarget.front;
  }
  if (!RegExp(r'^[가-힣]$').hasMatch(normalizedMiddle)) {
    return PlateIdentityFocusTarget.middle;
  }
  if (!RegExp(r'^\d{4}$').hasMatch(normalizedBack)) {
    return PlateIdentityFocusTarget.back;
  }
  return null;
}

PlateIdentityFocusTarget resolvePlateIdentityFocusTarget({
  required String front,
  required String middle,
  required String back,
  required int requiredFrontLength,
  PlateIdentityFocusTarget fallback = PlateIdentityFocusTarget.front,
}) {
  return resolveNextPlateIdentityFocusTarget(
        front: front,
        middle: middle,
        back: back,
        requiredFrontLength: requiredFrontLength,
      ) ??
      fallback;
}

class PlateIdentityAuxiliaryResult {
  const PlateIdentityAuxiliaryResult({
    required this.applied,
    required this.focusTarget,
    this.middleSuggestions = const <String>[],
    this.requiresManualCompletion = false,
  });

  final bool applied;
  final PlateIdentityFocusTarget focusTarget;
  final List<String> middleSuggestions;
  final bool requiresManualCompletion;
}
