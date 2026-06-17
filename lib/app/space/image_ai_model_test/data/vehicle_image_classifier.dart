import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

class VehicleImageClassifierResult {
  const VehicleImageClassifierResult({
    required this.success,
    required this.label,
    required this.displayLabel,
    required this.confidence,
    required this.probabilities,
    required this.rawScores,
    required this.logs,
    required this.topLabel,
    required this.topDisplayLabel,
    required this.topConfidence,
    required this.secondLabel,
    required this.secondDisplayLabel,
    required this.secondConfidence,
    required this.confidenceMargin,
    required this.minAutoConfidence,
    required this.minAutoMargin,
    required this.autoAcceptable,
    this.instabilityReason,
    this.failureReason,
  });

  final bool success;
  final String? label;
  final String? displayLabel;
  final double? confidence;
  final Map<String, double> probabilities;
  final Map<String, double> rawScores;
  final List<String> logs;
  final String? topLabel;
  final String? topDisplayLabel;
  final double? topConfidence;
  final String? secondLabel;
  final String? secondDisplayLabel;
  final double? secondConfidence;
  final double? confidenceMargin;
  final double minAutoConfidence;
  final double minAutoMargin;
  final bool autoAcceptable;
  final String? instabilityReason;
  final String? failureReason;

  static const VehicleImageClassifierResult empty = VehicleImageClassifierResult(
    success: false,
    label: null,
    displayLabel: null,
    confidence: null,
    probabilities: {},
    rawScores: {},
    logs: [],
    topLabel: null,
    topDisplayLabel: null,
    topConfidence: null,
    secondLabel: null,
    secondDisplayLabel: null,
    secondConfidence: null,
    confidenceMargin: null,
    minAutoConfidence: VehicleImageClassifier.minAutoConfidence,
    minAutoMargin: VehicleImageClassifier.minAutoMargin,
    autoAcceptable: false,
    instabilityReason: null,
    failureReason: null,
  );
}

class VehicleImageClassifier {
  VehicleImageClassifier._internal();

  static final VehicleImageClassifier instance = VehicleImageClassifier._internal();

  static const String modelAssetPath = 'assets/models/vehicle_front/vehicle_classifier.tflite';
  static const String labelsAssetPath = 'assets/models/vehicle_front/labels.txt';
  static const int inputSize = 224;
  static const double minAutoConfidence = 0.80;
  static const double minAutoMargin = 0.20;
  static const String inputMode = 'vehicle_front_224_rgb_float32_0_255';
  static const List<String> fallbackLabels = ['genesis_g80', 'kia_carnival'];
  static const Map<String, String> displayLabels = {
    'genesis_g80': '제네시스 G80',
    'kia_carnival': '기아 카니발',
  };

  Interpreter? _interpreter;
  List<String>? _labels;
  bool _loading = false;

  Future<List<String>> warmUp() async {
    final logs = <String>[];
    await _ensureLoaded(logs);
    return logs;
  }

  Future<VehicleImageClassifierResult> classifyFile(String path) async {
    final logs = <String>[];

    try {
      await _ensureLoaded(logs);
      final interpreter = _interpreter;
      final labels = _labels ?? fallbackLabels;
      if (interpreter == null) {
        return _failureResult(
          logs: logs,
          failureReason: 'interpreter_not_loaded',
        );
      }

      final file = File(path);
      if (!file.existsSync()) {
        logs.add('차량 이미지 파일 없음 path=$path');
        return _failureResult(
          logs: logs,
          failureReason: 'image_file_not_found',
        );
      }

      final bytes = await file.readAsBytes();
      logs.add('차량 이미지 로드 mode=$inputMode bytes=${bytes.length}');
      final decoded = img.decodeImage(bytes);
      if (decoded == null) {
        logs.add('차량 이미지 디코딩 실패');
        return _failureResult(
          logs: logs,
          failureReason: 'image_decode_failed',
        );
      }

      final oriented = img.bakeOrientation(decoded);
      final resized = img.copyResize(
        oriented,
        width: inputSize,
        height: inputSize,
        interpolation: img.Interpolation.linear,
      );
      logs.add('차량 전처리 inputMode=$inputMode resize=${inputSize}x$inputSize channels=RGB valueRange=0..255');

      final input = List.generate(
        1,
        (_) => List.generate(
          inputSize,
          (y) => List.generate(
            inputSize,
            (x) {
              final pixel = resized.getPixel(x, y);
              return [
                pixel.r.toDouble(),
                pixel.g.toDouble(),
                pixel.b.toDouble(),
              ];
            },
          ),
        ),
      );

      final output = List.generate(1, (_) => List<double>.filled(labels.length, 0.0));
      interpreter.run(input, output);
      final rawValues = output.first;
      final normalizedValues = _normalizeScores(rawValues);

      final rawScores = <String, double>{};
      final probabilities = <String, double>{};
      for (var i = 0; i < labels.length; i++) {
        rawScores[labels[i]] = i < rawValues.length ? rawValues[i] : 0.0;
        probabilities[labels[i]] = i < normalizedValues.length ? normalizedValues[i] : 0.0;
      }

      final ranked = probabilities.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final top = ranked.isEmpty ? null : ranked.first;
      final second = ranked.length < 2 ? null : ranked[1];
      final topLabel = top?.key;
      final topConfidence = top?.value;
      final secondLabel = second?.key;
      final secondConfidence = second?.value;
      final margin = topConfidence == null || secondConfidence == null ? null : topConfidence - secondConfidence;
      final accepted = topConfidence != null &&
          margin != null &&
          topConfidence >= minAutoConfidence &&
          margin >= minAutoMargin;
      final instabilityReason = accepted
          ? null
          : _buildInstabilityReason(
              topConfidence: topConfidence,
              margin: margin,
            );
      final displayLabel = topLabel == null ? null : displayLabels[topLabel] ?? topLabel;
      final secondDisplayLabel = secondLabel == null ? null : displayLabels[secondLabel] ?? secondLabel;
      logs.add(
        '차량 추론 완료 top1=${topLabel ?? '-'} ${_formatProbability(topConfidence)} '
        'top2=${secondLabel ?? '-'} ${_formatProbability(secondConfidence)} '
        'margin=${_formatProbability(margin)} minConfidence=${_formatProbability(minAutoConfidence)} '
        'minMargin=${_formatProbability(minAutoMargin)} autoAcceptable=$accepted '
        'reason=${instabilityReason ?? '-'} probabilities=${_formatProbabilities(probabilities)}',
      );

      return VehicleImageClassifierResult(
        success: true,
        label: topLabel,
        displayLabel: displayLabel,
        confidence: topConfidence,
        probabilities: Map<String, double>.unmodifiable(probabilities),
        rawScores: Map<String, double>.unmodifiable(rawScores),
        logs: logs,
        topLabel: topLabel,
        topDisplayLabel: displayLabel,
        topConfidence: topConfidence,
        secondLabel: secondLabel,
        secondDisplayLabel: secondDisplayLabel,
        secondConfidence: secondConfidence,
        confidenceMargin: margin,
        minAutoConfidence: minAutoConfidence,
        minAutoMargin: minAutoMargin,
        autoAcceptable: accepted,
        instabilityReason: instabilityReason,
      );
    } catch (e) {
      logs.add('차량 추론 오류 $e');
      return _failureResult(
        logs: logs,
        failureReason: e.toString(),
      );
    }
  }

  Future<void> _ensureLoaded(List<String> logs) async {
    if (_interpreter != null && _labels != null) {
      return;
    }
    if (_loading) {
      while (_loading) {
        await Future<void>.delayed(const Duration(milliseconds: 30));
      }
      return;
    }

    _loading = true;
    try {
      final modelData = await rootBundle.load(modelAssetPath);
      final modelBytes = modelData.buffer.asUint8List(
        modelData.offsetInBytes,
        modelData.lengthInBytes,
      );
      _interpreter = Interpreter.fromBuffer(modelBytes);
      logs.add('차량 모델 로드 완료 asset=$modelAssetPath bytes=${modelBytes.length}');

      final labelText = await rootBundle.loadString(labelsAssetPath);
      final labels = labelText
          .split(RegExp(r'\r?\n'))
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      _labels = labels.isEmpty ? fallbackLabels : labels;
      logs.add('차량 라벨 로드 완료 labels=${_labels!.join(', ')}');
    } finally {
      _loading = false;
    }
  }

  VehicleImageClassifierResult _failureResult({
    required List<String> logs,
    required String failureReason,
  }) {
    return VehicleImageClassifierResult(
      success: false,
      label: null,
      displayLabel: null,
      confidence: null,
      probabilities: const {},
      rawScores: const {},
      logs: logs,
      topLabel: null,
      topDisplayLabel: null,
      topConfidence: null,
      secondLabel: null,
      secondDisplayLabel: null,
      secondConfidence: null,
      confidenceMargin: null,
      minAutoConfidence: minAutoConfidence,
      minAutoMargin: minAutoMargin,
      autoAcceptable: false,
      failureReason: failureReason,
    );
  }

  List<double> _normalizeScores(List<double> raw) {
    if (raw.isEmpty) {
      return const [];
    }

    final allNonNegative = raw.every((value) => value >= 0);
    final sum = raw.fold<double>(0.0, (previous, value) => previous + value);
    if (allNonNegative && sum > 0.0 && sum <= 1.5) {
      return raw.map<double>((value) => value / sum).toList(growable: false);
    }

    final maxValue = raw.reduce((a, b) => a > b ? a : b);
    final expValues = raw
        .map<double>((value) => math.exp(value - maxValue).toDouble())
        .toList(growable: false);
    final expSum = expValues.fold<double>(
      0.0,
      (previous, value) => previous + value,
    );
    if (expSum <= 0.0) {
      return List<double>.filled(raw.length, 0.0);
    }
    return expValues
        .map<double>((value) => value / expSum)
        .toList(growable: false);
  }

  String _buildInstabilityReason({
    required double? topConfidence,
    required double? margin,
  }) {
    if (topConfidence == null || margin == null) {
      return 'vehicle_probability_unavailable';
    }
    final lowConfidence = topConfidence < minAutoConfidence;
    final lowMargin = margin < minAutoMargin;
    if (lowConfidence && lowMargin) {
      return 'vehicle_low_confidence_and_low_margin';
    }
    if (lowConfidence) {
      return 'vehicle_low_confidence';
    }
    if (lowMargin) {
      return 'vehicle_low_margin';
    }
    return 'vehicle_unstable_confidence';
  }

  String _formatProbabilities(Map<String, double> probabilities) {
    return probabilities.entries
        .map((e) => '${e.key}:${_formatProbability(e.value)}')
        .join(', ');
  }

  String _formatProbability(double? value) {
    if (value == null) return '-';
    return '${(value * 100).toStringAsFixed(1)}%';
  }
}
