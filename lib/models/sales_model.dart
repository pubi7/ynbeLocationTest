class Sales {
  final String id;
  final String productName;
  final String location;
  final String salespersonId;
  final String salespersonName;
  final double amount;
  final DateTime saleDate;
  final String? notes;
  final String? paymentMethod; // 'билэн', 'данс', 'зээл'
  final double? latitude; // GPS координат
  final double? longitude; // GPS координат
  final int? quantity; // Барааны тоо хэмжээ
  final String? ipAddress; // IP хаяг

  Sales({
    required this.id,
    required this.productName,
    required this.location,
    required this.salespersonId,
    required this.salespersonName,
    required this.amount,
    required this.saleDate,
    this.notes,
    this.paymentMethod,
    this.latitude,
    this.longitude,
    this.quantity,
    this.ipAddress,
  });

  factory Sales.fromJson(Map<String, dynamic> json) {
    return Sales(
      id: json['id'],
      productName: json['productName'],
      location: json['location'],
      salespersonId: json['salespersonId'],
      salespersonName: json['salespersonName'],
      amount: json['amount'].toDouble(),
      saleDate: DateTime.parse(json['saleDate']),
      notes: json['notes'],
      paymentMethod: json['paymentMethod'],
      latitude: json['latitude'] != null ? json['latitude'].toDouble() : null,
      longitude: json['longitude'] != null ? json['longitude'].toDouble() : null,
      quantity: json['quantity'] != null ? json['quantity'] as int : null,
      ipAddress: json['ipAddress'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'productName': productName,
      'location': location,
      'salespersonId': salespersonId,
      'salespersonName': salespersonName,
      'amount': amount,
      'saleDate': saleDate.toIso8601String(),
      'notes': notes,
      'paymentMethod': paymentMethod,
      'latitude': latitude,
      'longitude': longitude,
      'quantity': quantity,
      'ipAddress': ipAddress,
    };
  }
}
