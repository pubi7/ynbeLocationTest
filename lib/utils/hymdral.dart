import 'package:flutter/foundation.dart';

import 'promotion_pricing_utils.dart';

Map<String, dynamic>? _firstActivePromotionFromServerProduct(
  Map<String, dynamic> p,
) {
  final raw = p['promotions'];
  if (raw is! List || raw.isEmpty) return null;
  final first = raw.first;
  if (first is! Map) return null;
  return first.cast<String, dynamic>();
}

String? _promotionTextFromPromotionMap(Map<String, dynamic> promo) {
  final name = (promo['name'] ?? '').toString().trim();
  final type = (promo['type'] ?? '').toString().trim().toUpperCase();

  if (type == 'BUY_X_GET_Y') {
    final buy = promo['buyQty'] ?? promo['buy_qty'];
    final free = promo['freeQty'] ?? promo['free_qty'];
    final b = (buy is num) ? buy.toInt() : int.tryParse(buy?.toString() ?? '');
    final f =
        (free is num) ? free.toInt() : int.tryParse(free?.toString() ?? '');
    if (b != null && f != null && b > 0 && f > 0) {
      // Keep "N+M" in the text so PromotionPricingUtils.parseBuyFree can detect it.
      final tail = name.isEmpty ? '' : ' $name';
      return '$b+$f$tail'.trim();
    }
  }

  if (type == 'PERCENT_DISCOUNT') {
    final dp = promo['discountPercent'] ?? promo['discount_percent'];
    final n = (dp is num) ? dp.toDouble() : double.tryParse(dp?.toString() ?? '');
    if (n != null && n > 0) {
      return name.isNotEmpty ? name : '${n % 1 == 0 ? n.toInt() : n}%';
    }
  }

  return name.isEmpty ? null : name;
}

String? _discountPercentStringFromPromotionMap(Map<String, dynamic> promo) {
  final type = (promo['type'] ?? '').toString().trim().toUpperCase();
  if (type != 'PERCENT_DISCOUNT') return null;

  final dp = promo['discountPercent'] ?? promo['discount_percent'];
  if (dp == null) return null;
  final n = (dp is num) ? dp.toDouble() : double.tryParse(dp.toString());
  if (n == null || n <= 0) return null;
  return (n % 1 == 0) ? n.toInt().toString() : n.toString();
}

/// Серверийн барааны JSON-с хямдралын хувийг string болгон буцаана.
///
/// Дараах түлхүүрүүдийг дараалан шалгана:
/// 1. `discountPercent`
/// 2. `discount`
/// 3. `campaignDiscountPercent`
///
/// Тайлбар:
/// - `??` оператор нь зөвхөн `null`-ыг шалгадаг тул `0`/`false` утга "алдахгүй".
///   Гэхдээ map-д тухайн key огт байхгүй тохиолдлыг зөв ялгахын тулд `containsKey` ашиглав.
String? serverProductDiscountPercentToString(Map<String, dynamic>? p) {
  if (p == null) return null;

  // Warehouse-service style: product.promotions[] (active + date-filtered on server)
  final promo = _firstActivePromotionFromServerProduct(p);
  if (promo != null) {
    final v = _discountPercentStringFromPromotionMap(promo);
    if (v != null) return v;
  }

  const keys = [
    'discountPercent',
    'discount',
    'campaignDiscountPercent',
    // common snake_case variants
    'discount_percent',
    'campaign_discount_percent',
    // other common variants
    'discountPercentage',
    'discount_percentage',
  ];
  for (final key in keys) {
    if (p.containsKey(key) && p[key] != null) {
      return p[key].toString();
    }
  }

  // Support nested objects (common API shapes)
  final campaign = p['campaign'];
  if (campaign is Map) {
    final cm = campaign.cast<String, dynamic>();
    final nested = serverProductDiscountPercentToString(cm);
    if (nested != null) return nested;
  }
  final pricing = p['pricing'];
  if (pricing is Map) {
    final pm = pricing.cast<String, dynamic>();
    final nested = serverProductDiscountPercentToString(pm);
    if (nested != null) return nested;
  }

  return null;
}

/// Серверийн барааны JSON-с урамшууллын текстийг буцаана.
///
/// Дараах түлхүүрүүдийг дараалан шалгана:
/// 1. `promotionText`
/// 2. `promotion`
/// 3. `campaignTitle`
String? serverProductPromotionTextToString(Map<String, dynamic>? p) {
  if (p == null) return null;

  // Warehouse-service style: product.promotions[] (active + date-filtered on server)
  final promo = _firstActivePromotionFromServerProduct(p);
  if (promo != null) {
    final v = _promotionTextFromPromotionMap(promo);
    if (v != null) return v;
  }

  const keys = [
    'promotionText',
    'promotion',
    'campaignTitle',
    // common snake_case variants
    'promotion_text',
    'campaign_title',
    // other common variants
    'promotionName',
    'promotion_name',
  ];
  for (final key in keys) {
    if (p.containsKey(key) && p[key] != null) {
      return p[key].toString();
    }
  }

  // Support nested objects (common API shapes)
  final campaign = p['campaign'];
  if (campaign is Map) {
    final cm = campaign.cast<String, dynamic>();
    final nested = serverProductPromotionTextToString(cm);
    if (nested != null) return nested;
  }
  final promotion = p['promotion'];
  if (promotion is Map) {
    final pm = promotion.cast<String, dynamic>();
    final nested = serverProductPromotionTextToString(pm);
    if (nested != null) return nested;
  }

  return null;
}

/// Каталогийн map-аас хямдралын хувийг [int] болгон буцаана.
///
/// `int`, `double`, болон `"10.0"` хэлбэрийн string-г зөв зохицуулна.
/// `double`-г `int` болгохдоо truncate хийнэ (тойруулахгүй).
///
/// Хязгаар:
/// - Хямдрал 0–100% хооронд байх ёстой (эс бөгөөс `null`).
int? catalogMapDiscountPercent(Map<String, dynamic>? p) {
  if (p == null) return null;

  final raw = p['discountPercent'];
  if (raw == null) return null;

  int? result;

  if (raw is int) {
    result = raw;
  } else if (raw is double) {
    result = raw.toInt();
  } else {
    final s = raw.toString().trim();
    if (s.isEmpty) return null;
    result = int.tryParse(s) ?? int.tryParse(s.split('.').first);
  }

  if (result == null || result < 0 || result > 100) return null;
  return result;
}

/// Каталогийн нэр болон серверээс ирсэн урамшууллын текстийг нэгтгэнэ.
///
/// - [catalogName]: Каталогийн нэр (`PromotionPricingUtils`-д дамжуулагдана)
/// - [p]: Барааны map (nullable)
///
/// `p == null` үед ч `catalogName` дангаараа утга үүсгэж болох тул merge-г ажиллуулна.
/// Харин `promotionText` байхгүй/хоосон бол `null` дамжуулна.
String? catalogMapMergedPromotionText({
  required String catalogName,
  Map<String, dynamic>? p,
}) {
  try {
    final raw = p == null ? null : (p['promotionText'] ?? '').toString().trim();
    final promotionText = (raw?.isEmpty ?? true) ? null : raw;

    return PromotionPricingUtils.mergeCatalogPromotionText(
      catalogName,
      promotionText,
    );
  } catch (e, st) {
    debugPrint('catalogMapMergedPromotionText error: $e\n$st');
    return null;
  }
}