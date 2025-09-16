enum Capability {
  /// 태블릿/단말 관리
  tablet,

  /// 정기/월 주차
  monthly,

  /// 정산(빌링)
  bill,
}

extension CapabilityKey on Capability {
  String get key {
    switch (this) {
      case Capability.tablet:
        return 'tablet';
      case Capability.monthly:
        return 'monthly';
      case Capability.bill:
        return 'bill';
    }
  }

  String get label {
    switch (this) {
      case Capability.tablet:
        return '태블릿 관리';
      case Capability.monthly:
        return '정기 주차';
      case Capability.bill:
        return '정산';
    }
  }
}

typedef CapSet = Set<Capability>;

class Cap {
  const Cap._();

  static CapSet fromDynamic(dynamic raw) {
    if (raw == null) return <Capability>{};
    if (raw is CapSet) return Set<Capability>.from(raw);

    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return <Capability>{};
      final parts = s.contains(',')
          ? s.split(',').map((e) => e.trim())
          : s.split(RegExp(r'\s+')).map((e) => e.trim());
      return _fromIterable(parts);
    }

    if (raw is Iterable) {
      return _fromIterable(raw.map((e) => e?.toString() ?? ''));
    }

    if (raw is Map) {
      final result = <Capability>{};
      raw.forEach((k, v) {
        if (v == true) {
          final c = _capFromString(k?.toString() ?? '');
          if (c != null) result.add(c);
        }
      });
      return result;
    }

    return <Capability>{};
  }
  static bool supports(CapSet areaCaps, CapSet requires) =>
      requires.every(areaCaps.contains);

  static String human(CapSet caps) {
    if (caps.isEmpty) return '없음';
    return caps.map((c) => c.label).join(' · ');
  }

  static CapSet _fromIterable(Iterable<String> parts) {
    final out = <Capability>{};
    for (final s in parts) {
      final c = _capFromString(s);
      if (c != null) out.add(c);
    }
    return out;
  }

  static Capability? _capFromString(String s) {
    final k = s.trim().toLowerCase();
    switch (k) {
      case 'tablet':
      case 'device':
      case '단말':
      case '태블릿':
        return Capability.tablet;
      case 'monthly':
      case 'month':
      case '정기':
      case '월주차':
      case '정기주차':
        return Capability.monthly;
      case 'bill':
      case 'billing':
      case '정산':
        return Capability.bill;
      default:
      // 알 수 없는 값은 무시(하위호환: 예전 'space'가 있어도 그냥 건너뜀)
        return null;
    }
  }
}
