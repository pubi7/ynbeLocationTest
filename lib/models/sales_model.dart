class Sales {
  final String id;
  final String productName;
  final String location;
  final String salespersonId;
  final String salespersonName;
  final double amount;
  final DateTime saleDate;
  final String? notes;

  Sales({
    required this.id,
    required this.productName,
    required this.location,
    required this.salespersonId,
    required this.salespersonName,
    required this.amount,
    required this.saleDate,
    this.notes,
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
    };
  }
}
