class Product {
  final String id;
  final String name;
  final double price;
  final String? description;
  final String? category;

  Product({
    required this.id,
    required this.name,
    required this.price,
    this.description,
    this.category,
  });

  factory Product.fromJson(Map<String, dynamic> json) {
    return Product(
      id: json['id'],
      name: json['name'],
      price: json['price'].toDouble(),
      description: json['description'],
      category: json['category'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'description': description,
      'category': category,
    };
  }
}

