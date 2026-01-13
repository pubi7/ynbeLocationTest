class SalesItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final double total;

  SalesItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
  }) : total = price * quantity;

  factory SalesItem.fromJson(Map<String, dynamic> json) {
    return SalesItem(
      productId: json['productId'],
      productName: json['productName'],
      price: json['price'].toDouble(),
      quantity: json['quantity'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'total': total,
    };
  }
}



