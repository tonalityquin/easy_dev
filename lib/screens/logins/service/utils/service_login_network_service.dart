import 'dart:io';

/// 네트워크 연결 상태를 확인하는 서비스 클래스
class ServiceLoginNetworkService {
  /// 인터넷 연결 여부를 비동기적으로 확인하는 메서드
  ///
  /// - 'google.com'에 DNS lookup을 시도하여 연결 가능 여부 판단
  /// - 성공 시 true 반환, 실패 시 false 반환
  Future<bool> isConnected() async {
    try {
      // 'google.com' 도메인에 대해 DNS 조회 수행
      final result = await InternetAddress.lookup('google.com');

      // 결과가 비어있지 않고, IP 주소가 존재하면 연결된 것으로 판단
      return result.isNotEmpty && result[0].rawAddress.isNotEmpty;
    } catch (_) {
      // 예외 발생 시(오프라인 등), 연결되지 않은 것으로 판단
      return false;
    }
  }
}
