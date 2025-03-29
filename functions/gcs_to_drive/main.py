import os
from datetime import datetime, timedelta, timezone
from google.cloud import storage
from googleapiclient.discovery import build
from google.oauth2 import service_account
from googleapiclient.http import MediaFileUpload

# 버킷 이름 및 드라이브 폴더 ID
BUCKET_NAME = 'easydev-image'
DRIVE_FOLDER_ID = '1ExA39KIUe2X6IxS3KwFO5JXhwHMJc_wH'
SERVICE_ACCOUNT_FILE = 'service-uploader.json'

def transfer_gcs_to_drive(request):
    """
    하루 이상된 GCS 이미지들을 Google Drive로 옮기고 GCS에서는 삭제합니다.
    """
    try:
        # ✅ 서비스 계정 인증
        creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE)

        # ✅ Google Drive API 클라이언트
        drive = build('drive', 'v3', credentials=creds)

        # ✅ GCS 클라이언트
        storage_client = storage.Client(credentials=creds)
        bucket = storage_client.bucket(BUCKET_NAME)

        # ✅ plates/ 경로의 파일 목록 가져오기
        blobs = bucket.list_blobs(prefix='plates/')
        moved = 0

        for blob in blobs:
            # ✅ offset-aware로 수정
            if blob.time_created < datetime.now(timezone.utc) - timedelta(hours=1):
                # ✅ 임시 파일로 다운로드
                temp_path = f'/tmp/{os.path.basename(blob.name)}'
                blob.download_to_filename(temp_path)

                # ✅ Google Drive로 업로드
                media = MediaFileUpload(temp_path, resumable=True)
                drive.files().create(
                    body={
                        'name': os.path.basename(blob.name),
                        'parents': [DRIVE_FOLDER_ID]
                    },
                    media_body=media
                ).execute()

                # ✅ GCS에서 삭제
                blob.delete()
                moved += 1

        return f'{moved} files moved to Drive and deleted from GCS.'

    except Exception as e:
        return f'🚨 Error occurred: {str(e)}'
