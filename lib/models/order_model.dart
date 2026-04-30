class Order {
  final String id;
  final String customerName;
  final String customerPhone;
  final String customerAddress;
  final List<OrderItem> items;
  final double totalAmount;
  final String status; // 'pending', 'confirmed', 'delivered', 'cancelled'
  final DateTime orderDate;
  final DateTime? deliveryDate;
  final String? notes;
  final String salespersonId;
  final String salespersonName;
  final bool ebarimtRegistered;
  final String? ebarimtBillId;
  final String? ebarimtReturnId;

  /// eBarimt: сугалааны дугаар (B2C)
  final String? ebarimtLottery;

  /// eBarimt: QR-д оруулах өгөгдөл (ихэвчлэн backend-ээс)
  final String? ebarimtQrData;

  /// eBarimt: төлөв / тэмдэглэл (optional)
  final String? ebarimtStatus;

  Order({
    required this.id,
    required this.customerName,
    required this.customerPhone,
    required this.customerAddress,
    required this.items,
    required this.totalAmount,
    required this.status,
    required this.orderDate,
    this.deliveryDate,
    this.notes,
    required this.salespersonId,
    required this.salespersonName,
    this.ebarimtRegistered = false,
    this.ebarimtBillId,
    this.ebarimtReturnId,
    this.ebarimtLottery,
    this.ebarimtQrData,
    this.ebarimtStatus,
  });

  factory Order.fromJson(Map<String, dynamic> json) {
    return Order(
      id: json['id'],
      customerName: json['customerName'],
      customerPhone: json['customerPhone'],
      customerAddress: json['customerAddress'],
      items: (json['items'] as List)
          .map((item) => OrderItem.fromJson(item))
          .toList(),
      totalAmount: json['totalAmount'].toDouble(),
      status: json['status'],
      orderDate: DateTime.parse(json['orderDate']),
      deliveryDate: json['deliveryDate'] != null
          ? DateTime.tryParse(json['deliveryDate'].toString())
          : null,
      notes: json['notes'],
      salespersonId: json['salespersonId'],
      salespersonName: json['salespersonName'],
      ebarimtRegistered: json['ebarimtRegistered'] == true,
      ebarimtBillId:
          json['ebarimtBillId']?.toString() ?? json['billId']?.toString(),
      ebarimtReturnId: json['ebarimtReturnId']?.toString(),
      ebarimtLottery:
          json['ebarimtLottery']?.toString() ?? json['lottery']?.toString(),
      ebarimtQrData:
          json['ebarimtQrData']?.toString() ?? json['qrData']?.toString(),
      ebarimtStatus: json['ebarimtStatus']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerAddress': customerAddress,
      'items': items.map((item) => item.toJson()).toList(),
      'totalAmount': totalAmount,
      'status': status,
      'orderDate': orderDate.toIso8601String(),
      if (deliveryDate != null) 'deliveryDate': deliveryDate!.toIso8601String(),
      'notes': notes,
      'salespersonId': salespersonId,
      'salespersonName': salespersonName,
      'ebarimtRegistered': ebarimtRegistered,
      'ebarimtBillId': ebarimtBillId,
      'ebarimtReturnId': ebarimtReturnId,
      'ebarimtLottery': ebarimtLottery,
      'ebarimtQrData': ebarimtQrData,
      'ebarimtStatus': ebarimtStatus,
    };
  }
}

class OrderItem {
  final String productId;
  final String productName;
  final int quantity;
  final double unitPrice;
  final double totalPrice;

  /// 1 хайрцаг дахь ширхэг (backend / product-оос).
  final int unitsPerBox;

  /// 'piece' | 'box' — захиалга үүсгэх үедийн сонголт.
  final String orderedUnit;

  /// Сонгосон тоо (piece=ширхэг, box=хайрцаг). Backend илгээгээгүй бол null.
  final int? orderedQuantity;

  /// Акциар үнэгүй ширхэг (1+1 гэх мэт).
  final int freeQuantity;

  OrderItem({
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.unitPrice,
    required this.totalPrice,
    this.unitsPerBox = 1,
    this.orderedUnit = 'piece',
    this.orderedQuantity,
    this.freeQuantity = 0,
  });

  int get _upb => unitsPerBox <= 0 ? 1 : unitsPerBox;

  /// Дэлгэцэнд: хайрцаг + нэмэлт ширхэг / нийт ширхэг.
  String get boxPieceSummary {
    final upb = _upb;
    if (upb <= 1) {
      if (freeQuantity > 0) {
        return '$quantity ширхэг (+$freeQuantity үнэгүй)';
      }
      return '$quantity ширхэг';
    }
    final boxes = quantity ~/ upb;
    final extra = quantity % upb;
    final base = extra > 0
        ? '$boxes хайрцаг + $extra ширхэг (нийт $quantity ш)'
        : '$boxes хайрцаг (нийт $quantity ш)';
    if (freeQuantity > 0) {
      return '$base (+$freeQuantity үнэгүй)';
    }
    return base;
  }

  factory OrderItem.fromJson(Map<String, dynamic> json) {
    final qty = (json['quantity'] as num?)?.toInt() ?? 0;
    final upb = (json['unitsPerBox'] as num?)?.toInt() ?? 1;
    final ou = (json['orderedUnit']?.toString() ?? 'piece').trim();
    int? oq = (json['orderedQuantity'] as num?)?.toInt();
    if (oq == null && ou == 'box' && upb > 1) {
      oq = qty ~/ upb;
    }
    return OrderItem(
      productId: json['productId'].toString(),
      productName: json['productName'].toString(),
      quantity: qty,
      unitPrice: (json['unitPrice'] as num).toDouble(),
      totalPrice: (json['totalPrice'] as num).toDouble(),
      unitsPerBox: upb,
      orderedUnit: ou.isEmpty ? 'piece' : ou,
      orderedQuantity: oq,
      freeQuantity: (json['freeQuantity'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'quantity': quantity,
      'unitPrice': unitPrice,
      'totalPrice': totalPrice,
      'unitsPerBox': unitsPerBox,
      'orderedUnit': orderedUnit,
      if (orderedQuantity != null) 'orderedQuantity': orderedQuantity,
      'freeQuantity': freeQuantity,
    };
  }
}
