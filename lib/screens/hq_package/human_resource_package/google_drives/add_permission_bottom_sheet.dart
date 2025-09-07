import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';

import '../../../../utils/snackbar_helper.dart';

Future<void> showAddPermissionBottomSheet({
  required BuildContext context,
  required String selectedArea,
}) async {
  final emailController = TextEditingController();

  final folderMap = {
    'belivus': '1VohUN819zjkbqYBkDofca8fmLKx3MuIO',
    'pelican': '1ZB0UQoDbuhrEsEqsfCZhEsX5PMfOKGiD',
  };
  final fileId = folderMap[selectedArea] ?? folderMap['belivus']!;

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
                  if (email.isEmpty) {
                    // ✅ 안내 스낵바
                    showSelectedSnackbar(context, '이메일을 입력하세요');
                    return;
                  }

                  try {
                    await _addEditorPermission(fileId, email);
                    Navigator.pop(ctx);
                    // ✅ 성공 스낵바
                    showSuccessSnackbar(context, '$email 사용자에게 편집자 권한을 부여했습니다');
                  } catch (e) {
                    // ✅ 실패 스낵바
                    showFailedSnackbar(context, '권한 추가 실패: $e');
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
