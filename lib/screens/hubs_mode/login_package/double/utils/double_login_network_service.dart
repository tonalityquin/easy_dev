import 'dart:io';

/// 네트워크 연결 상태를 확인하는 서비스 클래스
class DoubleLoginNetworkService {
  /// 인터넷 연결 여부를 비동기적으로 확인하는 메서드
  ///
  /// - 'google.com'에 DNS lookup을 시도하여 연결 가능 여부 판단
  /// - 성공 시 true 반환, 실패 시 false 반환
  Future<bool> isConnected() async {
    try {
      final result = await InternetAddress.lookup('google.com');
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      return false;
    }
  }
}
