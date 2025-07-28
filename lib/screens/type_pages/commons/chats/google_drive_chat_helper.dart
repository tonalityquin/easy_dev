import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';

class GoogleDriveChatHelper {
  static const String _credentialsPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  // 🔁 캐시용 변수
  static List<Map<String, dynamic>>? _cachedChat;
  static DateTime? _lastReadTime;

  // 1. 인증용 클라이언트 생성
  static Future<AutoRefreshingAuthClient> _getClient() async {
    final jsonString = await rootBundle.loadString(_credentialsPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [drive.DriveApi.driveScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  // 2. chat.json 파일 읽기 (캐싱 적용)
  static Future<List<Map<String, dynamic>>> readChatJsonFile(String fileId) async {
    if (_cachedChat != null && _lastReadTime != null) {
      final duration = DateTime.now().difference(_lastReadTime!);
      if (duration.inSeconds < 5) {
        return _cachedChat!;
      }
    }

    final client = await _getClient();
    final api = drive.DriveApi(client);
    final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final content = await media.stream.transform(utf8.decoder).join();
    client.close();

    try {
      final decoded = json.decode(content);
      _cachedChat = List<Map<String, dynamic>>.from(decoded);
      _lastReadTime = DateTime.now();
      return _cachedChat!;
    } catch (e) {
      return [];
    }
  }

  // 3. 새 메시지를 추가하고 캐시 갱신
  static Future<void> appendChatMessageJson(String fileId, Map<String, dynamic> newMessage) async {
    final client = await _getClient();
    final api = drive.DriveApi(client);

    final oldMessages = await readChatJsonFile(fileId);
    oldMessages.add(newMessage);

    final updatedContent = json.encode(oldMessages);
    final bytes = utf8.encode(updatedContent);
    final media = drive.Media(Stream.value(bytes), bytes.length);

    await api.files.update(drive.File(), fileId, uploadMedia: media);
    client.close();

    _cachedChat = oldMessages;
    _lastReadTime = DateTime.now();
  }
}
