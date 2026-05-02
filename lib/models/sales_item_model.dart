class SalesItem {
  final String productId;
  final String productName;

  /// Нэгжийн үнэ (хөнгөлөлтийн дараа), серверээс ирсэнээр — дэлгэц/сагсанд ийм.
  /// [unitPriceExcludesVat] үед net; баримтад [receiptUnitGross].
  final double price;

  /// Нийт авсан ширхэг (төлөгдсөн + үнэгүй) — үлдэгдэл/серверт илгээх тоо.
  final int quantity;

  /// Хэрэглэгчийн сонгосон нэгж (UI дээр): 'piece' | 'box'
  /// quantity нь үргэлж "нийт ширхэг" (pieces) байдаг.
  final String orderedUnit;

  /// Хэрэглэгчийн оруулсан тоо (UI дээр). piece үед ширхэг, box үед хайрцаг.
  final int orderedQuantity;

  /// 1 хайрцаг дахь ширхэг (box үед ашиглана). piece үед 1.
  final int unitsPerBox;

  /// 1+1 зэрэг акциар үнэгүй авсан ширхэг (төлбөрт орохгүй).
  final int freeQuantity;

  /// true: серверээс ирсэн нэгжийн үнэ НӨАТ-гүй (net).
  final bool unitPriceExcludesVat;

  /// Каталогийн хувийн хөнгөлөлт (0–100), байхгүй бол null.
  final int? discountPercent;

  /// Акцийн тайлбар (жишээ нь 1+1).
  final String? promotionText;

  /// Сагсанд: үнэгүй ширхэг, хувийн хөнгөлөлт, эсвэл акцийн тайлбар байвал true.
  bool get hasPromotionBenefit =>
      freeQuantity > 0 ||
      (discountPercent != null && discountPercent! > 0) ||
      ((promotionText ?? '').trim().isNotEmpty);

  /// [PromotionPricingUtils.applyFinalPricingToCart]-аар тооцоолсон эцсийн нэгж/мөр;
  /// API-д `unitPrice` + `lineTotal` (warehouse-ийг өөрчлөхгүйгээр).
  final double? finalUnitPrice;

  /// Төлөх ширхэг дээр үндэслэсэн мөрийн нийт (`lineTotal`).
  final double? finalLineTotal;

  /// Төлбөрлөсөн ширхэг.
  int get paidQuantity => quantity - freeQuantity;

  /// Баримт: нэгжийн НӨАТ орсон дүн (10% нэмсэн).
  double get receiptUnitGross =>
      unitPriceExcludesVat ? _roundMoney(price * 1.1) : price;

  /// Баримтын мөрийн нийт (зөвхөн төлбөрт орох ширхэг).
  double get receiptLineGross => receiptUnitGross * paidQuantity;

  final double total;

  SalesItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    this.orderedUnit = 'piece',
    int? orderedQuantity,
    int? unitsPerBox,
    this.freeQuantity = 0,
    this.unitPriceExcludesVat = false,
    this.discountPercent,
    this.promotionText,
    this.finalUnitPrice,
    this.finalLineTotal,
  })  : assert(quantity >= 0),
        orderedQuantity =
            (orderedQuantity ?? quantity).clamp(0, 1 << 30).toInt(),
        unitsPerBox = (unitsPerBox ?? 1).clamp(1, 1 << 30).toInt(),
        assert(freeQuantity >= 0 && freeQuantity <= quantity),
        total = price * (quantity - freeQuantity);

  static double _roundMoney(double value) {
    // Avoid integer rounding; keep currency-style 2 decimals.
    return (value * 100).roundToDouble() / 100;
  }

  factory SalesItem.fromJson(Map<String, dynamic> json) {
    String _nonEmpty(dynamic v) {
      final s = (v ?? '').toString().trim();
      return (s.isEmpty || s.toLowerCase() == 'null') ? '' : s;
    }

    final qRaw = (json['quantity'] as num?)?.toInt() ?? 0;
    final q = qRaw < 0 ? 0 : qRaw;
    final f = (json['freeQuantity'] as num?)?.toInt() ?? 0;
    final fqRaw = f < 0 ? 0 : f;
    final fq = fqRaw > q ? q : fqRaw;
    final orderedUnit = (json['orderedUnit']?.toString() ?? 'piece').trim();
    final orderedQty = (json['orderedQuantity'] as num?)?.toInt();
    final upb = (json['unitsPerBox'] as num?)?.toInt();

    final productId = _nonEmpty(json['productId']);
    final productName = (() {
      final direct = _nonEmpty(json['productName']);
      if (direct.isNotEmpty) return direct;
      final product = json['product'];
      if (product is Map) {
        final nameMn = _nonEmpty(product['nameMongolian']);
        if (nameMn.isNotEmpty) return nameMn;
        final name = _nonEmpty(product['name']);
        if (name.isNotEmpty) return name;
        final nameEn = _nonEmpty(product['nameEnglish']);
        if (nameEn.isNotEmpty) return nameEn;
      }
      return productId.isNotEmpty ? 'Бараа #$productId' : 'Нэргүй бараа';
    })();

    return SalesItem(
      productId: productId.isNotEmpty ? productId : json['productId'].toString(),
      productName: productName,
      price: (json['price'] as num).toDouble(),
      quantity: q,
      orderedUnit: orderedUnit.isEmpty ? 'piece' : orderedUnit,
      orderedQuantity: orderedQty,
      unitsPerBox: upb,
      freeQuantity: fq,
      unitPriceExcludesVat: json['unitPriceExcludesVat'] == true,
      discountPercent: (json['discountPercent'] as num?)?.toInt(),
      promotionText: json['promotionText']?.toString(),
      finalUnitPrice: (json['finalUnitPrice'] as num?)?.toDouble() ??
          (json['lockedPayableUnitPrice'] as num?)?.toDouble(),
      finalLineTotal: (json['finalLineTotal'] as num?)?.toDouble() ??
          (json['lockedPayableLineTotal'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'orderedUnit': orderedUnit,
      'orderedQuantity': orderedQuantity,
      'unitsPerBox': unitsPerBox,
      'freeQuantity': freeQuantity,
      'unitPriceExcludesVat': unitPriceExcludesVat,
      if (discountPercent != null) 'discountPercent': discountPercent,
      if (promotionText != null && promotionText!.trim().isNotEmpty)
        'promotionText': promotionText,
      if (finalUnitPrice != null) 'finalUnitPrice': finalUnitPrice,
      if (finalLineTotal != null) 'finalLineTotal': finalLineTotal,
      'total': total,
    };
  }
}
