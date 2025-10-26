class Vehicle {
  final String id;
  final String name;
  final String licensePlate;
  final String driverName;
  final String driverPhone;
  final double? latitude;
  final double? longitude;
  final DateTime? lastUpdated;
  final String status; // 'active', 'inactive', 'maintenance'

  Vehicle({
    required this.id,
    required this.name,
    required this.licensePlate,
    required this.driverName,
    required this.driverPhone,
    this.latitude,
    this.longitude,
    this.lastUpdated,
    required this.status,
  });

  factory Vehicle.fromJson(Map<String, dynamic> json) {
    return Vehicle(
      id: json['id'],
      name: json['name'],
      licensePlate: json['licensePlate'],
      driverName: json['driverName'],
      driverPhone: json['driverPhone'],
      latitude: json['latitude']?.toDouble(),
      longitude: json['longitude']?.toDouble(),
      lastUpdated: json['lastUpdated'] != null 
          ? DateTime.parse(json['lastUpdated']) 
          : null,
      status: json['status'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'licensePlate': licensePlate,
      'driverName': driverName,
      'driverPhone': driverPhone,
      'latitude': latitude,
      'longitude': longitude,
      'lastUpdated': lastUpdated?.toIso8601String(),
      'status': status,
    };
  }
}
