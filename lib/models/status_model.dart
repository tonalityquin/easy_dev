class StatusModel {
  final String id;
  final String name;
  final bool isActive;
  final String area;

  StatusModel({
    required this.id,
    required this.name,
    required this.isActive,
    required this.area,
  });

  factory StatusModel.fromMap(String id, Map<String, dynamic> data) {
    return StatusModel(
      id: id,
      name: data['name'] ?? '',
      isActive: data['isActive'] ?? false,
      area: data['area'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'name': name,
      'isActive': isActive,
      'area': area,
    };
  }
}
