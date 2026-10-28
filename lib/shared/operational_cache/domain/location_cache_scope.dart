class LocationCacheScope {
  const LocationCacheScope._();

  static String? maybeKey(String division, String area) {
    final company = division.trim();
    final normalizedArea = area.trim();
    if (company.isEmpty || normalizedArea.isEmpty) return null;
    return 'company:${company.length}:$company:area:$normalizedArea';
  }

  static String requireKey(String division, String area) {
    final key = maybeKey(division, area);
    if (key == null) {
      throw StateError('LOCATION_CACHE_COMPANY_AREA_REQUIRED');
    }
    return key;
  }
}
