/// Product active/inactive helper utilities.
///
/// This file is the single source of truth for determining whether a product
/// should be considered "active" across the app.

import '../models/product_model.dart';

bool isProductActiveFromModel(bool? isActive) => isActive ?? true;

bool shouldForceInactiveProductFromModel(Product product) {
  final stock = product.stockQuantity ?? 0;
  if (stock > 0) return false;

  bool hasAnyPositivePrice() {
    // Match backend: defaultPrice / pricePerBox / product_prices.price (by customer type)
    if ((product.defaultPrice ?? 0) > 0) return true;
    if ((product.pricePerBox ?? 0) > 0) return true;
    final byType = product.pricesByCustomerType;
    if (byType != null && byType.values.any((v) => v > 0)) return true;
    return false;
  }

  return !hasAnyPositivePrice();
}

bool isProductActive(Product product) {
  // Only treat as inactive when explicitly false.
  // null/true => active (backend may omit the field).
  return product.isActive != false;
}

