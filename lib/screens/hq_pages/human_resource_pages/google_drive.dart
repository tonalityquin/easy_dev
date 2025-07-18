import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData, rootBundle;
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';

import '../../../widgets/navigation/secondary_mini_navigation.dart';
import 'google_drives/add_permission_bottom_sheet.dart';

class GoogleDrive extends StatefulWidget {
  const GoogleDrive({super.key});

  @override
  State<GoogleDrive> createState() => _GoogleDriveState();
}

class _GoogleDriveState extends State<GoogleDrive> {
  static const String rootFolderId = '1VohUN819zjkbqYBkDofca8fmLKx3MuIO';
  late Future<List<drive.File>> _rootItemsFuture;

  @override
  void initState() {
    super.initState();
    _rootItemsFuture = _listFilesInFolder(rootFolderId);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Drive 트리 탐색'),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        centerTitle: true,
      ),
      body: FutureBuilder<List<drive.File>>(
        future: _rootItemsFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (!snapshot.hasData || snapshot.data!.isEmpty) {
            return const Center(child: Text('📁 폴더가 비어 있습니다'));
          }
          return ListView(
            children: snapshot.data!.map((file) => _buildDriveItem(file)).toList(),
          );
        },
      ),
      bottomNavigationBar: SecondaryMiniNavigation(
        icons: const [
          Icons.add,
          Icons.mail,
        ],
        onIconTapped: (index) {
          if (index == 0) {
            showAddPermissionBottomSheet(context: context); // ✅ 분리된 위젯 호출
          }
        },
      ),
    );
  }

  Widget _buildDriveItem(drive.File file) {
    final isFolder = file.mimeType == 'application/vnd.google-apps.folder';

    if (isFolder) {
      return FutureBuilder<List<drive.File>>(
        future: _listFilesInFolder(file.id!),
        builder: (context, snapshot) {
          final children = snapshot.hasData
              ? snapshot.data!.map((child) => _buildDriveItem(child)).toList()
              : [const ListTile(title: Text('로딩 중...'))];

          return ExpansionTile(
            leading: const Icon(Icons.folder),
            title: Text(file.name ?? '이름 없음'),
            children: children,
          );
        },
      );
    } else {
      return ListTile(
        leading: const Icon(Icons.insert_drive_file),
        title: Text(file.name ?? '이름 없음'),
        subtitle: Text(file.mimeType ?? ''),
        onTap: () => _showFileBottomSheet(context, file),
      );
    }
  }

  void _showFileBottomSheet(BuildContext context, drive.File file) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                file.name ?? '파일명 없음',
                style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(file.mimeType ?? 'MIME 타입 없음'),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  icon: const Icon(Icons.link),
                  label: const Text('링크 생성'),
                  onPressed: () {
                    final url = 'https://drive.google.com/file/d/${file.id}/view';
                    Clipboard.setData(ClipboardData(text: url));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('링크가 복사되었습니다: ${file.name}')),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<List<drive.File>> _listFilesInFolder(String folderId) async {
    final client = await _getDriveClient();
    final driveApi = drive.DriveApi(client);

    final fileList = await driveApi.files.list(
      q: "'$folderId' in parents and trashed = false",
      $fields: "files(id, name, mimeType, modifiedTime)",
    );

    client.close();
    return fileList.files ?? [];
  }

  Future<AutoRefreshingAuthClient> _getDriveClient() async {
    final jsonString = await rootBundle.loadString('assets/keys/easydev-97fb6-e31d7e6b30f9.json');
    final credentials = ServiceAccountCredentials.fromJson(jsonString);
    const scopes = [drive.DriveApi.driveScope];
    return await clientViaServiceAccount(credentials, scopes);
  }
}
