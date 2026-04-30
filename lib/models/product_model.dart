Map<int, double>? _parsePricesByCustomerType(dynamic value) {
  if (value == null || value is! Map) return null;
  final result = <int, double>{};
  for (final e in value.entries) {
    final k = int.tryParse(e.key.toString());
    final v = (e.value as num?)?.toDouble();
    if (k != null && v != null && v > 0) result[k] = v;
  }
  return result.isEmpty ? null : result;
}

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

  /// Дэлгүүр (customerType)-аас хамаарах үнэ. Key = customerTypeId, value = үнэ
  final Map<int, double>? pricesByCustomerType;
  final String? supplierName;
  final bool? isActive; // Product active status from backend
  /// true: серверийн нэгжийн үнэ НӨАТ-гүй (net); дэлгэцэнд ийм, баримтад +10%.
  final bool unitPriceExcludesVat;

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
    this.pricesByCustomerType,
    this.supplierName,
    this.isActive,
    this.unitPriceExcludesVat = false,
  });

  /// Дэлгүүр сонгосон үед тухайн customerType-д тохирох үнэ, эсвэл default үнэ
  double getPriceForCustomerType(int? customerTypeId) {
    if (customerTypeId != null &&
        pricesByCustomerType != null &&
        pricesByCustomerType!.containsKey(customerTypeId)) {
      return pricesByCustomerType![customerTypeId]!;
    }
    return price;
  }

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
      pricesByCustomerType:
          _parsePricesByCustomerType(json['pricesByCustomerType']),
      supplierName: json['supplierName'],
      isActive:
          json['isActive'] as bool? ?? true, // Default to true if not provided
      unitPriceExcludesVat: json['unitPriceExcludesVat'] == true,
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
      'pricesByCustomerType': pricesByCustomerType,
      'supplierName': supplierName,
      'isActive': isActive,
      'unitPriceExcludesVat': unitPriceExcludesVat,
    };
  }
}
