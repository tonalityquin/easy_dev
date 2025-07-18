import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';

/// 구글 드라이브에서 특정 파일/폴더에 편집자 권한을 부여하는 Bottom Sheet
Future<void> showAddPermissionBottomSheet({
  required BuildContext context,
  String fileId = _defaultFolderId,
}) async {
  final emailController = TextEditingController();

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) {
      return Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 20,
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              '편집자 권한 추가',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(
                labelText: '이메일 주소',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  final email = emailController.text.trim();
                  if (email.isEmpty) return;

                  try {
                    await _addEditorPermission(fileId, email);
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('$email 사용자에게 편집자 권한을 부여했습니다')),
                    );
                  } catch (e) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('권한 추가 실패: $e')),
                    );
                  }
                },
                icon: const Icon(Icons.person_add, size: 20),
                label: const Text(
                  '권한 추가',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
                style: ElevatedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
              ),
            ),
          ],
        ),
      );
    },
  );
}

// 기본 폴더 ID (belivusTest)
const String _defaultFolderId = '1VohUN819zjkbqYBkDofca8fmLKx3MuIO';

Future<void> _addEditorPermission(String fileId, String email) async {
  final client = await _getDriveClient();
  final driveApi = drive.DriveApi(client);

  final permission = drive.Permission()
    ..type = 'user'
    ..role = 'writer'
    ..emailAddress = email;

  await driveApi.permissions.create(
    permission,
    fileId,
    sendNotificationEmail: false,
  );

  client.close();
}

Future<AutoRefreshingAuthClient> _getDriveClient() async {
  final jsonString = await rootBundle.loadString('assets/keys/easydev-97fb6-e31d7e6b30f9.json');
  final credentials = ServiceAccountCredentials.fromJson(jsonString);
  const scopes = [drive.DriveApi.driveScope];
  return await clientViaServiceAccount(credentials, scopes);
}
