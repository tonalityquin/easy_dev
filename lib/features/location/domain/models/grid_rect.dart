class GridRect {
  const GridRect({
    required this.r0,
    required this.c0,
    required this.r1,
    required this.c1,
  });

  final int r0;
  final int c0;
  final int r1;
  final int c1;

  GridRect normalized() {
    final top = r0 < r1 ? r0 : r1;
    final bottom = r0 < r1 ? r1 : r0;
    final left = c0 < c1 ? c0 : c1;
    final right = c0 < c1 ? c1 : c0;
    return GridRect(r0: top, c0: left, r1: bottom, c1: right);
  }

  int get top => r0 < r1 ? r0 : r1;
  int get bottom => r0 < r1 ? r1 : r0;
  int get left => c0 < c1 ? c0 : c1;
  int get right => c0 < c1 ? c1 : c0;

  int get height => bottom - top + 1;
  int get width => right - left + 1;
  int get area => height * width;

  bool overlaps(GridRect other) {
    final a = normalized();
    final b = other.normalized();
    if (a.right < b.left) return false;
    if (b.right < a.left) return false;
    if (a.bottom < b.top) return false;
    if (b.bottom < a.top) return false;
    return true;
  }

  bool containsCell(int r, int c) {
    final n = normalized();
    return r >= n.top && r <= n.bottom && c >= n.left && c <= n.right;
  }

  String toKey() => '$r0|$c0|$r1|$c1';

  static GridRect? tryFromKey(String key) {
    final parts = key.split('|');
    if (parts.length != 4) return null;
    final r0 = int.tryParse(parts[0].trim());
    final c0 = int.tryParse(parts[1].trim());
    final r1 = int.tryParse(parts[2].trim());
    final c1 = int.tryParse(parts[3].trim());
    if (r0 == null || c0 == null || r1 == null || c1 == null) return null;
    return GridRect(r0: r0, c0: c0, r1: r1, c1: c1);
  }

  Map<String, dynamic> toJson() => {
    'r0': r0,
    'c0': c0,
    'r1': r1,
    'c1': c1,
  };

  factory GridRect.fromJson(Map<String, dynamic> json) => GridRect(
    r0: (json['r0'] as num?)?.toInt() ?? 0,
    c0: (json['c0'] as num?)?.toInt() ?? 0,
    r1: (json['r1'] as num?)?.toInt() ?? 0,
    c1: (json['c1'] as num?)?.toInt() ?? 0,
  );

  @override
  String toString() => 'GridRect($r0,$c0 -> $r1,$c1)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GridRect &&
        other.r0 == r0 &&
        other.c0 == c0 &&
        other.r1 == r1 &&
        other.c1 == c1;
  }

  @override
  int get hashCode => Object.hash(r0, c0, r1, c1);
}
