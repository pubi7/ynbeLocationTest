import 'order_model.dart';
import 'sales_model.dart';

class Shop {
  final String id;
  final String name;
  final String address;
  final double latitude;
  final double longitude;
  final String phone;
  final String? email;
  final String? registrationNumber; // Бүртгэлийн дугаар
  final String status; // 'active', 'inactive'
  final List<Order> orders;
  final List<Sales> sales;
  final DateTime lastVisit;

  Shop({
    required this.id,
    required this.name,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.phone,
    this.email,
    this.registrationNumber,
    required this.status,
    required this.orders,
    required this.sales,
    required this.lastVisit,
  });

  factory Shop.fromJson(Map<String, dynamic> json) {
    return Shop(
      id: json['id'],
      name: json['name'],
      address: json['address'],
      latitude: json['latitude'].toDouble(),
      longitude: json['longitude'].toDouble(),
      phone: json['phone'],
      email: json['email'],
      registrationNumber: json['registrationNumber'],
      status: json['status'],
      orders: (json['orders'] as List)
          .map((order) => Order.fromJson(order))
          .toList(),
      sales: (json['sales'] as List)
          .map((sale) => Sales.fromJson(sale))
          .toList(),
      lastVisit: DateTime.parse(json['lastVisit']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'phone': phone,
      'email': email,
      'registrationNumber': registrationNumber,
      'status': status,
      'orders': orders.map((order) => order.toJson()).toList(),
      'sales': sales.map((sale) => sale.toJson()).toList(),
      'lastVisit': lastVisit.toIso8601String(),
    };
  }
}
