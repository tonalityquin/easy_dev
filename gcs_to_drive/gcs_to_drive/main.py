import os
from datetime import datetime, timedelta, timezone
from google.cloud import storage
from googleapiclient.discovery import build
from google.oauth2 import service_account
from googleapiclient.http import MediaFileUpload

# GCS 설정
BUCKET_NAME = 'easydev-image'
SERVICE_ACCOUNT_FILE = 'service-uploader.json'

# Google Drive 폴더 ID
PLATE_DRIVE_FOLDER_ID = '1ExA39KIUe2X6IxS3KwFO5JXhwHMJc_wH'
EXCEL_DRIVE_FOLDER_ID = '1rl00BNY_r_pIznT1Vedb-h9bP8kgXgC8'

# GCS 내부 경로 접두사
PLATE_PREFIX = 'plates/'
EXCEL_PREFIX = 'exports/'

def transfer_gcs_to_drive(request):
    """
    이미지와 엑셀 파일을 각각 구글 드라이브로 옮기고 GCS에서 삭제
    """
    try:
        plate_result = move_plate_images()
        excel_result = transfer_excel_files()
        return f'{plate_result}\n{excel_result}'
    except Exception as e:
        return f'🚨 Error occurred: {str(e)}'


def move_plate_images():
    """
    24시간 이상된 이미지 파일을 Google Drive로 이동
    """
    try:
        creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE)
        drive = build('drive', 'v3', credentials=creds)
        storage_client = storage.Client(credentials=creds)
        bucket = storage_client.bucket(BUCKET_NAME)

        blobs = bucket.list_blobs(prefix=PLATE_PREFIX)
        moved = 0

        for blob in blobs:
            if blob.time_created < datetime.now(timezone.utc) - timedelta(hours=24):
                temp_path = f'/tmp/{os.path.basename(blob.name)}'
                blob.download_to_filename(temp_path)

                media = MediaFileUpload(temp_path, resumable=True)
                drive.files().create(
                    body={
                        'name': os.path.basename(blob.name),
                        'parents': [PLATE_DRIVE_FOLDER_ID]
                    },
                    media_body=media
                ).execute()

                blob.delete()
                moved += 1

        return f'🖼 {moved} plate image(s) moved to Drive.'
    except Exception as e:
        return f'🚨 Plate move error: {str(e)}'


def transfer_excel_files():
    """
    1분 이상된 엑셀 파일을 Google Drive로 이동
    """
    try:
        creds = service_account.Credentials.from_service_account_file(SERVICE_ACCOUNT_FILE)
        drive = build('drive', 'v3', credentials=creds)
        storage_client = storage.Client(credentials=creds)
        bucket = storage_client.bucket(BUCKET_NAME)

        blobs = bucket.list_blobs(prefix=EXCEL_PREFIX)
        moved = 0

        for blob in blobs:
            if blob.time_created < datetime.now(timezone.utc) - timedelta(minutes=1):
                temp_path = f'/tmp/{os.path.basename(blob.name)}'
                blob.download_to_filename(temp_path)

                media = MediaFileUpload(temp_path, resumable=True)
                drive.files().create(
                    body={
                        'name': os.path.basename(blob.name),
                        'parents': [EXCEL_DRIVE_FOLDER_ID]
                    },
                    media_body=media
                ).execute()

                blob.delete()
                moved += 1

        return f'📊 {moved} Excel file(s) moved to Drive.'
    except Exception as e:
        return f'🚨 Excel move error: {str(e)}'
