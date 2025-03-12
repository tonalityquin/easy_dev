class LocationModel {
  final String id;
  final String locationName;
  final String area;
  final bool isSelected;

  LocationModel({
    required this.id,
    required this.locationName,
    required this.area,
    required this.isSelected,
  });

  factory LocationModel.fromMap(String id, Map<String, dynamic> data) {
    return LocationModel(
      id: id,
      locationName: data['locationName'] ?? '',
      area: data['area'] ?? '',
      isSelected: data['isSelected'] ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'locationName': locationName,
      'area': area,
      'isSelected': isSelected,
    };
  }
}
