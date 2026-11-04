# ParkinWorkin — 기술 명세 및 개발 초기화

초기 설계 기준은 `261103 1901.zip`이며, Firebase Activity Center V2는 `261103 2300.zip`, Plate TTS 계측 분리는 `261103 2347.zip`, **AppBar 높이 복원은 `261104 0027.zip`, Firebase 계측 세션·로컬 보존은 `261104 0117.zip`, 저널 복구·범위별 COST·파일 커서 조회·종료 상태 정정은 `261104 0202.zip`, 사용자 상태·출퇴근 요청 중복 방지는 `261104 0236.zip`, 2차 비용 최적화는 `261104 1413.zip`**을 기준으로 한다. APP RESTART 건너뛰기와 개발자 로그인 성공 시 디버그 모드 자동 활성화 등 기존 동작은 유지한다. 이 문서는 2026-11-03 제공된 Firestore Security Rules, 실제 Dart 코드 및 명시적으로 전달된 초기 백엔드 상태를 구분해 설명한다. 코드의 정적 확인과 실제 Firebase 프로젝트의 배포·실행 검증은 서로 다르다.

## 1. 변경할 수 없는 설계 전제

| 조건 | 프로젝트 계약 |
| --- | --- |
| Firebase Authentication UID | 인증 UID를 업무 계정 문서 ID와 동일시하지 않는다. 계정 연결·Firebase 인증·업무 계정 검증은 별도 단계다. |
| Cloud Functions 배제 | 이 프로젝트의 인증, 계정 생성, 지역 생성에 Cloud Functions를 신규 도입하지 않는다. |
| GCS `publicRead` | 이미지 업로드의 공개 읽기는 의도된 정책이다. 업로드·수정·삭제 권한까지 공개한다는 뜻은 아니다. |
| 초기 백엔드 | `divisions/dev` 문서는 존재한다. `areas`, `user_accounts`, `user_accounts_show`는 비어 있다고 가정한다. 이는 사용자가 제공한 환경 전제이며 런타임 실측이 아니다. |
| 회사 문서 보존 | `divisions/dev`가 있으면 필드, 버전, 생성 시각, 초기 관리자 참조를 **전부 변경하지 않는다**. 없을 때만 생성한다. |
| 사용자 경험 | 기존 화면의 AppBar 높이 56dp, 본문 시작 위치, 중앙 버튼과 좌측 로고 배치를 유지한다. 우측 Activity Center는 높이 48dp 안에 고정하며 UI 계측으로 헤더를 확장하지 않는다. 기존 애니메이션을 유지하고 신규 `hintText`·수정 Dart 주석을 추가하지 않는다. |
| 디버깅 | `debugPrint`와 개발자 모드 ON일 때 `STATUS`의 `debugPrint 코드 복사`를 유지한다. 민감정보 원문은 진단 로그에 기록하지 않는다. |
| 사용자 표시 | 계정 연결·인증 과정의 일반 앱 안내 문구에 내부 백엔드 제품·기술명을 표시하지 않는다. 외부 제공자가 제어하는 계정 선택·동의 UI는 예외다. |
| 비용 최적화 2차 전제 | 동일 업무 계정의 다중 기기 동시 접속은 이번 범위에서 제외한다. **옛 구조의 출퇴근 레거시 `logs` 데이터는 존재하지 않는다**는 제공 전제를 사용하며, 현재 월별 기록·관리자 달력 기능과 실제 필수 상태 변경은 유지한다. |

보안은 실제 운영상 필수 위험만 수정 대상으로 평가하고, 선택적 강화는 별도 요청 없이 진행하지 않는다. 비용 최적화는 실제 청구 단위 및 사용량과 연결해 판단한다.

## 2. 프로젝트 구성과 진입

| 위치 | 책임 |
| --- | --- |
| `lib/main.dart` | 앱 시작과 Firebase 초기화. 기존 근무 알림 통신은 유지하고 Activity Bridge 수신 콜백은 등록하지 않음 |
| `lib/app/tutorial/tutorial/start_gate_screen.dart` | 최초 설정/세션 복원 판단 |
| `lib/features/launcher/page/power_boot_screen.dart` | 전원 시작, 최초 사용 목적 |
| `lib/app/terminal/presentation/parkinworkin_terminal_screen.dart` | 런처, Mini Terminal, 계정 인증 Dialog, 개발자 도움말 UI, APP RESTART 제목 5회 탭과 업무 화면 이동 |
| `lib/features/launcher/application/mode_launcher_controller.dart` | 로그인 명령, 계정/지역/모드 진행, 개발자 비밀번호 성공 후 디버그 상태 활성화 |
| `lib/features/launcher/application/terminal_auth_coordinator.dart` | 계정 유형, 로그인과 업무 계정 검증 |
| `lib/app/auth/google_auth_session.dart` | 외부 계정과 Firebase 인증 세션 관리 |
| `lib/features/launcher/application/dev_bootstrap_service.dart` | 개발용 회사·본사 지역·메타·계정 조건부 생성/복구 |
| `lib/shared/secondary/pages/sheets/tabs/dev_management_common.dart` | 지역과 계정 메타 생성 Payload 계약 |
| `lib/shared/secondary/data/services/dev_user_write_service.dart` | 계정 원본·코드 예약·메타·사용자 View의 계정 생성 트랜잭션 |
| `lib/features/account/domain/models/user/user_model.dart` | 일반 업무 계정 데이터 필드 |
| `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart` | `debugPrint` 진단 수집, 개발자 Status Dialog와 Firebase 활동 로그 복사 |
| `lib/app/diagnostics/firebase_activity_meter.dart` | Firebase/Firestore/Storage API 계측, 메모리 이벤트·카운터, 호출부 확장 |
| `lib/app/diagnostics/firebase_activity_journal.dart` | 세션별 JSONL 저장, 실패 재시도·부분 쓰기 복구, 보관 범위별 COST 집계, 파일 커서 기반 100건 조회 |
| `lib/app/diagnostics/firebase_activity_center_dialog.dart` | 개발자 전용 Firebase Activity Center, 보관 세션·기간의 COST 조회, 파일 커서 페이지, debugPrint 코드 복사와 페이드 애니메이션 |
| `lib/features/account/data/services/user_status_service.dart` | 문서별 쓰기 순서 보존, 성공한 필드 값 추적, 순차 중복 UPDATE 생략 및 실제 쓰기 발생 여부 반환 |
| `lib/features/account/domain/repositories/user_repository.dart`, `lib/features/account/data/repositories/firestore_user_repository.dart` | 로그인·지역 동기화의 실제 원격 WRITE 여부를 호출부에 반환; 직접 계정 문서를 수정할 때 상태 확인 캐시 무효화 |
| `lib/features/account/applications/user_state.dart` | 10초 지역 쓰기 생략 규칙 제거, 저장소의 확인된 쓰기 결과를 적용하여 로그인·지역 로컬 UI 갱신 유지 |
| `lib/features/commute/domain/repositories/commute_log_repository.dart` | 오늘 출근·관리자 달력의 월별 문서만 GET, 레거시 GET·삭제 SET 제거, 저장소 인스턴스 간 동시 동일 월 GET 공유 |
| `lib/shared/tts/application/foreground_task_handler.dart` | 기존 Plate TTS 및 근무 상태 알림 실행. Firebase Activity Bridge 시작·종료 호출 없음 |
| `lib/shared/tts/data/repositories/firestore_plate_tts_listener_repository.dart` | Plate TTS용 원래 Firestore 직접 조회·스냅샷 구독 유지. Activity Center 중계 래퍼 미적용 |
| `lib/app/diagnostics/firebase_activity_http.dart` | 공개 GCS URL HTTP 요청 상태·수신 본문 바이트 계측 |
| `lib/app/init/db_connection_status_section.dart` | AppBar 내부 116×48dp 컴팩트 상태·카운터 패널, 개발자 전용 상세 진입, 상태·숫자 페이드 애니메이션과 전체 카운터 접근성 정보 |
| `lib/features/dev/application/debug_session_controller.dart` | 개발자 승인 상태를 확인하여 전역 디버그 모드 활성화·비활성화 |
| `lib/features/selector/application/dev_auth.dart` | SharedPreferences 디버그 모드 상태, ValueNotifier 및 새 시작 시 복원·초기화 정책 |
| `lib/features/launcher/application/launcher_actions.dart`, `lib/app/init/app_exit_service.dart` | 기본 재시작 버튼의 앱 종료 준비·Android 네이티브 Activity 재실행 요청 |
| `lib/shared/auth/account_code_number.dart` | 코드번호 검증·생성·문서 ID·마스킹 |

최초 사용 목적은 지사 직원·본사 직원·출퇴근 기록형 → 일반 계정, 태블릿 설치형 → 태블릿형, 개인용 → 개인형으로 지정된다. 런처 인증 이후 회사·지역·허용 모드를 결정한다. 단순 Firebase 인증과 업무 계정 로그인의 성공은 다르다.

## 3. 회사 `divisions/dev`의 기존 상태

사용자가 제공한 기존 문서는 다음과 같다. 파일에 포함된 시드 데이터가 아니라 실제 백엔드에 존재한다고 전달된 값이다.

| 필드 | 기존 값 | 도움말 실행 후 |
| --- | --- | --- |
| `name` | `dev` | 유지 |
| `companyId` | `dev` | 유지 |
| `accountWriteLocked` | `false` | 유지 |
| `accountWriteVersion` | `11` | 유지 |
| `areaConfigVersion` | `3` | 유지 |
| `createdAt` | 2025-05-08 23:02:37 KST | 유지 |
| `initialAdminAccountId` | `aef260e9aa1-dev` | 유지 |

`initialAdminAccountId`는 계정이 실제 존재한다는 증거가 아니라 계정 문서 참조다. 이 참조 ID의 코드번호가 유효하다면 초기 개발 계정 생성에 사용하고 **기존 회사 참조를 다시 쓰지 않는다**. 참조 형식이 잘못됐거나 참조된 문서가 다른 계정이면 자동 덮어쓰기 대신 중단한다.

회사 문서 자체가 없는 경우만 신규 생성한다. 새 문서에는 `name`, `companyId`, `accountWriteLocked=false`, 초기 버전 `accountWriteVersion=0`, `areaConfigVersion=0`, 무작위 코드번호를 기반으로 한 `initialAdminAccountId`, 서버 `createdAt`을 기록한다. 기존 문서의 11·3 버전을 새 회사에 복제하지 않는다.

## 4. 런처 로그인 Dialog UI

| 위치/상태 | 내용 |
| --- | --- |
| 상단 `ACCOUNT VERIFICATION` | 제목 영역을 2초 이내 간격으로 연속 5회 탭하면 수집된 진단 로그를 `debugPrint(...)` 코드로 복사한다. |
| 상단 오른쪽 끝 | **일반 계정(`TerminalAccountKind.user`)이고 개발자 비밀번호 로그인 모드가 ON인 경우에만** 도움말 아이콘을 표시한다. 개인형·태블릿형은 개발자 로그인 모드가 ON이어도 도움말 아이콘을 표시하지 않는다. 진행 중에는 원형 로딩 표시로 바뀐다. |
| 계정 유형 | 현재 `PROFILE` 표시 |
| 입력 1 | `NAME or Unique` |
| 입력 2 | `코드번호`; 기존 코드 포맷터·검증 유지 |
| 코드번호 바로 아래 | 중앙 정렬 `계정 연결` / `연결 계정 변경` 버튼 |
| 하단 왼쪽 | 연결된 계정 이메일 또는 `연결된 계정 없음` |
| 하단 오른쪽 | `로그인`; 개발자 비밀번호 경로에서는 `계정 확인` |
| 도움말 실행 결과 | 인라인 로딩·성공·오류 표시, 결과 애니메이션·햅틱; 성공 시 계정 이름과 코드번호를 기존 입력 필드에 적용 |

Mini Terminal의 오픈 660ms, 닫힘 410ms, 내용 페이드·스케일과 입력 필드 포커스 전환을 유지한다. 도움말은 `AnimatedSwitcher`로 등장/퇴장하고, 결과 영역은 `FadeTransition`과 `SizeTransition`으로 바뀐다. 애니메이션 감소 설정에서는 시간을 0으로 사용한다.

### 서로 다른 개발자 기능

| 조작 | 기능 | 권한 효과 |
| --- | --- | --- |
| 이름·코드번호가 빈 상태로 로그인 버튼 5회(일반·개인형), 3회(태블릿형) | `DeveloperAccountAuthorization.authorizeInteractive()`를 통해 개발자 비밀번호 인증 모드 승인 | 승인 성공 후 `_developerPasswordMode=true`, 업무 계정 로그인 자체를 완료하지는 않음 |
| 제목 `ACCOUNT VERIFICATION` 5회 연속 탭 | 메모리의 디버그 로그 클립보드 복사 | 권한 상승 없음 |
| 일반 계정에서 개발자 비밀번호 모드 활성화 시 헤더 우측 `?` | 개발 회사·지역·일반형 dev 계정 초기화 | 개인형·태블릿형은 표시·실행 모두 제외, 인증 및 충돌 검증 이후 누락 문서만 생성 |
| 전역 Developer Mode ON 상태의 `STATUS` | 진단 상태 Dialog 및 `debugPrint 코드 복사` | 기존 `DevAuth.devModeEnabled` 기준 유지 |
| `APP RESTART` 제목을 2초 이내 간격으로 5회 탭 | 재시작 Dialog를 닫힘 애니메이션과 함께 종료하고 업무 목적지로 이동 | 인증·지역·모드 검증 생략 없음 |
| 개발자 비밀번호 인증 성공 | 기존 승인 검증 후 `DebugSessionController.enable()` 호출 | 디버그 모드 ON이 확인돼야 로그인 완료 처리 |

`_developerPasswordMode`와 전역 `DevAuth.devModeEnabled`는 별도 상태다. Debug 빌드의 개발자 승인 경로와 Release 빌드의 허용 계정 승인 경로도 다르다. 도움말 아이콘은 **일반 계정과 개발자 비밀번호 모드 ON을 모두 충족할 때만** 표시되며, 실행 함수에서도 같은 계정 유형 및 상태를 검사한다. 개인형·태블릿형은 기존 개발자 비밀번호 로그인만 유지하고 일반형 dev 초기화 기능에서 배제한다. 이 UI 검사로 Firestore 서버의 권한 규칙이 강화되는 것은 아니다. 개발자 도움말을 표시하거나 실행하는 것만으로는 전역 Developer Mode를 임의 ON으로 바꾸지 않는다. **개발자 비밀번호 로그인 검증에 성공한 경우에만** 기존 `DebugSessionController.enable()`을 호출하여 전역 디버그 모드를 ON으로 전환하고, 실패하면 로그인 완료로 처리하지 않는다.

### APP RESTART Dialog 재시작 및 숨겨진 건너뛰기

`ModeLauncherController`에서 수동 Google 계정 로그인 성공 및 업무 경로 준비를 완료하면 `requiresManualGoogleLoginRestart`가 설정되고, `parkinworkin_terminal_screen.dart`의 `_finalizeLauncherAndNavigate()`에서 `APP RESTART`를 표시한다. 기존 세션 자동 복원과 개발자 비밀번호 로그인은 이 재시작 요청 대상이 아니다. 제목을 누르는 것만으로 인증 절차나 Firebase UID·업무 계정 검증을 우회하지 않는다.

| 동작 | 조건·구현 | 결과 |
| --- | --- | --- |
| `재시작` 버튼 | 안내문 타이핑 완료 후 활성화, 중복 실행 차단 | `LauncherActions.restartApp()` → `AppExitService.restartApp()` → Android 플랫폼 재시작 요청. 기존 기능 유지 |
| 제목 `APP RESTART` 1~4회 탭 | 연속 입력 간격 2초 이내, 제목 영역만 감지 | 재시작 Dialog 유지, 외관·안내문 변경 없음 |
| 제목 `APP RESTART` 5회 탭 | Dialog 열림 완료, 재시작·건너뛰기 처리 중이 아닐 때 | `manual_google_login_restart_skip_requested` 진단 기록, 햅틱, Mini Terminal 닫힘 애니메이션, Dialog 종료, `manual_google_login_restart_skipped` 기록 |
| 건너뛰기 이후 | `_showManualGoogleLoginRestartNotice()`가 `false`를 반환 | `_resolveActiveWorkSessionNavigationTarget()` 및 `_closeLauncherAndNavigate()`의 기존 업무 경로로 진행; 네이티브 재시작 호출 없음 |
| 재시작 실행 중 제목 탭 | `_restarting=true` | 건너뛰기 처리 차단 |
| 건너뛰기 실행 중 재시작 버튼 | `_skipping=true` | 버튼 비활성화, 중복 실행 차단 |
| 모션 감소 옵션 | `reduceMotion=true` | 애니메이션 시간만 0으로 변경; 건너뛰기와 업무 이동은 동일 |

상단 `APP RESTART`는 평소에는 일반 제목과 동일하게 보이며 추가 힌트나 버튼을 표시하지 않는다. 제목의 연속 탭 판정은 2초 간격이며, 5회째에만 건너뛰기를 실행한다. 기존 오픈 660ms, 닫힘 410ms, 라우트 페이드 170ms, 안내 타이핑(문자당 24ms)과 개발자 `STATUS` 버튼을 유지한다. 건너뛰기 중에는 기존 `_MiniTerminalFrameState.close()`를 호출한다. Android 실제 재시작 성공과 프로세스 완전 종료는 별개이고, 건너뛰기는 이 네이티브 요청을 호출하지 않는다.

### 개발자 비밀번호 로그인 성공과 디버그 모드

`mode_launcher_controller.dart`의 `authenticateResolvedPassword()`는 `TerminalAuthCoordinator.verifyResolvedAccountPassword()`가 성공하여 유효한 계정이 반환됐을 때만 `DebugSessionController.enable(source: 'launcher_developer_password_login')`을 호출한다. 이 함수는 `DeveloperAccountAuthorization.isAuthorized`를 재검사하고 `DevAuth.setDevModeEnabled(true)`로 앱 내부 디버그 상태를 갱신한다. **비밀번호 검증 실패·개발자 승인 만료·디버그 활성화 실패에서는 디버그를 새로 ON으로 만들지 않고, 개발자 로그인 완료로 진행하지 않는다.**

성공 진단 이벤트 `developer_password_debug_enabled`, 실패 이벤트 `developer_password_debug_enable_failed` 또는 `developer_password_login_debug_unavailable`을 `LauncherDiagnostics.record()`에 기록한다. 전역 디버그 ON 이후에는 기존 Mini Terminal `STATUS`를 통해 `ParkinWorkinTerminalDiagnostics.debugPrintCode`를 클립보드로 복사할 수 있다. 이미 ON인 경우에도 동일 공유 상태를 사용한다. 개발자 비밀번호 인증 성공의 기존 Status Dialog 호출은 디버그 자동 활성화보다 앞에 두어 새 Status 팝업이 로그인 흐름에 갑자기 추가되지 않도록 한다. 사용자에게는 로그인 성공 이후 헤더 `STATUS` 버튼이 표시된다.

이 디버그 모드는 Flutter의 `kDebugMode` 빌드 플래그를 변경하지 않는다. 일반 Google 로그인에는 디버그 자동 활성화를 적용하지 않는다. 앱을 재실행한 경우 `DevAuth.restorePrefs()`의 첫 시작 정책에 따라 디버그 모드가 다시 OFF로 초기화될 수 있으므로 영구 ON이라고 해석하지 않는다.

## 5. 개발용 초기 데이터 생성 — 도움말 동작

**일반 계정(`TerminalAccountKind.user`)의 개발자 비밀번호 로그인 모드에서만** `lib/features/launcher/application/dev_bootstrap_service.dart`의 `DevBootstrapService.ensure(email: ...)`를 호출한다. 개인형·태블릿형은 도움말 UI를 숨기며 실행 함수 진입 검사에서도 즉시 반환하므로 이 기능으로 인한 Firestore 조회·쓰기가 발생하지 않는다. 도움말을 누를 때 연결된 계정이 없으면 기존 대화형 계정 연결 절차를 시도한다. 취소하거나 유효한 비익명 Firebase 인증과 외부 계정 이메일 일치가 없으면 문서를 생성하지 않는다. 연결 이메일은 신규 개발 계정의 등록 이메일로 사용하며 임의 이메일을 만들지 않는다.

| 순서 | 문서 경로 | 존재 시 | 없을 때 |
| --- | --- | --- | --- |
| 1 | `divisions/dev` | 내용 확인 후 **쓰기 0회**, `accountWriteLocked=true`이면 중단 | 회사 생성, 안전한 신규 코드로 `initialAdminAccountId` 지정 |
| 2 | `areas/dev-dev` | `division`, `name`, `isHeadquarter` 일치 검사 후 보존 | `headquarterAreaPayload()` 사용하여 생성 |
| 3 | `user_accounts_show/dev-dev` | 집계와 계정 제한값 검사 후 보존 | `accountMetaPayload()`로 0명 메타 생성 |
| 4 | `user_accounts/{accountId}` | 이름 `dev`, 역할 `dev`, 코드, 회사·지역, 등록 이메일 일치 확인 | `DevUserWriteService.createUser()`로 신규 생성 |
| 5 | `user_account_codes/{codeNumber}` | 기존 예약이 같은 사용자를 가리키는지 확인 | 계정 생성 트랜잭션에서 예약 |
| 6 | `user_accounts_show/dev-dev/users/{accountId}` | 코드와 활성 상태 검증 후 보존 | 계정 생성 트랜잭션에서 조회용 문서 생성 |

`areas/dev-dev`는 본사 지역이며 `name=dev`, `englishName=dev`, `division=dev`, `isHeadquarter=true`, `modes=[single,double,triple,minor]`, 개발 테스트용 capability 목록, 서버 `createdAt/updatedAt`을 사용한다. 새 메타에는 `activeLimit=100`, `totalLimit=100`, `activeCount=0`, `inactiveCount=0`, `totalCount=0`을 기록한다. **기존 메타의 제한값·집계는 자동 초기화하지 않는다.** 신규 계정 생성 후 정상 집계는 `1/0/1`이다.

개발 계정은 `name=dev`, `role=dev`, `isActive=true`, `divisions=[dev]`, `areas=[dev]`, `currentArea=dev`, `selectedArea=dev`, 네 가지 정규 모드, 연결된 이메일을 가진다. 코드번호는 `AccountCodeNumber.isValid()`를 충족한다. 기존 회사의 `initialAdminAccountId=aef260e9aa1-dev`가 있다면 계정 ID와 코드번호는 해당 참조에 따른다. 회사가 새로 생성될 경우에는 `AccountCodeNumber.generate()`의 무작위 코드를 사용한다.

계정 생성은 기존 `DevUserWriteService.createUser()`를 재사용한다. 이것은 `user_accounts` 원본, `user_account_codes` 예약, 상위 메타 집계, `users` 하위 문서의 **4개 문서를 한 트랜잭션에서 기록**한다. 회사·지역·메타는 별도의 존재 확인 트랜잭션을 사용한다. 계정 생성 도중 오류가 나면 앞서 생성한 지역·메타는 남을 수 있으므로 다음 실행에서 다시 확인하며, 임의 삭제하거나 이전 문서를 덮어쓰지 않는다.

### 기존 데이터와 재실행

- 이미 완성된 `dev` 회사·지역·메타·계정은 재사용하고 쓰지 않는다. 도움말 버튼 중복 입력은 UI에서 차단한다.
- 신규 문서 생성은 Firestore 트랜잭션의 존재 검사 후 수행한다. 다른 기기에서 동시에 생성하면 기존 계정·예약 충돌을 다시 확인한다.
- 기존 계정의 코드번호 예약 문서가 없으면 동일 계정을 가리키도록 복구할 수 있다. View 사용자 문서가 없고 상위 집계가 확실히 0일 때만 사용자 View와 집계 1을 복구한다.
- 메타·조회용 문서가 서로 모순되거나, 회사 참조·계정 이메일·역할·코드·지역이 충돌하면 수정을 중단한다. 다른 계정·버전·집계를 임의 재작성하지 않는다.
- 기존 회사에 `initialAdminAccountId`가 없거나 형식이 잘못된 경우에는 신규 계정을 추측해서 만들지 않고 사용자 확인을 요구한다.
- 계정 생성은 `password`를 저장하지 않는다. 따라서 dev 계정의 일반 이메일 기반 로그인 가능성과 **개발자 비밀번호 로그인 가능 여부는 별개**이며, 저장된 비밀번호가 없다면 후자의 인증은 성공하지 않는다. 기본·고정 비밀번호를 새로 심지 않는다.

## 6. 진단 기록·복사·오류 처리

`DevBootstrapService`는 요청, 회사·지역 준비, 계정 쓰기 단계, 성공·실패를 `ParkinWorkinTerminalDiagnostics.record()`로 기록하며 내부적으로 `debugPrint`를 호출한다. 계정 코드번호, 이메일, 인증 토큰은 새 초기화 진단에 원문으로 기록하지 않는다. 기존 서비스의 상세 메시지를 그대로 노출하는 대신 단계별 이벤트와 처리된 문서 수를 기록한다.

로그 복사는 기존 `ParkinWorkinTerminalDiagnostics.debugPrintCode` 형식을 유지한다. 개발자 `STATUS`에서는 클립보드 버튼을 누를 때 `debugPrintCodeWithJournal()`로 기존 진단과 로컬 보관된 현재 세션의 Firebase 기록을 비동기로 합친다. APP RESTART 건너뛰기 및 디버그 자동 활성화도 `LauncherDiagnostics.record()` 및 `ParkinWorkinTerminalDiagnostics.record()`에 기록되어 `debugPrint(...)` 코드 복사 대상에 포함된다. 개발자 `STATUS` Dialog의 클립보드 버튼은 진입 시 및 복사 실행 직전에 `DevAuth.isDevModeEnabled()`로 권한을 재확인하며, 별도의 제목 5회 탭 복사는 개발자 권한을 제공하지 않는다. 진단 복사 과정에는 Firestore 읽기·쓰기가 필요 없다. UI는 연결 실패·권한 만료·문서 충돌과 일반 네트워크 오류를 구분해 표시한다.

### Firebase Activity Center — 비용 관련 앱 활동 계측

이 기능은 **메인 앱 Isolate에서 계측이 연결된 호출부**의 Firebase/Google Cloud Storage API 활동을 집계한다. 포그라운드 Plate TTS Isolate의 Firestore 활동은 안정성 우선 정책에 따라 의도적으로 통합하지 않는다. Firebase 프로젝트 전체의 실제 청구액·청구 읽기 수가 아니다. 로그를 서버에 저장하거나 계측 목적으로 Firestore를 추가 조회하지 않는다.

| 화면/권한 | 디버그 OFF | 디버그 ON |
| --- | --- | --- |
| 우측 상단 `LIVE DB` · `STORAGE DB` | 상시 표시 | 상시 표시 |
| 우측 상단 `READ` · `WRITE` · `DELETE` · `SNAP` · `LISTEN` · `STORAGE` | 상시 계측·표시 | 상시 계측·표시 |
| `ACTIVITY CENTER` 진입 항목 | 표시, 상세 접근 거부 | 표시, 상세 Dialog 진입 가능 |
| 최근 이벤트·유형별 필터·상세 상태 | 접근 거부 | 열람 가능 |
| 활동 로그 클립보드 복사 | 접근 거부 | `debugPrint(...)` 코드로 복사 가능 |
| 기존 `STATUS`의 `debugPrint 코드 복사` | 기존 개발자 접근 정책 | 기존 진단에 Firebase 활동 로그도 병합 |

#### 기존 헤더 높이 복원 및 1시 방향 관측 패널

Activity Center 도입 전 `261103 2050.zip`의 일반 AppBar는 기본 `kToolbarHeight`인 **56dp**, Single 내부·주차 완료 AppBar는 `toolbarHeight: kToolbarHeight`였다. 관측 패널 도입으로 `261104 0027.zip`에는 7개 화면에 `toolbarHeight: 128`, 우측 영역 `height: 116`, `maxWidth: 168`이 적용되어 본문 시작 위치를 아래로 이동시켰다. 이번 변경은 **7개 화면 모두 원래 56dp 헤더 높이로 복원**하고 본문 시작 위치를 유지한다.

| 위치·구성 | 변경 전 `0027.zip` | 헤더 복원 후 |
| --- | --- | --- |
| 본사·Single·Double·Triple·Minor 대시보드 | AppBar 128dp, 우측 116dp 높이·168dp 최대 너비 | 기본 AppBar 56dp, 우측 `kToolbarHeight - 8`=48dp·최대 132dp |
| Single 내부 | AppBar 128dp, 우측 116dp 높이·168dp 최대 너비 | AppBar 56dp, 우측 48dp·최대 116dp |
| 주차 완료 화면 | AppBar 128dp, 우측 116dp 높이·168dp 최대 너비 | AppBar 56dp, 우측 48dp·최대 132dp |
| 공통 관측 위젯 | 163dp 폭, 상태·집계·진입 문구의 세로 누적 | 고정 116×48dp, 상태 두 줄·집계 두 줄, 전체 패널 탭 |
| 본문 시작 위치 | 추가 툴바 높이 72dp만큼 하강 | 기존 높이와 동일한 위치 |

고정 패널 1행에는 `LIVE DB ON/OFF`, 2행에는 `STORAGE DB ON/OFF`를 표시한다. 3행 `R·W·D`는 READ·WRITE·DELETE, 4행 `SN·L·ST`는 SNAP·현재 활성 LISTEN·STORAGE를 뜻한다. 카운터는 큰 값에서 K/M/B 단위로 축약하며, **계측 원본 수치·상세 설명은 기존 Activity Center Dialog와 개발자 `STATUS` 복사에 유지**한다. 첫 줄의 화살표 및 패널 전체 탭으로 Activity Center에 진입하되, 개발자 모드가 OFF이면 기존처럼 상세 접근을 거부한다. 화면 판독기에는 축약하지 않은 전체 명칭·수치를 제공한다.

상태 점의 `AnimatedContainer`, ON/OFF의 `AnimatedSwitcher`, 카운터의 페이드 전환을 보존한다. 색상·텍스트만 바뀌고 패널 크기는 고정되며 `MediaQuery.disableAnimations`이면 전환 시간을 0으로 한다. 터치 가능한 기존 1시 방향 패널을 `IgnorePointer`로 복원하지 않으며, 7개 화면의 좌측 로고·중앙 터미널 버튼·기존 업무 애니메이션은 변경하지 않는다. 계측용 Firestore 요청이나 Storage 작업도 추가하지 않는다.

현재 `LIVE DB ON`은 익명이 아닌 Firebase Auth 사용자가 존재한다는 뜻이고, `STORAGE DB ON`은 사용 가능한 Google 로그인 세션이 존재한다는 뜻이다. 이것을 서버 통신 정상 여부 또는 비용 발생 여부로 단정하지 않는다. 디버그 OFF에서도 계측 서비스는 작동하지만, 개별 활동의 상세 정보·복사는 디버그 모드 ON에서만 제공한다. 열린 Dialog에서 디버그 모드가 꺼지면 닫히고 복사 시점에도 모드를 재검사한다.

#### 앱 전체 실행 세션의 계측과 로컬 보관 — 2026-11-04

앱이 `main()`에 진입해 `WidgetsFlutterBinding.ensureInitialized()`가 끝나면 `FirebaseActivityMeter.startSession()`으로 `SESSION_START`를 동기 기록한다. `initializeJournal()`은 UI 시작을 불필요하게 대기시키지 않고 비동기 실행한다. 저장 경로 준비 전 이벤트는 최대 4096개의 메모리 대기열에 기록한 뒤 준비되면 기록한다. 대기열이 넘치거나 디스크 쓰기 실패가 발생하면 누락·실패 수치로 표시한다. 메인 Isolate의 Flutter/Firebase SDK 메서드가 계측 래퍼를 거쳐야만 호출 내용이 기록된다. 앱 실행 구간을 표시하는 행위 자체가 Firebase 읽기·쓰기를 추가하지 않는다.

| 라이프사이클 단계 | 기존 동작 | 이번 수정 후 | 비용 해석 |
| --- | --- | --- | --- |
| `main()` 첫 실행 | Meter 최초 참조 시점부터 이벤트 존재 | `SESSION_START`를 Firebase 초기화 이전에 기록, 로그 저장소 준비 | SESSION_START 자체는 Firebase 비용이 아님 |
| Firebase Core 초기화 | 별도 초기화 진단 | `firebase_core / INITIALIZE_APP` 성공·실패·지연 기록 | Firestore READ가 아님 |
| App Check 활성화·진단 토큰 | 별도 진단만 존재 | `ACTIVATE`, `TOKEN_FORCE_REFRESH` 계측 | 과금 문서 읽기와 별개 |
| 기존 Google·Firebase 인증 준비 | 인증 진단 중심 | `CONFIGURE_RUNTIME`, `INITIALIZE_SESSION`, `BOOTSTRAP_EXISTING_USER`, 실제 Firebase `SIGN_IN_*`, `SIGN_OUT` 계측 | 인증 API 기록 자체가 청구 단위를 확정하지 않음 |
| 로그인·로그아웃·화면 이동 | UI 단계가 변경 | 동일 세션 ID 유지, 계측 계속 | 앱 실행 중 관측 범위 연속 유지 |
| 앱 백그라운드 | 앱 생명주기에 따름 | 계측을 수동 중단하지 않음 | OS가 프로세스를 종료하면 마지막 기록이 유실될 수 있음 |
| 정상 종료·재시작 요청 | 업무·알림 서비스 정리 후 종료 | `SESSION_EXIT_REQUESTED`/`SESSION_RESTART_REQUESTED`, `SESSION_EXIT_PREPARED`/`SESSION_RESTART_PREPARED` 기록·저널 flush 시도 | PREPARED는 종료 준비를 뜻하며 OS 프로세스 종료 확정 신호가 아님 |
| 종료 실패 | 기존 업무·알림 복구 | `SESSION_EXIT_FAILED`/`SESSION_RESTART_FAILED` 기록 후 기존 복구 유지 | 계측을 멈추지 않음 |
| OS 강제 종료 | 종료 콜백 보장되지 않음 | 파일에 남은 이벤트 유지, 다음 실행에서 `PREVIOUS_SESSION_UNCLEAN` 또는 `PREVIOUS_SESSION_OUTCOME_UNKNOWN` 구분 | 마지막 사건 유실 및 실제 종료 여부는 앱만으로 확정 불가 |
| 앱 새 실행 | 메모리 누적 초기화 | 새 sessionId·새 카운터, 이전 보관 파일은 제한 내 유지 | 세션 사이 합계는 별도로 조회 |

로컬 파일은 `path_provider`의 Application Support 디렉터리 아래 `firebase_activity/`에 저장하는 JSON Lines 형식이다. 세션별 파일명에 세션 ID와 파일 순번을 포함하고, 2MiB 단위로 나눈다. 기본 보관 한도는 **최근 7일·총 20MiB**이며 한도 초과 시 오래된 조각부터 삭제한다. 현재 열려 있는 조각은 삭제하지 않지만 현재 세션의 오래된 조각도 용량 제한으로 정리될 수 있으므로, 앱이 수일간 실행되거나 이벤트가 매우 많은 경우 완전한 무기한 보존을 보장하지 않는다. UI의 최근 500개는 기존처럼 메모리에서 즉시 표시하고, 저장된 이벤트는 로컬 파일에서 별도로 읽는다. 모든 파일 쓰기는 비동기로 수행하며 오류가 기존 인증·Firestore·Storage 업무 요청의 성공 여부에 영향을 주지 않도록 격리한다.

`FirebaseActivityJournal`은 이벤트 시각, 세션 ID, 서비스, 작업 종류, 결과와 이미 마스킹된 진단 문자열만 로컬에 기록한다. 실제 사용자 문서 본문, UID·이메일, 차량번호, OAuth 토큰, 다운로드 서명 URL을 추가로 수집하지 않는다. 계측 파일은 서버에 전송하거나 Firestore 문서로 저장하지 않는다. 파일은 앱 전용 디렉터리이지만 디버그 기기·백업·탈옥 등에서는 별도 보호가 필요하며 장기간 개인정보 관련 로그를 보존하지 않도록 용량·기간 제한을 적용한다.

| 조회·복사 진입점 | 수정 전 | 수정 후 |
| --- | --- | --- |
| 상단 116×48dp 패널 | 실시간 누적 요약 | 그대로 유지, 헤더 56dp 불변 |
| Activity Center 기본 목록 | 메모리 최근 500개 | 그대로 유지, `보관 기록` 모드와 전환 애니메이션 추가 |
| 보관 기록 | 미지원 | 현재·이전·전체 보관 세션 및 시간 필터, JSONL 파일을 최신순 역방향으로 읽는 커서 기반 100건 페이지 조회 |
| Activity Center 클립보드 복사 | 최근 500개 이벤트만 | 선택 세션·서비스·시간 범위의 로컬 보관 기록 전체를 `debugPrint(...)` 코드로 복사 시도 |
| `COST` 복사 | 현재 실행 세션의 메모리 요약 | 선택한 보관 세션·기간의 구조화 JSONL 이벤트에서 계산한 `OBSERVED / ESTIMATED / UNAVAILABLE` 복사, 화면과 같은 집계 결과 사용 |
| `STATUS` 클립보드 복사 | 기존 진단 + 최근 Firebase 이벤트 | 복사 실행 시 기존 진단 + 현재 세션의 보관 이벤트 전체를 동적으로 생성 |
| 디버그 OFF | 상세 열람 제한 | 로컬 기록은 계속, 상세·복사는 제한 |
| 디버그 ON→OFF | 기존 상세 닫힘 | 상세 닫힘 유지, `STATUS` 복사 버튼에서도 권한 재검사 |
| 로컬 파일 접근 실패 | 최근 메모리만 존재 | 실패 시 대기열 보존·지수 백오프 복구 시도, 오류·누락 표시, 로컬 파일 복사 실패 시 현재 세션의 최근 500개 메모리 기록으로 대체 가능 |

클립보드 복사는 Android 클립보드 처리 한계로 매우 큰 로그에서 실패할 수 있다. 실패하면 성공으로 표시하지 않으며, 서비스·시간 범위를 좁혀 다시 복사할 수 있다. 앱 내 로컬 보관에서 이미 삭제되었거나 저장되지 않은 이벤트를 복원할 수 없으며, `PREVIOUS_SESSION_UNCLEAN`은 이전 세션의 종료 준비가 확인되지 않음을 뜻한다. `PREVIOUS_SESSION_OUTCOME_UNKNOWN`은 준비 또는 이전 버전의 종료 기록은 있지만 OS의 실제 프로세스 종료 결과를 확인할 수 없다는 뜻이다. Apple/Android 플랫폼의 프로세스 중단에서는 종료 후 코드를 실행할 수 없으므로 종료 준비 기록이 없는 것이 곧 앱 결함이라는 뜻은 아니다.

Firebase Auth·Google Auth·App Check의 진단 이벤트는 실제 Firebase 과금 단위와 분리해 `auth`, `google_auth`, `app_check`, `firebase_core`, `lifecycle`로 기록한다. 기존 READ·WRITE·DELETE·SNAP·STORAGE 합계에는 포함하지 않는다. Firestore 표준/엔터프라이즈 요금, 인덱스 읽기, Rules 의존 읽기, 보존·저장 용량, SDK 내부 재시도, 다른 기기 및 서버 작업은 앱 계측만으로 확정할 수 없다. Plate TTS 포그라운드 Isolate의 구독은 이전 합의대로 계측에서 제외하고 **기존 정상 처리 코드를 변경하지 않는다**.

#### 사용자 상태·출퇴근 Firestore 요청 절감 — 2026-11-04, `261104 1413.zip` 기반 2차

이번 변경은 단일 기기 사용과 **레거시 출퇴근 기록 없음**을 요구 전제로 삼는다. 오늘 출근 여부 확인과 관리자 월별 달력 조회는 별개 기능이므로, 관리자 출퇴근·휴게 달력은 삭제하지 않는다. Firestore 작업을 계측하기 위한 추가 GET·UPDATE는 발생시키지 않는다. Firebase UID·인증 흐름·Plate TTS·근무 알림·Firestore Rules는 변경하지 않는다.

| 실제 호출부 | `1413.zip` 수정 전 | 수정 후 | 이유 및 효과 |
| --- | --- | --- | --- |
| `UserStatusService._safeUpdate()` | 동시 동일 요청만 공유; 직후의 동일값 순차 UPDATE는 다시 전송 | 동일 문서의 쓰기를 요청 순서대로 수행하며 **성공한 원격 필드 값**과 차이를 비교. 동일하면 `WRITE_SKIPPED`, 일부만 바뀌면 필요한 필드만 UPDATE | 서버에 이미 성공적으로 저장했다고 확인된 값만 생략. 실패 시 해당 문서의 확인 상태 무효화 |
| 동일 문서의 교차 요청 | 서로 다른 값의 UPDATE가 동시에 겹칠 수 있음 | 동일 문서 쓰기를 직렬화하고, 서로 다른 변경을 사이에 둔 동일값 요청은 임의로 합치지 않음 | `A→B→A` 요청의 최종 결과를 `B`로 바꾸지 않음 |
| 동시 동일 UPDATE | `_pendingExactUpdates`로 공유 | 가장 최근에 요청된 동일 변경인 경우만 공유, 중간에 다른 변경이 있으면 개별 실행 | 중복 제거와 요청 순서를 동시에 보존 |
| `updateLoginSession()` | 항상 UPDATE하며 사용자 진단은 쓰기 1회로 출력 | 같은 공통 상태 비교 경로를 사용하고 호출자에게 **실제 전송 여부 `bool`** 반환, 진단에도 0/1 적용 | 로그인 상태 동일 시 0회 가능. 로그인 문서가 없으면 기존대로 실패 처리하여 부분 계정 생성 금지 |
| `UserState.areaPickerCurrentArea()` | 최근 10초 조건으로 상태 확인 | **10초 기준 제거**. 저장소가 성공한 상태를 확인한 경우만 UPDATE 생략, 로컬 UI·`AreaState.updateArea`는 그대로 수행 | 단일 기기 전제. 원격 성공 증거가 없으면 기존 WRITE 수행 |
| 직접 `updateUser`·`updateTablet`·삭제 | 상태 서비스의 필드 확인 기록과 독립 | 전체 계정 문서를 별도 코드가 수정하기 전에 확인 캐시 무효화 | 잘못된 과거 필드 상태를 근거로 생략하지 않도록 방어 |
| 월별 출퇴근 GET | Repository 인스턴스별 동일 GET만 공유 | 동일 FirebaseFirestore 인스턴스의 저장소들이 진행 중인 동일 월별 문서 GET 공유 | 완료된 Future는 제거, 최신 기록을 영구 캐싱하지 않음 |
| `hasLogForDate()` | 월별 GET에서 없으면 레거시 GET | **월별 GET 1회만 확인**, 레거시 GET 제거 | 오늘 출근 기록이 없는 경우 GET 2→1 가능. 오류는 미출근으로 위장하지 않고 호출자에게 전달 |
| `getMonthlyTimes()` | 월별 + 레거시 GET 후 병합 | 월별 문서만 조회하고 기존 일자별 시각 포맷을 반환 | 관리자 달력은 유지, 상태별 GET 2→1 가능 |
| `deleteLogsForDates()` | 월별 SET·필요 시 정리 후 레거시 루트 SET | 레거시 삭제 SET 제거, 월별 기록 삭제·빈 월 정리는 유지 | 레거시 SET 1회 제거. `_deleteMonthDocIfEmpty()`의 추가 GET·조건부 DELETE는 유지 |
| `_ensureRootDoc()` | 월별 기록 저장 시 루트 메타데이터 SET | **유지** | `latestYearMonth` 등 별도 메타 필드·외부 규칙 의존 여부 미확정이므로 무리하게 삭제하지 않음 |
| Activity Center 최적화 안내 | 200ms 글자 페이드 | 페이드와 세로 미세 슬라이드 전환, `disableAnimations` 시 즉시 전환 | 새로운 화면 크기·헤더 변경 없음 |

실제로 생략된 작업은 `service=optimization`, `result=skipped`로 Journal에 기록한다. `WRITE_COALESCED`, `WRITE_SKIPPED`, `WRITE_FIELDS_REDUCED`, `MONTH_GET_COALESCED`, `LEGACY_GET_SKIPPED`, `LEGACY_WRITE_SKIPPED`는 서버 작업이 아니므로 READ·WRITE 카운터를 증가시키지 않는다. 이벤트에는 메서드 경로·필드 이름·생략 사유만 기록하며 계정 ID·필드 값·로그인 비밀번호를 새로 기록하지 않는다. 기존 개발자 모드 ON의 `STATUS` Dialog와 Activity Center에서 `debugPrint(...)` 코드로 복사할 수 있으며, OFF에도 저널 기록은 계속한다.

이 변경은 **제공된 운영 전제가 유효할 때** 월별 구조의 출퇴근 기록을 동일하게 보존한다. 실제 서버에 구형 `logs` 기록이 남아 있거나 구형 앱이 다시 기록한다면 해당 기록은 조회·삭제되지 않는다. 직접적인 계정 수정이 다른 서비스에서 병행되거나 서버 규칙·외부 관리자가 필드를 갱신하는 경우에는 상태 추적 값이 최신 서버 값과 다를 수 있다. 이번 범위는 동일 계정의 다중 기기 동시 접속을 제외하나, 전면적인 서버 동시성 제어를 제공하는 것은 아니다. 또한 Firebase SDK 호출 수 절감과 실제 청구량·결제 금액은 다른 수치다.

#### 계측 정의

| 지표·이벤트 | 측정하는 값 | 청구량 해석 시 한계 |
| --- | --- | --- |
| `GET` | 단일 문서 `get()` 완료 | 캐시 응답, 과금 읽기와 다름 |
| `QUERY` | 쿼리 `get()` 완료; 반환 문서 수·캐시 여부 | GET 호출 1회가 문서 1개 읽기라는 뜻이 아님 |
| `AGGREGATION` | `count().get()` 완료 | 인덱스 읽기 청구 단위는 계측할 수 없음 |
| `SET`, `UPDATE`, `DELETE` | 비트랜잭션 문서 작업 완료 | CREATE와 덮어쓰기·병합을 무리하게 구분하지 않음 |
| `TRANSACTION` | 트랜잭션 Future 완료·실패 | 작업 기록과 확정 문서 작업 집계는 별도로 유지 |
| `STAGE_SET`, `STAGE_UPDATE`, `STAGE_DELETE` | 트랜잭션·배치 내부에 예약한 작업 | 예약 단계에서 WRITE/DELETE에 합산하지 않음; 재시도된 트랜잭션은 마지막 성공 시도만 확정 |
| `BATCH` | 배치 커밋 Future 완료·실패 | 커밋 성공한 배치의 문서 쓰기·삭제 건수를 별도로 확정 |
| `LISTEN_START`, `LISTEN_CANCEL` | 메인 앱의 계측 Stream 실제 구독 시작·해제 | Plate TTS 포그라운드 구독은 활성 리스너 수에 포함되지 않음 |
| `SNAP` | 구독 스트림의 스냅샷 수신·문서 수·변경 수·캐시/미확정 쓰기 상태 | SNAP 1회가 청구 읽기 1회는 아님 |
| `UPLOAD`, `DOWNLOAD`, `URL_ACCESS`, `STORAGE_DELETE`, `STORAGE_LIST`, `METADATA` | Storage SDK·GCS API·공개 GCS URL 요청 | 업로드 TaskSnapshot, Media 스트림 소비 완료 및 HTTP 본문 바이트를 계측; 확정 네트워크 과금량은 아님 |
| `ERROR` | 성공 대신 실패한 작업의 오류 유형·소요 시간 | 실패했어도 일부 백엔드 작업이 발생했을 수 있음 |

상단의 각 수치는 포그라운드 Plate TTS를 제외한 앱 관측 범위에 한정된다. `READ`는 성공한 명시적 GET·QUERY 호출 수, `WRITE`는 성공한 일반 SET·CREATE·UPDATE 작업 수에 트랜잭션·배치의 **커밋 성공 문서 쓰기 수**를 더한 값, `DELETE`는 일반 문서 삭제에 커밋 성공 삭제 작업을 더한 값이다. `SNAP`은 수신 이벤트 수, `LISTEN`은 현재 활성 계측 리스너 수, `STORAGE`는 성공한 계측 객체 작업 수이다. 트랜잭션·배치 자체의 호출 이벤트와 예약 단계 `STAGE_*`는 WRITE에 중복 합산하지 않는다. **WRITE/DELETE는 계측된 클라이언트 확정 작업 수이며 프로젝트 전체 청구량을 보증하지 않는다.**

트랜잭션은 `runTrackedActivityTransaction()`으로 실행한다. `Zone`에 시도별 `STAGE_*` 작업 수를 저장하고, 재시도 중 실패한 시도의 수를 버리고 **최종 Firestore Future 성공 이후 마지막 성공 시도에서 확인된 쓰기만 `COMMITTED_TRANSACTION`으로 기록**한다. 배치는 `trackedActivityBatch()`가 `set/update/delete` 횟수를 수집하고 원래 `WriteBatch.commit()` 성공 후 `COMMITTED_BATCH`를 기록한다. 커밋 실패는 확정 집계 0건이며 기존 `BATCH`·`TRANSACTION` 로그와 예외 처리는 유지한다. SDK에 드러나지 않은 서버 내부 동작과 기존 `STAGE_*`가 삽입되지 않은 트랜잭션 작업은 관측 범위 밖일 수 있다.

`COST`는 전체 활동 로그의 별칭이 아니라 전용 분석 화면이다. `OBSERVED`는 호출 수·반환 문서 수·캐시/서버 응답·확정 쓰기·삭제·스냅샷·Storage 처리 바이트를 제시한다. `ESTIMATED`는 현재 SDK 관측값으로 확정 과금액을 산출할 수 없다는 조건을 표시하며 **임의 금액을 생성하지 않는다**. `UNAVAILABLE`에는 인덱스 읽기·Rules 의존 읽기·저장 용량·SDK 내부 재시도·다른 클라이언트 비용을 명시한다. COST 복사 버튼은 전체 이벤트가 아닌 이 세 범주의 요약을 `debugPrint(...)`로 출력한다.

Storage 작업에서는 Firebase Storage `TaskSnapshot.bytesTransferred`, `getData()` 반환 바이트, GCS `Media.stream` 실제 소비 크기, GCS 공개 URL HTTP 응답 `bodyBytes.length`를 각각 계측한다. 메타데이터만 조회하는 `storage.objects.get`은 `DOWNLOAD`이 아니라 `METADATA`로 분류한다. 요청 본문 크기·객체 크기·실제 네트워크 청구 전송량은 서로 다른 수치다. HTTP 계측은 확인된 `storage.googleapis.com` CSV 다운로드 호출부에만 연결하며 외부 이미지 로더가 자체 실행하는 다운로드는 포함하지 않을 수 있다.

Plate TTS·근무 상태 알림에 사용하는 포그라운드 Task Isolate는 Firebase Activity Center 계측 브리지를 사용하지 않는다. `foreground_task_handler.dart`에서는 `FirebaseActivityBridge.startForeground()`와 `stopForeground()` 호출을 제거하고, `main.dart`에서는 `ensureMainReceiver()`를 제거한다. 기존 `FlutterForegroundTask.initCommunicationPort()`, 근무 상태 알림 콜백, Plate TTS의 Firebase 조회·스냅샷 구독 및 소유권 관리 방식은 유지한다. 따라서 포그라운드 Plate TTS가 서버에서 문서를 읽거나 스냅샷을 수신해도 메인 화면의 READ·SNAP·LISTEN에 합산되지 않을 수 있으며, 이것을 과금 활동 0건으로 해석하지 않는다. Activity Center의 장애가 Plate TTS 실행 조건·구독·음성 안내·근무 상태 알림을 변화시키지 않는 것을 우선한다.

압축 파일 덮어쓰기는 기존 파일 삭제를 수행하지 않으므로 `lib/app/diagnostics/firebase_activity_bridge.dart`가 기존 프로젝트에 남아 있을 수 있다. 이 파일은 본 수정 후 앱 진입점과 포그라운드 핸들러에서 참조되지 않는 비사용 코드이며, 런타임에서 콜백을 등록하거나 포그라운드로 계측 메시지를 보내지 않는다. 저장소에서 파일까지 정리하려면 별도 삭제가 필요하다.

계측 작업은 `firebase_activity_meter.dart`의 메모리 링 버퍼(최근 500개 이벤트), `ValueNotifier`와 세션별 로컬 JSON Lines 저장소로 분리한다. UI는 120ms 단위로 갱신을 병합하며 서버 접근 없이 값을 표시한다. 디버그 ON에서만 각 이벤트를 `debugPrint`로 출력한다. 로그 필드는 시각·서비스·작업 종류·출처 코드 파일·결과·지연시간·문서 수·확인 가능한 바이트·캐시 여부로 제한한다. 동적 문서 ID, Google 이메일, 비밀번호, 계정 코드번호, 객체 URL, 인증 토큰은 이벤트에 기록하지 않는다.

#### 실제 수정과 커버리지

- `lib/app/diagnostics/firebase_activity_meter.dart`: 메인 앱의 시도별 커밋 확정 수, 별도 COST 요약, Stream·Future 계측. 이전 Isolate 수신 유틸리티는 실행 경로에서 사용하지 않음
- `lib/app/diagnostics/firebase_activity_center_dialog.dart`: COST 전용 분석, 개발자 권한 검증·로그 복사, 필터 전환 페이드 및 포그라운드 Plate TTS 미계측 안내
- `lib/app/diagnostics/firebase_activity_http.dart`: 공개 GCS HTTP GET 횟수·상태·본문 크기 기록
- `lib/shared/tts/application/foreground_task_handler.dart`: Activity Bridge 호출만 제거하고 기존 Plate TTS·근무 상태 알림 처리 보존
- `lib/shared/tts/data/repositories/firestore_plate_tts_listener_repository.dart`: `2050.zip`의 직접 GET·snapshots 동작 원형 복원
- `lib/main.dart`: Activity Bridge 메인 수신은 연결하지 않고, 앱 진입 시 계측 세션 시작 및 Firebase 초기화·App Check·초기 인증 작업 관측을 추가한다. 기존 통신 포트 및 근무 알림 초기화는 보존한다
- `lib/app/init/db_connection_status_section.dart`: 인증 기반 DB ON/OFF, 상시 활동 요약, `ACTIVITY CENTER` 터치 연결
- `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart`: 기존 `STATUS` 복사에 보관된 현재 세션 전체 Firebase 이벤트를 비동기로 병합하고 복사 시 개발자 권한을 재검사
- 기존 우측 상단 DB 상태부를 쓰는 7개 화면: 확장됐던 AppBar를 56dp로 원복하고 기존 화면별 최대 너비 132dp/116dp와 48dp 표시 영역을 복원. 전체 패널 탭 유지, 116×48dp 고정 UI로 계측 표시
- 기존 Firestore 호출부: 일반 읽기·쓰기·snapshots 유지, `runTrackedActivityTransaction` 30곳 및 Firestore 배치 생성 14곳을 커밋 확정 계측으로 연결
- 기존 Storage 호출부: Firebase Storage SDK 음성·백업, GCS 객체 `insert/get/list`, GCS Media 스트림, 공개 GCS CSV HTTP 다운로드 4곳 계측

해당 계측은 런타임 동작을 가로채는 전역 네트워크 프록시가 아니라, **수정한 Dart 호출부에 삽입한 계측 확장**이다. 호출부 자체가 이 파일의 범위 밖에 있으면 계측되지 않는다. Google Cloud Storage 이미지 로더 내부 요청, SDK 내부 재시도, 보안 규칙에서 발생하는 문서 접근, Firestore 인덱스 사용, Plate TTS 포그라운드 Isolate와 다른 Isolate, 다른 기기, 서버 측 작업, TTL/PITR/백업, 저장 용량 및 통신 비용은 정확히 계측하지 못한다. 집계에서 `0`은 계측된 작업이 없다는 뜻이지 전체 프로젝트 과금이 0이라는 뜻은 아니다.

Firestore 에디션 및 요금·무료 한도는 프로젝트 구성과 공식 Firebase/GCP 청구 설정에서 확인해야 한다. 최종 청구 금액과 비교할 때는 Firebase 사용량 화면 또는 Google Cloud Billing 기록을 기준으로 삼는다. 모니터링 UI가 Firestore에 활동 로그를 저장하지 않으므로 계측을 위한 별도 Firestore 문서 쓰기는 없다. 기존 READ·WRITE 실행의 실제 결과나 재시도 정책을 변경하지 않는다.

#### 저널 복구·범위별 COST·실제 페이지 조회 — `261104 0202.zip` 기준

이번 리팩터링의 목표는 기존 업무 처리나 Firestore 쓰기 정책을 바꾸지 않고 Activity Center의 기록 보존과 해석 정확도를 높이는 것이다. 계측은 `main()` 실행 직후부터 계속하며 개발자 모드 ON/OFF는 기록 여부가 아니라 상세 열람·복사 권한만 결정한다. Plate TTS 포그라운드 Isolate는 기존 안정성 우선 제외 정책을 유지한다.

| 항목 | `0202.zip` 수정 전 | 수정 후 |
| --- | --- | --- |
| 종료 기록 | `_closeApplication()`·네이티브 재시작 요청 전 `SESSION_END` 기록 | `SESSION_EXIT_PREPARED`·`SESSION_RESTART_PREPARED`로 기록, 실제 프로세스 종료 확인을 주장하지 않음 |
| 이전 세션 판정 | 마지막 이벤트가 `SESSION_END`인지에 가까운 단순 판정 | 가장 최근 이전 세션에서 종료 준비/재시작 준비 후 결과는 `PREVIOUS_SESSION_OUTCOME_UNKNOWN`, 준비 없음·실패는 `PREVIOUS_SESSION_UNCLEAN` |
| 저널 초기화 오류 | 실패 후 자동 재시도 부족 | 실패 상태에서 재초기화 가능, 1·2·4·8·16·30초를 상한으로 하는 지수 백오프 재시도 |
| JSONL 쓰기 실패 | 쓰기 전에 최대 64개 대기 이벤트를 제거하여 유실 가능 | 쓰기 성공·flush 이후 제거, 실패하면 대기열 보존, 부분 쓰기 롤백 시도 |
| 불완전한 파일 끝 | 손상 JSONL 레코드 재사용 위험 | 재초기화 때 마지막 완결된 줄 이후를 정리하고 이벤트 ID로 기록 중복 완화 |
| 대기열 상한 | 4096개 초과 시 오래된 이벤트 제거 | 이미 쓰기 중인 이벤트를 보호, 새 이벤트의 누락을 별도 계수하고 Firebase 업무는 계속 |
| COST 선택 범위 | 현재 세션 메모리 누적값이 과거·시간 범위에도 표시 | 저널에 구조화된 시각·문서 수·커밋 쓰기·캐시·바이트 필드를 바탕으로 선택 세션·기간별 계산 |
| 과거 구버전 기록 | 문자열 로그만 존재 | `schemaVersion=2` 이전 기록은 `legacyEvents`로 표시하고 수치 불완전성 안내 |
| COST 화면과 복사 | 선택 조건과 결과가 불일치할 수 있음 | 화면에 사용한 동일한 COST 집계 스냅샷을 클립보드용 `debugPrint(...)` 문자열로 변환 |
| 보관 로그 페이지 | 전체 JSONL을 `List<String>`으로 읽은 다음 100건만 표시 | 파일을 뒤에서부터 읽고 100건만 반환하는 커서 조회, 시작 파일 크기를 다음 페이지까지 유지 |
| 전체 로그 복사 | 전체 보관 범위의 JSONL을 순차 읽어 복사 | 유지, 페이지 조회와 독립적인 경로 사용 |

새 기록의 `schemaVersion=2`에는 `eventId`, `timeMs`, `sessionId`, `service`, `operation`, `result`, `documents`, `bytes`, `fromCache`, `committedWrites`, `committedDeletes`, 마스킹된 진단 `line`을 저장한다. 과거 파일은 삭제하거나 소급 변조하지 않는다. 과거 기록의 작업명과 성공 여부는 일부 합산할 수 있지만 구조화되지 않은 필드는 복원할 수 없고, 저장 실패나 보관 한도 삭제된 이벤트도 복구할 수 없다. 따라서 COST는 **선택한 범위에서 실제 보관한 앱 관측값**이며 전체 Firebase 청구량이 아니다. 현재 활성 LISTEN 수는 과거 시점에 재현 가능한 값으로 단정하지 않고, 선택 범위에서 관측한 LISTEN 시작·해제 이벤트 수를 별도로 표시한다.

저널 복구는 최선의 노력 방식이다. 디스크 공간 부족, 장기 접근 오류, 강제 종료, 손상된 세그먼트 및 4096개 대기열 초과 상황에서는 기록 손실이 여전히 발생할 수 있다. `droppedEvents`, `droppedFiles`, `writeErrors`, `legacyEvents`, 저장 가능 상태를 통해 이러한 한계를 표시한다. 계측 기록 때문에 신규 Firestore 읽기·쓰기 또는 GCS 객체 작업을 만들지 않는다.

최근 500개 메모리 화면, 우측 상단 56dp AppBar·116×48dp 관측 패널, 상태 점·카운터·Dialog 애니메이션과 보관 페이지 `AnimatedSwitcher` 180ms 전환(모션 감소 시 0ms), 개발자 `STATUS`의 비동기 `debugPrint 코드 복사` 및 복사 직전 권한 검사는 그대로 유지한다. 기존 `AppExitService`의 종료 준비·네이티브 종료·실패 시 알림 복구 순서는 변경하지 않으며 기록하는 이벤트 이름만 바꾼다.

## 7. Firestore Rules 및 보안 평가

다음은 **사용자가 제공한 Rules 텍스트**를 근거로 하며 배포 여부는 미확인이다.

| 경로 | 공개/인증 정책 | 검토 결과 |
| --- | --- | --- |
| `divisions`, `areas`, `user_accounts`, `user_account_codes`, `user_accounts_show` | 로그인한 Firebase 사용자에게 읽기·쓰기 허용 | 개발자 도움말의 UI 조건이나 클라이언트 승인만으로는 타 사용자의 직접 SDK 쓰기를 막지 못함 |
| 대부분의 업무 컬렉션 | `request.auth != null` | 회사·현장·역할 간 서버 권한 분리가 없음 |
| `/{path=**}/plates/{plateDocId}` | 누구나 읽기 허용 | GCS 이미지 `publicRead`와는 **별도의 문서 공개** 정책임 |
| `usage_daily/...` | 조건부 쓰기, 읽기·삭제 차단 | UID-문서 user 일치 검사가 없고 이벤트 생성량 자체는 제한하지 않음 |
| 기타 명시되지 않은 경로 | 거부 | 기본 차단 유지 |

이번 변경은 기존 Rules를 수정하거나 Cloud Functions를 추가하지 않는다. **보안 판정:** 완전히 통제된 개발·테스트 환경에서 초기화 기능의 확인용으로는 사용할 수 있다. 그러나 제공된 Rules가 운영 서버에 적용된 채 실제 사용자·차량·회사 데이터를 저장하는 경우, Firebase에 로그인한 다른 사용자의 데이터 접근·수정 위험이 있으므로 공개 운영 전 서버 권한 규칙 검토가 필수다. 도움말은 개발자 승인과 인증 이메일 일치 여부를 확인하지만 서버의 독립적인 관리자 권한 검증을 대신할 수 없다.

Firebase UID를 업무 accountId로 바꾸거나 GCS `publicRead`를 제거하는 것은 해결책의 전제가 아니다. 실제 위협과 무관한 보안 강화는 보류한다. 공개 이미지에 민감한 자료를 저장하지 않도록 운영 데이터는 별도 검증한다.

## 8. 비용·사용량 평가

| 동작 | Firestore/서비스 작업 | 비용 정책 |
| --- | --- | --- |
| 도움말 아이콘 표시, 애니메이션, 제목 탭·로그 복사 | 로컬 UI·클립보드, Firestore 읽기/쓰기 없음 | 최적화 불필요 |
| APP RESTART 제목 5회 탭·건너뛰기 | 로컬 상태·진단 로그·내비게이션, 직접적인 Firestore 쓰기 없음 | 기존 업무 화면 진입 후 정상 조회는 별도 비용 발생 가능 |
| 개발자 로그인 성공 후 디버그 ON | 승인 검사와 로컬 SharedPreferences 갱신, 추가 Firestore 쓰기 없음 | 실패 시 추가 인증·업무 조회를 수행하지 않고 로그인 완료 차단 |
| 첫 실행에서 이미 있는 `divisions/dev` 검사 | 트랜잭션 문서 읽기, 회사 쓰기 0 | 기존 버전 보존 및 불필요한 쓰기 방지 |
| 없는 지역·메타 생성 | 각 문서 1회 쓰기 | 최초 실행만 |
| 신규 dev 계정 | 원본·코드 예약·메타 갱신·사용자 View, 총 4개 문서 쓰기 | 기존 생성 서비스를 재사용. 중복 조회·트랜잭션 재시도 가능 |
| 최초 정상 생성의 핵심 쓰기 | 회사 존재 시 6회, 회사 부재 시 7회 | 읽기·트랜잭션 재시도·복구는 별도. 이것은 실제 청구 실측치가 아님 |
| 완전한 상태에서 재실행 | 정상 흐름에서 쓰기 0, 확인 읽기 발생 | 정기 실행/자동 리스너 없음 |
| 계정 연결 | Google/Firebase 인증 API, 별도 Firestore 사용자 문서 생성 없음 | 요금제에 따라 인증 비용 정책 별도 |
| 계정 중복 검사 | `DevUserWriteService`가 `codeNumber`, `phone`, `handle` 쿼리 실행 | 비어 있는 쿼리에도 최소 읽기 과금 가능 |
| 실시간 차량·음성 수신 | Firestore `snapshots()` 읽기 및 재연결 | 이용량에 따라 과금, 정상 기능이므로 유지 |
| 음성 전송 후 정리 | 전송마다 정리 대상 최대 32개 조회 | 전송량 증가 시 실제 비용을 계측하고 최적화 판단 |
| GCS 공개 이미지 | 저장·요청·다운로드 네트워크 사용량 | `publicRead` 유지, 전송 트래픽 관찰 |

### 실제 사용자 상태·출퇴근 호출 최적화 비용 비교 — 2차

| 동작 | `1413.zip` 기존 SDK 작업 | 2차 변경 후 | 적용 조건 |
| --- | --- | --- | --- |
| 오늘 출근 기록이 없는 사용자 | 월별 GET 1 + 레거시 GET 1 | **월별 GET 1** | 레거시 출퇴근 데이터가 없다는 전제 |
| 이미 오늘 출근한 사용자 | 월별 GET 1 | 월별 GET 1 | 기존 로컬 출근 기록 캐시 사용 시 GET 0 유지 |
| 관리자 출퇴근 달력의 월별 출근·퇴근 조회 | 출근/퇴근 월별 GET 2 + 레거시 GET 최대 2 | **월별 GET 2** | 달력 UI·시각 결과 유지 |
| 관리자 휴게 달력 | 월별 GET 1 + 레거시 GET 1 가능 | **월별 GET 1** | 같은 월·휴게 상태 기준 |
| 출퇴근 날짜 삭제 | 월별 SET + 레거시 SET + 빈 월 확인 GET 등 | **레거시 SET 1건 제거** | 빈 월 GET·조건부 DELETE는 그대로 |
| 동일 계정 상태를 연속으로 두 번 저장 | UPDATE 2 가능 | 첫 성공 후 동일 필드면 UPDATE 1 | 중간에 다른 상태 변경 없고 성공한 원격 쓰기 증거가 있음 |
| 동일 문서에 A→B→A 순서의 서로 다른 변경 | UPDATE 3 | UPDATE 3 | 최종 상태 보존을 위해 모두 수행 |
| 로그인 상태가 이미 이번 실행에서 확인됨 | UPDATE 1 | UPDATE 0 가능 | `UserStatusService`의 필드별 원격 성공 상태가 존재 |
| 첫 로그인 상태 쓰기·근무 ON/OFF 실제 변경 | UPDATE 1 | UPDATE 1 | 초기 원격 확인이 없거나 값이 실제로 다름 |
| 월별 문서 동시 조회(서로 다른 Repository 객체) | GET 2 가능 | 진행 중이면 GET 1 | 같은 FirebaseFirestore 객체·문서·연월 |
| 사용자 상태 UPDATE 4건이 전부 다른 변경 | UPDATE 4 | UPDATE 4 | 무조건 4→1로 줄이지 않음 |

기존 로그의 UPDATE 4건이 실제 중복이라고 확정된 것은 아니다. 2차 수정은 원인을 구분하고 가능한 연속 중복을 제거하도록 코드 경로를 바꾼 것이다. Firestore Standard의 기본 문서 단위와 실제 청구 금액, Security Rules 의존 읽기·네트워크 비용은 분리해 평가한다. 출퇴근 월별 문서 하나의 GET은 오늘 날짜만 읽었다고 과금 단위가 더 줄어드는 것이 아니라, **존재하지 않는 레거시 위치에 대한 두 번째 GET을 제거**했기 때문에 절감된다.

계정 생성 10 Reads 목표 등의 수치는 실제 SDK/서버 계측 전에는 보증하지 않는다. SDK 호출 횟수와 청구 읽기 수는 다를 수 있다. Firestore 쿼리의 빈 결과, 트랜잭션 재시도, 리스너 재연결, Rules 의존 문서 읽기 등에 따라 비용이 추가된다. 로그인 Dialog의 연결 상태 표시 자체는 실시간 Firestore 구독이 아니다.

권장 실측: Firebase Console/Google Cloud Billing에서 기능별 문서 읽기·쓰기·삭제, 인증 사용자 수, GCS 저장·전송을 확인한다. 사용량이 적은 개발 단계에서 비용이 실제로 증가했다는 근거 없이 정상 기능을 축소하지 않는다. 예산 알림은 이상 징후 감지용이며 자동 과금 중단을 보장하지 않는다.

공식 문서: https://firebase.google.com/docs/firestore/pricing · https://firebase.google.com/pricing · https://cloud.google.com/storage/pricing · https://firebase.google.com/docs/firestore/security/rules-structure

## 9. 실행 검증 시나리오

| 입력·서버 상태 | 기대 동작 |
| --- | --- |
| 로그인 계정 비연결 | Dialog 표시; 도움말을 누르면 연결 절차를 거쳐 유효한 세션 확보 후 생성. 취소 시 쓰기 없음 |
| 모든 계정에서 개발자 비밀번호 모드 OFF | 헤더 오른쪽 도움말 없음 |
| 일반 계정에서 빈 로그인 버튼 5회 후 개발자 승인 | 개발자 인증 배너 + 도움말 표시; 일반형 dev 초기화 실행 가능 |
| 개인형에서 빈 로그인 버튼 5회 후 개발자 승인 | 개발자 인증 배너 표시, 도움말 숨김; 기존 개인형 개발자 로그인 유지 |
| 태블릿형에서 빈 로그인 버튼 3회 후 개발자 승인 | 개발자 인증 배너 표시, 도움말 숨김; 기존 태블릿형 개발자 로그인 유지 |
| 개인형·태블릿형에서 개발 초기화 함수 실행 조건 검사 | 즉시 종료, 이 기능으로 인한 Firestore 조회·쓰기는 없음 |
| 기존 `divisions/dev` 존재 | `accountWriteVersion=11`, `areaConfigVersion=3`, `initialAdminAccountId=aef260e9aa1-dev`, 생성 시각 등 보존 |
| `accountWriteLocked=true` | 초기화 중단, 회사 원본 유지 |
| 지역·메타·계정 모두 없음 | 누락 문서만 트랜잭션 생성, 계정 원본/예약/상위 메타/하위 View 생성 |
| 도움말 두 번 실행 | 최초 1회만 생성, 두 번째는 존재 확인 후 쓰기 없음 |
| 코드 예약 충돌·계정 이메일 불일치 | 자동 덮어쓰기 금지, 오류 표시 |
| 계정 원본만 있고 View 누락/집계 0 | 조건 충족 시 View와 카운터 복구 |
| 원본과 View 또는 집계 충돌 | 자동 복구 금지, 기존 자료 보존 |
| 회사·지역 일부만 생성 후 네트워크 오류 | 재실행 시 남은 데이터 보존, 누락 단계만 수행 |
| 제목 연속 5회 탭 | `debugPrint(...)` 복사, 도움말 실행과 무관 |
| 전역 개발자 모드 ON에서 `STATUS` | 기존 진단 Dialog와 `debugPrint 코드 복사` 사용 가능 |
| 애니메이션 감소 설정 | 효과가 즉시 전환되어도 기능 유지 |
| 작업 완료 후 기존 로그인 | 이름·코드 입력 및 이메일 일치 검증 유지, 개발자 비밀번호는 별도 요건 |
| APP RESTART 제목 4회 탭 | Dialog 유지, 네이티브 재시작 없음, 업무 화면 이동 없음 |
| APP RESTART 제목 5회 탭 | 닫힘 모션·진단 이벤트, 재시작 스킵, 기존 업무 목적지로 이동 |
| APP RESTART 제목 탭 간격 2초 초과 | 연속 입력 카운터 초기화 |
| APP RESTART `재시작` 버튼 | 기존 플랫폼 재시작 흐름 유지, 제목 5회 탭과 중복 실행 없음 |
| 개발자 비밀번호 검증 성공 + 승인 유효 | 디버그 ON, 공유 ValueNotifier 반영, `STATUS` 및 `debugPrint 코드 복사` 사용 가능 |
| 개발자 비밀번호 검증 실패 또는 승인 세션 만료 | 로그인 완료·디버그 자동 활성화 없음 |
| 개발자 디버그 활성화 자체 실패 | 기존 인증을 완료한 것으로 처리하지 않으며 오류 표시 후 재시도 가능 |
| 일반 계정의 Google 방식 로그인 | 디버그 자동 ON 없음, 기존 APP RESTART 조건 유지 |
| 접근성 모션 감소 설정 + APP RESTART 스킵 | 닫힘 시간 0이어도 업무 화면 진입 가능 |


### AppBar 56dp 복원 및 우측 Activity Center UI 검증

| 테스트 화면·상황 | 통과 기준 |
| --- | --- |
| 본사·Single·Double·Triple·Minor 대시보드 | 원래 기본 AppBar 56dp 유지, 기존 좌측 로고·중앙 터미널 버튼 위치와 본문 시작점 변화 없음 |
| Single 내부 | `toolbarHeight: kToolbarHeight`, 우측 최대 너비 116dp, 상태 영역 48dp, 본문 위치 동일 |
| 주차 완료 화면 | `toolbarHeight: kToolbarHeight`, 우측 최대 너비 132dp, 상태 영역 48dp, 조건부 DB 상태 표시 정상 |
| 일반 화면 우측 표시 | 최대 너비 132dp, 공통 패널 116×48dp, 상태·카운터 총 4행이 헤더를 확장하지 않음 |
| DB 인증 ON/OFF 전환 | 상태 값·점 색상 전환이 헤더 크기를 바꾸지 않음 |
| READ/WRITE/DELETE/SNAP/LISTEN/STORAGE 갱신 | R/W/D, SN/L/ST 2행의 수치가 갱신되며 높이·본문 시작 위치 고정 |
| 카운터 999 → 1.0K 및 큰 값 | 축약값이 패널 안에 표시되고 상세 Dialog에는 정확한 원본 정수가 표시됨 |
| 디버그 OFF | 우측 카운터는 상시 표시, 탭해도 상세 Dialog는 접근 거부 |
| 디버그 ON | 패널 전체 탭으로 상세 Dialog 열람·클립보드 복사 가능 |
| 디버그 ON에서 기존 `STATUS` | Firebase 활동을 포함한 `debugPrint(...)` 코드 복사 유지 |
| 좁은 화면·글꼴 확대·화면 판독기 | 우측 패널의 렌더 높이 고정, 중앙 터미널 버튼 터치 가능, 의미 있는 전체 계측 명칭 전달 |
| 애니메이션 감소 설정 | 상태·숫자 애니메이션 0ms 처리, 앱바 높이 유지 |

### Plate TTS 안정성 우선 원복 범위

| 구성요소 | `2347.zip` 수정 전 | 원복 후 |
| --- | --- | --- |
| `main.dart` | Activity Bridge 수신 콜백 등록 | 등록 제거. 기본 근무 상태·알림 수신은 유지 |
| `foreground_task_handler.dart` | 계측 브리지 시작과 종료 호출 3곳 | 해당 호출만 제거. TTS 시작·중지·소유권·근무 상태 처리 보존 |
| `firestore_plate_tts_listener_repository.dart` | Firestore `get()`·`snapshots()` 계측 확장 적용 | 원래 `get()`·`snapshots()` 호출로 복원 |
| Activity Center | 메인 + 전달된 포그라운드 활동 일부 병합 | 메인 앱에서 관측한 활동만 표시. 원격 TTS 활동은 미계측 |
| COST · `STATUS` | 분석·진단 로그 복사 | 유지. COST에 포그라운드 TTS 미계측 경계 명시 |
| 애니메이션 | 기존 요약 카운터·Dialog 페이드 | 유지하고 필터 변경 텍스트 전환 추가. 접근성 설정 시 전환 시간 0 |

### Firebase Activity Center 검증 시나리오

| 수행 | 기대되는 결과 |
| --- | --- |
| 디버그 OFF로 본사·Single/Double/Triple/Minor·내부·주차 완료 화면 표시 | 우측 `LIVE DB`·`STORAGE DB`와 READ/WRITE/DELETE/SNAP/LISTEN/STORAGE 상시 보임 |
| 디버그 OFF에서 실제 조회·저장·실시간 수신 | 상단 집계 증가; 센터 상세는 열리지 않음 |
| 개발자 비밀번호 로그인 성공 및 디버그 ON | Activity Center 열림, 필터·로그 복사 및 STATUS 진단 복사 가능 |
| 단일 문서 GET, Query GET, count GET | 조회 결과·집계 구분 및 성공/실패 기록 |
| 트랜잭션 실패 또는 재시도 | 예약 작업은 STAGE로 남고 커밋되지 않은 작업은 WRITE 청구로 합산하지 않음 |
| Firebase Storage 업로드와 GCS 목록·다운로드 | 작업별 STORAGE 카운터와 확인 가능한 바이트 기록 |
| 디버그 ON → OFF | 상단 요약 유지, 상세 Dialog 접근·복사 차단 |
| 화면 이탈·리스너 취소 | 계측된 활성 LISTEN 수 감소 |
| 트랜잭션 STAGE 4개 후 최종 성공 | WRITE +4, 재시도 횟수와 관계없이 한 번만 확정 |
| 트랜잭션 STAGE 4개 후 최종 실패 | WRITE +0, 기존 실패 예외 유지 |
| 배치 SET 3건·DELETE 2건 성공 | WRITE +3, DELETE +2; 실패 시 확정 작업 +0 |
| COST 선택·복사 | OBSERVED / ESTIMATED / UNAVAILABLE 별도 표시와 요약 debugPrint 복사 |
| GCS 객체 메타데이터 확인 | METADATA 증가, DOWNLOAD 증가 없음 |
| GCS 공개 CSV HTTP GET 4개 호출부 | URL_ACCESS와 실제 받은 bodyBytes 길이 기록, 오류 상태 보존 |
| GCS Media CSV 스트림 완료 | 데이터 수신 완료 시 다운로드 크기 기록, 중복 성공 기록 없음 |
| Plate TTS 포그라운드 시작·차량 변경 | 기존 Firestore 구독과 음성 안내가 이전과 동일하게 작동 |
| 포그라운드 Plate TTS에서 SNAP 수신 | 메인 Meter에 원격 이벤트를 전달하지 않고 READ·SNAP·LISTEN에 합산하지 않음 |
| 포그라운드 Task 종료·재시작 | 기존 TTS 세션·소유권 및 근무 상태 알림 절차 유지 |
| 메인 앱에서 Firestore 스냅샷 수신 | 메인 SNAP 증가, 포그라운드 구독에 영향 없음 |
| 다른 Isolate, 공개 GCS 이미지 URL 사용 | 연결되지 않은 경로는 미계측일 수 있음을 문서와 대조 |
| 접근성 애니메이션 감소 | 패널 카운터·활동 Dialog 애니메이션 시간 단축 |

### 앱 전체 실행 세션·로컬 로그·복사 테스트

| 테스트 | 통과 조건 |
| --- | --- |
| 앱 Cold Start | `SESSION_START`가 `INITIALIZE_APP`보다 먼저 저장되며 개발자 OFF에서도 기록 |
| App Check·Google 초기화·Firebase 인증 | 원문 토큰/UID 없이 결과와 소요 시간 기록, 기존 로그인 흐름 동일 |
| 초기 로그인 이전 Firestore 조회 | 실제 계측 호출부를 통해 발생한 경우 로그와 상단 수치에 반영 |
| 이벤트 501개 이상 | 실시간 목록 최대 500개, 보관 기록에는 보관 한도 내 이전 이벤트 존재 |
| 100건 단위 보관 목록 | JSONL 전체 메모리 적재 없이 역방향 스트림으로 최대 100개 읽기, 처음 조회한 파일 길이·커서로 안정적인 이전·다음 페이지 이동 |
| 앱 백그라운드·복귀 | 동일 실행 세션 유지, 새 `SESSION_START`가 중복 기록되지 않음 |
| 로그아웃·재로그인 | 앱 실행 세션 유지, Auth 이벤트 별도 기록 |
| 정상 종료 요청 | `SESSION_EXIT_REQUESTED` 후 `SESSION_EXIT_PREPARED`와 저널 flush를 시도하고, 실제 종료 성공을 확정 이벤트로 오기록하지 않음 |
| 재시작 성공·실패 | 기존 네이티브 재시작 동작 유지, 실패 시 로그 작성·서비스 복구 유지 |
| 강제 종료·이전 세션 미종료 | 마지막 저장된 이벤트 보존 및 다음 실행에서 미종료 가능성 기록 |
| 7일·20MiB 초과 | 오래된 조각 정리, 누락된 파일 수와 저장 오류 표시 |
| 저장소 권한/쓰기 오류 | 기존 Firebase 요청 정상 진행, 대기열 보호·부분 쓰기 정리·재초기화·제한적 재시도로 복구, 잔여 유실 건수 표시 |
| 디버그 OFF → ON | 앱 실행부터 기록된 로컬 로그를 Activity Center에서 조회 가능 |
| Activity Center 복사 | 선택 세션·기간·필터의 `debugPrint(...)` 코드 복사, 권한 재검사 |
| 기존 개발자 `STATUS` | 복사 버튼 터치 시 최신 보관 Firebase 기록과 기존 진단 병합, 모드 OFF면 복사 차단 |
| 보관 기록 화면 전환 | `AnimatedSwitcher` 페이드, `disableAnimations` 시 0ms, 56dp AppBar 불변 |
| Plate TTS·근무 상태 알림 | 포그라운드 브리지 미연결 유지, 기존 동작 정상 |

### 2026-11-04 사용자 상태·출퇴근 비용 최적화 2차 검증

| 테스트 | 통과 기준 |
| --- | --- |
| 첫 로그인·세션 복원 | 인증·지역·근무 상태가 기존과 동일, 실제 원격 UPDATE가 필요하면 1건 전송 |
| 로그인 세션 동일값 순차 재요청 | 첫 UPDATE 성공 후 두 번째는 `WRITE_SKIPPED`, 로그인 Dialog 진단의 `firebaseWrite=0` |
| 로그인 대상 문서 없음 | 새 부분 계정을 만들지 않고 기존과 동일하게 실패 전달 |
| 동일 문서 A→B→A | 3개의 순서를 보존하여 최종 A가 서버에 남음 |
| 동시에 동일 UPDATE | 최종 서버 UPDATE 1건, 대기 호출자도 같은 성공·실패 전달 |
| 일부 필드만 이미 같은 UPDATE | 변경된 필드만 서버 전송하고 `WRITE_FIELDS_REDUCED` 기록 |
| 상태 UPDATE 실패·재호출 | 확인 상태 무효화, 실패를 생략으로 처리하지 않음 |
| 계정 전체 모델 직접 수정·삭제 | 확인된 필드 상태 초기화, 이후 필수 UPDATE 생략 금지 |
| 지역 재선택 | 10초에 의존하지 않고 저장소의 성공한 필드 상태로 판단, 로컬 화면·애니메이션 유지 |
| 오늘 처음 출근 여부 | 월별 문서 GET 한 번, 빈 결과면 출근 전 상태 유지 |
| 이미 출근한 사용자 | 월별 문서의 오늘 날짜 기록을 정상 감지하고 중복 출근 방지 |
| 출퇴근 GET 서버 실패 | 기록 없음(`false`)으로 오인하지 않고 실패 전파, 성공한 빈 결과만 `false` |
| 서로 다른 Repository의 동일 월 동시 GET | 요청 중에만 공유해 실제 GET 1회, 완료 후 재요청은 신규 GET |
| 관리자 출퇴근·휴게 달력 | 출근/퇴근/휴게의 월별 정보·기존 페이드·전환 동일, 레거시 GET 없음 |
| 출퇴근 날짜 수정·삭제 | 월별 필드 갱신/삭제와 빈 월 삭제 기능 유지, 레거시 SET 없음 |
| 진단과 비용 | 최적화 `result=skipped`는 READ·WRITE에 추가되지 않고 `STATUS`에서 개발자 ON일 때만 복사 가능 |
| 애니메이션 접근성 | `AnimatedSwitcher` 페이드/슬라이드, `MediaQuery.disableAnimations` 시 전환 0ms |
| 다른 기능 회귀 | 56dp AppBar, 116×48dp 패널, Plate TTS, 근무 알림, UID, 기존 Rules·GCS 공개 읽기 변경 없음 |

실제 SDK/Android 환경에서 위 시나리오를 실행하기 전에는 빌드 성공·동시성·비용 절감량이 검증됐다고 주장하지 않는다.

### 2026-11-04 Journal 운영 안정성 및 COST 범위 검증

| 테스트 | 통과 조건 |
| --- | --- |
| `main()` 초기 계측 | Firebase 초기화보다 먼저 `SESSION_START` 기록, 디버그 OFF에서도 관측 지속 |
| 종료·재시작 준비 | `SESSION_EXIT_PREPARED` 또는 `SESSION_RESTART_PREPARED`로 저장, 실제 종료 확정으로 오인하지 않음 |
| 종료·재시작 실패 | `SESSION_EXIT_FAILED`/`SESSION_RESTART_FAILED`, 기존 근무 상태·서비스 복구 유지 |
| 이전 세션 상태 | 정상 종료 준비 기록이 없는 경우 `PREVIOUS_SESSION_UNCLEAN`, 준비 후 결과 미확인 경우 `PREVIOUS_SESSION_OUTCOME_UNKNOWN` |
| 최초 저널 초기화 오류 | 지수 백오프로 자동 재시도, 앱 실행·Firebase 업무에는 영향 없음 |
| JSONL 부분 쓰기 | 마지막 불완전 레코드 정리, 쓰기 전 대기열 제거 금지, 기록 이벤트 ID 대조 |
| 저장 중 대기열 4096개 초과 | 쓰기 중인 항목을 보호하고 유실 수를 기록, 실패 후 가능한 이벤트부터 순서대로 저장 |
| 현재 세션 COST | 선택 세션의 JSONL 기록에서 계산, 현재 메모리 이벤트와 혼동하지 않음 |
| 과거 세션·전체 세션 COST | 해당 보관 세션만 또는 모든 보관 세션 합산, 화면과 클립보드의 집계 기준 동일 |
| 최근 15분·1시간 COST | 선택 시각의 구조화 이벤트만 포함, 다른 기간 누적값 제외 |
| 구조화 이전 JSONL | `legacyEvents`로 구분, 문서 수·커밋 확정 수·바이트를 임의로 0의 근거로 단정하지 않음 |
| 보관 파일 삭제·쓰기 오류 | 분석 불완전 상태 표시, 공식 청구량으로 오인하지 않음 |
| 100건 페이지 | 파일 최신순 역방향 조회, 전체 파일 목록 메모리 적재 없음 |
| 페이지 전환 중 로그 추가 | 조회 시작 시점의 파일 길이를 커서에 보존하여 기존 페이지에 중복·누락이 없도록 함 |
| `COST` 개발자 복사 | 선택한 범위에 계산된 분석 스냅샷을 `debugPrint(...)`로 복사, 복사 직전 개발자 권한 재확인 |
| Plate TTS·헤더·애니메이션 | 기존 Foreground Task 미계측 정책, 56dp AppBar, 116×48dp 패널, `AnimatedSwitcher`·모션 감소 처리 유지 |

## 10. 검증 상태 및 배포 경계

**현재 헤더 복원 패치의 기준은 `261104 0027.zip`이다.** 변경 범위는 공통 AppBar 상태 패널 1개, AppBar를 포함한 화면 7개와 본 README다. Firebase Activity Meter, COST Dialog, Plate TTS, 포그라운드 서비스, Firestore Rules, 개발자 `STATUS`는 이번 헤더 수정에서 변경하지 않는다. 완전한 Flutter 프로젝트와 기기에서 56dp 헤더·48dp 패널·터치 겹침 및 다크 모드·글꼴 확대를 검증해야 한다. 해당 실행 검증 전에는 실제 화면에서 픽셀 단위로 동일함을 확정하지 않는다.

앞선 Plate TTS 계측 분리는 `261103 2347.zip`을 기준으로 제공된 Dart 소스의 **정적 수정**이다. 수정된 파일만 원본 상대 경로를 유지한 ZIP으로 제공한다. Dart 파일에는 주석을 포함하지 않고 새 `hintText`를 넣지 않는다. 초기 로그인, APP RESTART, 개발자 디버그 ON, 우측 상단 상태·Activity Center 상시 표시, 애니메이션, `STATUS`의 `debugPrint 코드 복사`를 보존한다. Firestore Rules, Firebase UID 체계, GCS `publicRead`, Cloud Functions 배제, 기존 `divisions/dev` 원본 데이터는 변경하지 않는다.

기준 ZIP은 Flutter SDK·완전한 Android 프로젝트·`pubspec.yaml`을 포함하지 않으므로 변경 파일을 기존 **완전한 Flutter 프로젝트 루트에 덮어써야 한다**. 정적 경로 대조와 구조 검증은 컴파일·실기기 검증을 대신하지 않는다. 현재 환경에 Dart/Flutter SDK가 없으므로 `dart format`, `flutter analyze`, Android 빌드와 실제 Firebase 트랜잭션 재시도·배치 실패·GCS 스트림 및 Plate TTS·근무 상태 알림의 실기기 회귀 동작을 검증하지 못했다. 배포 전에 테스트 Firebase 환경과 Android 실기기에서 9장의 시나리오를 확인해야 한다.

### 2026-11-04 Activity Center 헤더 레이아웃 복원

| 실제 변경 파일 | 변경 전 | 변경 후 |
| --- | --- | --- |
| `lib/app/init/db_connection_status_section.dart` | 세로로 긴 163dp 폭 상태·활동 패널 | 116×48dp 4행 고정 패널, R/W/D·SN/L/ST 숫자 축약, 전체 접근성 라벨, 탭·페이드 애니메이션 유지 |
| `lib/features/dashboard/pages/common/headquarter_page.dart` | `toolbarHeight: 128`, 우측 116dp·168dp | 기본 AppBar 56dp, 우측 48dp·132dp |
| `lib/features/dashboard/pages/single/widgets/single_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/dashboard/pages/double/widgets/double_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/dashboard/pages/triple/widgets/triple_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/dashboard/pages/minor/widgets/minor_dash_board.dart` | 동일 | 동일 복원 |
| `lib/features/mode_single/page/single_inside_screen.dart` | `toolbarHeight: 128`, 우측 116dp·168dp | `kToolbarHeight`, 우측 48dp·116dp |
| `lib/shared/page/pages/common/parking_completed_page/parking_completed_page_shell.dart` | `toolbarHeight: 128`, 우측 116dp·168dp | `kToolbarHeight`, 우측 48dp·132dp |

본 변경에서 대시보드 5개 화면의 우측 바깥 여백은 상하 각 4dp로 조정해 48dp 패널과 합쳐 정확히 56dp 높이 안에 배치한다. Activity Center Dialog는 별도 화면이므로 AppBar 높이를 변경하지 않는다. `R/W/D/SN/L/ST`는 시각적 축약이며 내부 계측 데이터 및 `debugPrint` 복사 형식은 바꾸지 않는다. 신규 `hintText`·수정 Dart 주석은 없다. 정적 파일 검사만으로 실제 기기 레이아웃·컴파일 성공을 보장하지 않으며, 9장의 7개 화면 회귀 검증을 배포 전 수행한다.

### 2026-11-04 Flutter 분석기 오류·경고 교정

이번 오류 교정의 적용 기준은 `261104 0020.zip`이며, 업무 데이터·Plate TTS·근무 상태 알림 실행 코드는 변경하지 않는다.

| 파일 | 변경 전 | 변경 후 | 근거 |
| --- | --- | --- | --- |
| `lib/app/diagnostics/firebase_activity_meter.dart` | `FirebaseActivityWriteBatch.update<T>(DocumentReference<T>, T)`가 존재하지 않는 `WriteBatch.update<T>()`를 호출 | `update(DocumentReference<Object?>, Map<String, dynamic>)`로 SDK 서명에 맞춰 위임 | FlutterFire `WriteBatch.update`는 제네릭이 아니며 업데이트 본문은 `Map<String, dynamic>` |
| `lib/app/init/db_connection_status_section.dart` | 사용하지 않는 `_AppBarStatusChip` 선언 잔존 | 미사용 클래스 삭제 | 상단 요약은 기존 `_ActivityConnectionLine`, `_ActivityCountsLine`과 `AnimatedSwitcher`를 사용 |
| `lib/shared/plate/widgets/departure_completed_history_workspace.dart` | 사용하지 않는 `package:http/http.dart` import | 해당 import 삭제 | GCS 공개 URL GET은 `FirebaseActivityHttp.get()`에서 처리 |

교정 후 배치 업데이트 데이터는 기존과 동일하게 Firestore SDK에 전달된다. `_writes` 증가는 실제 `WriteBatch.update()` 호출이 예외 없이 반환된 이후에만 수행하며, 확정 집계는 기존과 같이 `commit()` 성공 후 기록한다. 상단 DB 상태·계측 요약과 COST 애니메이션, 개발자 모드 ON에서의 `STATUS` 및 `debugPrint(...)` 코드 클립보드 복사는 그대로 유지한다. 새 `hintText`나 Dart 주석을 추가하지 않는다.

이 패치는 제공된 Flutter 분석기 진단 두 오류와 두 경고를 대상으로 한 최소 수정이다. 현재 작업 환경에 Flutter·Dart SDK가 없어 `flutter analyze`와 실기기 실행은 수행하지 못했다. 완전한 프로젝트에서 `flutter analyze`로 네 진단이 해소되는지 확인해야 한다.

### 2026-11-04 앱 실행 전체 구간 Firebase Activity Journal 추가

**변경 기준 ZIP: `261104 0117.zip`.** 수정 범위는 계측 엔진과 신규 Journal, `main.dart` 초기화, Firebase Auth Bridge, 앱 종료 서비스, Activity Center Dialog, 터미널 `STATUS`, 개발자 전용 Status Dialog 복사 경로 및 README다. 헤더는 56dp, 우측 패널은 116×48dp를 유지하며 Plate TTS·포그라운드 서비스 및 Firestore Rules는 변경하지 않는다.

| 수정 파일 | 이전 | 개선 후 |
| --- | --- | --- |
| `lib/app/diagnostics/firebase_activity_journal.dart` (신규) | 메모리 500개 이외 이벤트 보관 없음 | 앱 전용 JSON Lines 기록, 2MiB 조각·7일·20MiB 정리, 보관 세션 조회·복사 |
| `lib/app/diagnostics/firebase_activity_meter.dart` | 실시간 계측과 최근 500개 복사 | `SESSION_START`·저널 기록·세션 전체 비동기 export, 기존 비용 카운터 유지 |
| `lib/main.dart` | 날짜·앱 초기화 후 Firebase 초기화 | 바인딩 직후 시작 기록, Firebase Core·App Check·초기 인증 계측 |
| `lib/features/dashboard/applications/common/firebase_google_auth_bridge.dart` | 로그인/로그아웃 개별 진단 | 실제 Firebase Auth signIn/signOut Future를 계측 |
| `lib/app/init/app_exit_service.dart` | 기존 종료·재시작 | 종료 요청/실패 기록·Flush 시도 후 기존 플랫폼 종료 흐름 유지 |
| `lib/app/diagnostics/firebase_activity_center_dialog.dart` | 최근 500개 실시간 로그만 표시 | 보관 세션/기간/페이지 조회 및 전체 범위 debugPrint 복사, 기존 애니메이션 보존 |
| `lib/app/terminal/application/parkinworkin_terminal_diagnostics.dart` | Firebase 최근 이벤트만 복사 | 기존 진단 + 로컬 현재 세션 전체 로그를 복사 시점에 병합 |
| `lib/app/utils/status_dialog.dart` | 제공된 고정 문자열 클립보드 복사 | 개발자 전용 비동기 생성기·복사 시점 권한 재검사 옵션 추가, 일반 복사는 유지 |

소스·README를 수정한 사실과 컴파일·실기기 성공 여부는 구분한다. Flutter/Dart SDK와 완전한 프로젝트가 없는 환경에서는 `flutter analyze`, Firebase 실제 요청·네트워크 차단·앱 강제 종료 및 Android 클립보드 처리 결과를 보증하지 않는다. 9장의 세션 관련 테스트를 실기기에서 완료한 후 배포한다.

### 2026-11-04 Firebase Activity Journal 신뢰성 개선

**기준 소스: `261104 0202.zip`.** 수정 파일은 `lib/app/diagnostics/firebase_activity_journal.dart`, `firebase_activity_meter.dart`, `firebase_activity_center_dialog.dart`, `lib/app/init/app_exit_service.dart` 및 본 README다. 완전한 Dart 파일을 같은 경로에 덮어쓰며, 주석과 `hintText`를 추가하지 않는다.

저널 재시도·부분 쓰기 정리, 세션·기간별 구조화 COST 계산, 역방향 JSONL 커서 페이지, 종료 준비 이벤트 분리가 적용됐다. 기존 전체 세션 `STATUS` 로그 복사·애니메이션·56dp AppBar·Plate TTS·근무 상태 알림·Firestore Rules·GCS `publicRead`는 수정하지 않는다.

정적 구조·상대 import·ZIP 무결성 검사와 Flutter 컴파일·실기기 실행 검증은 구분한다. Flutter/Dart SDK·완전한 Android 빌드 파일이 없는 환경에서는 `flutter analyze`, 디스크 I/O 실패 복구, 대용량 로그 페이지 이동, 개발자 클립보드 권한 및 실제 Firebase 호출 집계의 성공 여부를 보증할 수 없다. 배포 전 9장의 회귀 시나리오를 실행해야 한다.

### 2026-11-04 사용자 상태·출퇴근 읽기·쓰기 중복 방지 패치

**기준 소스: `261104 0236.zip`.** `user_status_service.dart`, `user_state.dart`, `commute_log_repository.dart`, `firebase_activity_center_dialog.dart`의 생략 없는 전체 Dart 소스와 README만 원래 상대 경로로 덮어쓴다. 9장의 동시 동일 요청·확인된 지역 쓰기·마이그레이션 표식 검증을 적용 전에 수행해야 하며, 실측되지 않은 READ/WRITE 절감량을 확정 수치로 주장하지 않는다.

기존 7일/20MiB Activity Journal, 현재·이전 세션 COST, 개발자 전용 `STATUS` 로컬 기록 비동기 병합 및 클립보드 복사 코드는 그대로 유지한다. `optimization` 이벤트는 별도 서버 호출이 아니며 Firestore 카운터를 증가시키지 않는다. `debugPrint(...)` 코드 복사 직전에 개발자 모드 권한 검사를 다시 수행하는 기존 구현을 변경하지 않는다.

화면의 56dp AppBar와 116×48dp 계측 패널, Plate TTS 직접 Firestore 구독, 근무 상태 알림, 로그인 Firebase UID, GCS 공개 읽기, 기존 `divisions/dev`, 기존 화면·상태 애니메이션은 변경하지 않는다. 비용 최적화 Dialog의 설명 전환은 기존 `AnimatedSwitcher`를 활용하고 `disableAnimations`이면 0ms로 처리한다. 수정한 Dart에는 주석 및 신규 `hintText`를 포함하지 않는다. 현재 제공된 ZIP에는 완전한 Flutter 프로젝트 루트가 없고 실행 환경에 Dart/Flutter SDK가 없어 실제 컴파일·Android 실기기·동시성·다중 기기 회귀 동작은 미검증이다.

### 2026-11-04 Firestore 비용 최적화 2차 — `261104 1413.zip` 기준

수정하는 완전한 Dart 파일은 `user_status_service.dart`, `user_state.dart`, `user_repository.dart`, `firestore_user_repository.dart`, `commute_log_repository.dart`, `firebase_activity_center_dialog.dart` 6개와 본 README다. 덮어쓰기 ZIP에는 변경 파일만 기존 상대 경로대로 포함하고 나머지는 그대로 유지한다. 새로 설치하거나 이동해야 할 파일은 없다.

| 검증 대상 | 이 패치의 정적 처리 | 추가 실기기 확인 |
| --- | --- | --- |
| 레거시 데이터 없음 | 레거시 조회·삭제 전용 WRITE 경로 제거; 월별 데이터 유지 | 현재 서버에 구형 출퇴근 `logs`가 실제 없음을 운영자가 확인 |
| 상태 원격 쓰기 | 문서별 요청 순서·성공 필드 추적·동일값 생략·로그인 쓰기 0/1 표시 | 로그인·로그아웃·근무 시작·지역 전환 반복 수행 |
| 관리자 월별 달력 | 월별 조회 결과 포맷과 저장/삭제는 보존 | 관리자 출퇴근·휴게 달력 표시·삭제·전환 확인 |
| 진단·애니메이션 | Activity Center 최적화 안내 페이드·슬라이드, 모션 감소 지원 | 개발자 `STATUS` `debugPrint(...)` 클립보드 복사 및 OFF 접근 차단 |
| 변경 제외 | Plate TTS·근무 알림·56dp 헤더·116×48dp 패널·Firebase 인증 UID·Firestore Rules·GCS `publicRead` | 실제 Android 회귀 검증 |

문서 원본 필드 값을 서버에서 추가 조회해 비교하지 않으며, **이번 앱 실행 중 성공한 원격 상태 쓰기를 확인한 경우에만** 순차 중복 UPDATE를 생략한다. 직접 계정 모델 쓰기는 상태 확인 캐시를 무효화한다. 필드 값이나 사용자 식별자가 새 `optimization` 이벤트에 저장되지 않는다. Firestore 자체의 유료 SDK 호출과 로컬 생략 진단을 구분한다.

현재 배포 자료에는 완전한 Flutter 프로젝트 루트와 Dart/Flutter SDK가 없어 `flutter analyze`, Android 빌드, 실제 Firestore READ·WRITE 절감 및 운영 Rules/레거시 데이터 확인은 수행하지 못했다. 정적 구조 검사나 ZIP 무결성만으로 실기기에서의 성공을 보장하지 않는다. 수정한 Dart 파일의 주석은 제거하고 신규 `hintText`는 삽입하지 않는다.
