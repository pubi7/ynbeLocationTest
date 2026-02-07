class Product {
  final String id;
  final String name;
  final double price;

  /// Discount percent from Weve/backend (0-100). If null, no discount.
  final int? discountPercent;

  /// Promotion/campaign text from Weve/backend.
  final String? promotionText;
  final String? description;
  final String? category;
  final String? barcode;
  final String? productCode;
  final int? stockQuantity;
  final int? unitsPerBox;
  final double? netWeight;
  final double? grossWeight;
  final double? priceWholesale;
  final double? priceRetail;
  final double? pricePerBox;
  final String? supplierName;
  final bool? isActive; // Product active status from backend

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.discountPercent,
    this.promotionText,
    this.description,
    this.category,
    this.barcode,
    this.productCode,
    this.stockQuantity,
    this.unitsPerBox,
    this.netWeight,
    this.grossWeight,
    this.priceWholesale,
    this.priceRetail,
    this.pricePerBox,
    this.supplierName,
    this.isActive,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      price: json['price'].toDouble(),
      discountPercent: (json['discountPercent'] as num?)?.toInt(),
      promotionText: json['promotionText']?.toString(),
      description: json['description'],
      category: json['category'],
      barcode: json['barcode'],
      productCode: json['productCode'],
      stockQuantity: json['stockQuantity'],
      unitsPerBox: json['unitsPerBox'],
      netWeight: (json['netWeight'] as num?)?.toDouble(),
      grossWeight: (json['grossWeight'] as num?)?.toDouble(),
      priceWholesale: (json['priceWholesale'] as num?)?.toDouble(),
      priceRetail: (json['priceRetail'] as num?)?.toDouble(),
      pricePerBox: (json['pricePerBox'] as num?)?.toDouble(),
      supplierName: json['supplierName'],
      isActive:
          json['isActive'] as bool? ?? true, // Default to true if not provided
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'discountPercent': discountPercent,
      'promotionText': promotionText,
      'description': description,
      'category': category,
      'barcode': barcode,
      'productCode': productCode,
      'stockQuantity': stockQuantity,
      'unitsPerBox': unitsPerBox,
      'netWeight': netWeight,
      'grossWeight': grossWeight,
      'priceWholesale': priceWholesale,
      'priceRetail': priceRetail,
      'pricePerBox': pricePerBox,
      'supplierName': supplierName,
      'isActive': isActive,
    };
  }
}
