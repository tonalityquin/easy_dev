import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';

class GoogleDriveChatHelper {
  static const String _credentialsPath = 'assets/keys/easydev-97fb6-e31d7e6b30f9.json';

  // 1. 인증용 클라이언트 생성
  static Future<AutoRefreshingAuthClient> _getClient() async {
    final jsonString = await rootBundle.loadString(_credentialsPath);
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [drive.DriveApi.driveScope];
    return await clientViaServiceAccount(credentials, scopes);
  }

  // 2. chat.json 파일 읽기 (List<Map<String, dynamic>> 형태)
  static Future<List<Map<String, dynamic>>> readChatJsonFile(String fileId) async {
    final client = await _getClient();
    final api = drive.DriveApi(client);
    final media = await api.files.get(fileId, downloadOptions: drive.DownloadOptions.fullMedia) as drive.Media;
    final content = await media.stream.transform(utf8.decoder).join();
    client.close();

    try {
      final decoded = json.decode(content);
      return List<Map<String, dynamic>>.from(decoded);
    } catch (e) {
      // JSON 파싱 실패 시 빈 배열 반환
      return [];
    }
  }

  // 3. 새 메시지를 JSON 리스트에 추가 후 저장
  static Future<void> appendChatMessageJson(String fileId, Map<String, dynamic> newMessage) async {
    final client = await _getClient();
    final api = drive.DriveApi(client);

    final oldMessages = await readChatJsonFile(fileId);
    oldMessages.add(newMessage);

    final updatedContent = json.encode(oldMessages);
    final bytes = utf8.encode(updatedContent); // ✅ 바이트 정확히 계산
    final media = drive.Media(Stream.value(bytes), bytes.length); // ✅ 바이트 수 지정

    await api.files.update(drive.File(), fileId, uploadMedia: media);

    client.close();
  }
}
