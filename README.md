Windows용 Flutter 개발환경 설정 (JDK 17)
사전 요구사항

Windows 10/11 64-bit

관리자 권한 터미널(콘솔) 사용 가능

디스크 여유공간 10GB+

1) Flutter 설치

Flutter SDK를 내려받아 압축 해제

예시 경로: C:\Flutter

환경변수 등록

Windows 검색 → “환경 변수” → 시스템 속성(고급) → 환경 변수 → Path 편집 → 새로 만들기

C:\Flutter\bin 추가

확인

flutter --version

2) Android Studio & SDK 구성

Android Studio 설치

Plugins에서 Flutter 설치 → IDE 재시작

SDK Manager → SDK Platforms

Android 14 (API 34) ✔

(필요 시) Android 13 (API 33) ✔

SDK Manager → SDK Tools

Android SDK Command-line Tools (latest) ✔

NDK (Side by side) (네이티브/일부 플러그인 필요 시)

CMake (NDK 사용 시)

Google USB Driver (Windows, 실기기 디버깅 시)

3) Android 라이선스 동의
flutter doctor
flutter doctor --android-licenses

4) JDK 17 설정 (고정)

Flutter/AGP 최신 조합은 JDK 17 권장/요구

JDK 17 설치 (Microsoft OpenJDK, Temurin 등)

권장 경로 예: C:\Program Files\Java\jdk-17

환경변수

JAVA_HOME = C:\Program Files\Java\jdk-17

Path에 %JAVA_HOME%\bin 추가

확인

# PowerShell
Test-Path "$env:JAVA_HOME\bin\java.exe"   # True면 정상
java -version

:: CMD
echo %JAVA_HOME%
where java

5) (선택) Windows 데스크톱 빌드

Windows 앱까지 필요하면 Visual Studio 2022 설치 → 워크로드: C++를 사용한 데스크톱 개발 체크.
Android 전용이면 생략해도 됩니다.

6) (선택) Dart SDK 경로(IDE)

Android Studio: File → Settings → Languages & Frameworks → Dart
→ Flutter 설치 경로의 dart-sdk 지정 (자동인식 안 될 때만)

예: C:\Flutter\bin\cache\dart-sdk

7) 첫 프로젝트 빌드 테스트
flutter create hello_app
cd hello_app
flutter run

8) 자주 발생 오류 & 해결
8-1) Some Android licenses not accepted
flutter doctor --android-licenses

8-2) Value 'C:/Program Files/Java/jdk-17' ... org.gradle.java.home ... invalid

원인: android/gradle.properties의 org.gradle.java.home가 잘못 지정되었거나 불필요

권장 해결: 해당 줄 삭제하여 JAVA_HOME을 사용

불가피하게 유지해야 할 때: JDK 루트로 정확히 지정하고 bin 미포함, 경로 이스케이프 주의

org.gradle.java.home=C:\\Program Files\\Java\\jdk-17
# 또는
org.gradle.java.home=C:/Program Files/Java/jdk-17


경로 존재 확인:

Test-Path "C:\Program Files\Java\jdk-17\bin\java.exe"

8-3) A problem occurred evaluating project ':app'. > path may not be null or empty string. path='null'

상황: android/ 폴더를 다른 PC에서 복사해 교체했을 때 흔함

주원인: signingConfigs에서 key.properties의 storeFile 경로가 비거나 파일 부재

해결 가이드

프로젝트 루트에 key.properties 확인(없으면 임시 생성)

# android/key.properties (예시)
storeFile=keystore.jks
storePassword=your-password
keyAlias=your-alias
keyPassword=your-password


상대경로 사용 시 실제 파일이 android/app/keystore.jks 등에 존재해야 함

android/app/build.gradle에 조건부 서명 설정으로 NPE/Null path 방지

def keystorePropertiesFile = rootProject.file("key.properties")
def keystoreProperties = new Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(new FileInputStream(keystorePropertiesFile))
}

android {
    signingConfigs {
        release {
            if (keystorePropertiesFile.exists() && keystoreProperties['storeFile']) {
                storeFile file(keystoreProperties['storeFile'])
                storePassword keystoreProperties['storePassword']
                keyAlias keystoreProperties['keyAlias']
                keyPassword keystoreProperties['keyPassword']
            }
        }
    }
    buildTypes {
        release {
            // key.properties가 없으면 기본 디버그 키로만 빌드 (내부 배포/테스트용)
            signingConfig signingConfigs.release
            minifyEnabled false
        }
        debug { }
    }
}


기타: 커스텀 스크립트에서 file(null) 유발, 빈 resDir/jniLibsDir 설정 등도 점검

9) 트러블슈팅 팁

의심될 때는:

flutter clean
flutter pub get


SDK/빌드 실패 시 버전 호환 확인

android/gradle/wrapper/gradle-wrapper.properties (Gradle)

android/build.gradle의 Android Gradle Plugin(AGP)

실기기 디버깅: 개발자 옵션 + USB 디버깅 활성, Google USB Driver 설치

10) 빠른 설치 요약
1) Flutter: C:\Flutter → Path에 C:\Flutter\bin
2) Android Studio → Flutter 플러그인 설치/재시작
3) SDK:
   - Platforms: Android 14(API 34), (필요 시) 13(API 33)
   - Tools: Command-line Tools(latest), (옵션) NDK/CMake, (Windows) Google USB Driver
4) 라이선스: flutter doctor --android-licenses
5) JDK 17:
   - JAVA_HOME=C:\Program Files\Java\jdk-17
   - Path에 %JAVA_HOME%\bin
6) 빌드: flutter create app → flutter run
[오류]
- org.gradle.java.home invalid → gradle.properties 항목 제거 또는 정확한 JDK 루트
- path may not be null → key.properties/keystore 확인 + 조건부 signingConfigs
- (선택) Windows 데스크톱: VS 2022 + “C++ 데스크톱 개발”
