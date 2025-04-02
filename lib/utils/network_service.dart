import 'dart:io';

class NetworkService {
  /// 인터넷 연결 여부를 확인합니다.
  /// - 정상 연결 시 true
  /// - 실패 또는 예외 발생 시 false
  Future<bool> isConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}