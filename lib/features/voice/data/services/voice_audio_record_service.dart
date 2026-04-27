import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

class WorkinTalkinAudioRecordService {
  WorkinTalkinAudioRecordService() : _recorder = AudioRecorder();

  final AudioRecorder _recorder;
  final Uuid _uuid = const Uuid();

  Future<String> start() async {
    final hasPermission = await _recorder.hasPermission();
    if (!hasPermission) {
      throw Exception('마이크 권한이 허용되지 않았습니다.');
    }
    final directory = await getTemporaryDirectory();
    final path = '${directory.path}/${_uuid.v4()}.m4a';
    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: path,
    );
    return path;
  }

  Future<File?> stop() async {
    final path = await _recorder.stop();
    if (path == null) {
      return null;
    }
    return File(path);
  }

  Future<void> cancel() => _recorder.cancel();

  Future<void> dispose() => _recorder.dispose();
}
