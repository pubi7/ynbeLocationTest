class Sales {
  final String id;
  final String productName;
  final String location;
  final String salespersonId;
  final String salespersonName;
  final double amount;
  final DateTime saleDate;
  final String? notes;
  final String? paymentMethod; // 'бэлэн', 'данс', 'зээл'
  final double? latitude; // GPS координат
  final double? longitude; // GPS координат
  final int? quantity; // Барааны тоо хэмжээ
  final String? ipAddress; // IP хаяг
  /// Backend захиалгын ID — нэг товчоор илгээсэн бүх мөрийг нэгтгэхэд (газрын зураг)
  final int? warehouseOrderId;

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
    this.warehouseOrderId,
  });

  factory Sales.fromJson(Map<String, dynamic> json) {
    String _nonEmpty(dynamic v) {
      final s = (v ?? '').toString().trim();
      return s;
    }

    final productName = (() {
      // Common shapes:
      // - { productName: "..." }
      // - { product: { nameMongolian/name/nameEnglish: "..." } }
      final direct = _nonEmpty(json['productName']);
      if (direct.isNotEmpty && direct.toLowerCase() != 'null') return direct;
      final product = json['product'];
      if (product is Map) {
        final nameMn = _nonEmpty(product['nameMongolian']);
        if (nameMn.isNotEmpty && nameMn.toLowerCase() != 'null') return nameMn;
        final name = _nonEmpty(product['name']);
        if (name.isNotEmpty && name.toLowerCase() != 'null') return name;
        final nameEn = _nonEmpty(product['nameEnglish']);
        if (nameEn.isNotEmpty && nameEn.toLowerCase() != 'null') return nameEn;
      }
      final fallback = _nonEmpty(json['productId']);
      return fallback.isNotEmpty && fallback.toLowerCase() != 'null'
          ? 'Бараа #$fallback'
          : 'Нэргүй бараа';
    })();

    return Sales(
      id: json['id'],
      productName: productName,
      location: json['location'],
      salespersonId: json['salespersonId'],
      salespersonName: json['salespersonName'],
      amount: json['amount'].toDouble(),
      saleDate: DateTime.parse(json['saleDate']),
      notes: json['notes'],
      paymentMethod: json['paymentMethod'],
      latitude: json['latitude'] != null ? json['latitude'].toDouble() : null,
      longitude:
          json['longitude'] != null ? json['longitude'].toDouble() : null,
      quantity: json['quantity'] != null ? json['quantity'] as int : null,
      ipAddress: json['ipAddress'],
      warehouseOrderId: json['warehouseOrderId'] != null
          ? int.tryParse(json['warehouseOrderId'].toString())
          : null,
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
      'warehouseOrderId': warehouseOrderId,
    };
  }
}
