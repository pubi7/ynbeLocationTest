import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/order_model.dart';
import '../models/sales_item_model.dart';
import 'promotion_pricing_utils.dart';

/// Захиалгыг warehouse backend (`POST /api/orders`) руу илгээхэд хэрэглэх
/// **JSON items**, төлбөрийн төрөл mapping, **429 retry** — нэг газраас.
///
/// **Юу хийдэг:** сервер рүү дамжуулах body-г цуглуулна. Мөрийн `lineTotal` нь **үргэлж**
/// [PromotionPricingUtils.payableLineTotalInCart] (сагсны «Нийт») + [parsePercentFromNotes];
/// `finalLineTotal` зөвхөн UI-д. `priceMode` илгээхгүй.
///
/// **Юу биш:** promotion rule engine, campaign/coupon/customer-tier pipeline,
/// signed эсвэл серверээс ирсэн promotion ID-ээр үнэ баталгаажуулах — эдгээр нь
/// тусад нь загвар шаарддаг.
class WarehouseOrderBackendSubmitOneFile {
  WarehouseOrderBackendSubmitOneFile._();

  /// Debug: `POST /api/orders` body-ийн `items` дэх ширхэгүүдийг консолд (Run/Debug) хэвлэнэ.
  static void debugLogBackendOrderItems(
    List<Map<String, dynamic>> items, {
    List<String>? productNames,
  }) {
    if (!kDebugMode) return;
    debugPrint('📋 Backend items: ${items.length} мөр (totalPiecesForStock=үлдэгдлээс хасах нийт)');
    for (var i = 0; i < items.length; i++) {
      final m = items[i];
      final id = m['productId'];
      final q = m['quantity'];
      final paid = m['paidQuantity'];
      final free = m['freeQuantity'];
      final tps = m['totalPiecesForStock'];
      final unit = m['unitPrice'];
      final line = m['lineTotal'];
      final mode = m['priceMode'];
      final name = (productNames != null && i < productNames.length)
          ? productNames[i].trim()
          : '';
      final suffix = name.isNotEmpty ? ' — $name' : '';
      debugPrint(
        '   [$i] productId=$id$suffix → quantity(төлөх ш)=$q, paidQuantity=$paid, '
        'freeQuantity=$free, totalPiecesForStock=$tps, unitPrice=$unit, lineTotal=$line'
        '${mode != null ? ', priceMode=$mode' : ''}',
      );
    }
  }

  /// Note талбарт "10%" гэх мэт бичвэл order-level хөнгөлөлтийн хувь.
  static double? parsePercentFromNotes(String? notes) {
    final s = (notes ?? '').trim();
    if (s.isEmpty) return null;
    final m = RegExp(r'(\d+(?:[.,]\d+)?)\s*%').firstMatch(s);
    if (m == null) return null;
    final raw = m.group(1)?.replaceAll(',', '.') ?? '';
    final v = double.tryParse(raw);
    if (v == null) return null;
    if (v <= 0) return null;
    return v.clamp(0, 100);
  }

  /// Гар утасны төлбөрийн нэр → backend enum (`Cash`, `Credit`, …).
  static String mapMobilePaymentMethodToBackend(String mobileMethod) {
    switch (mobileMethod.toLowerCase()) {
      case 'cash':
      case 'бэлэн':
        return 'Cash';
      case 'credit':
      case 'зээл':
        return 'Credit';
      case 'bank':
      case 'банк':
      case 'данс':
        return 'BankTransfer';
      case 'sales':
      case 'борлуулалт':
        return 'Sales';
      case 'padan':
      case 'падан':
        return 'Padan';
      default:
        return 'Cash';
    }
  }

  /// Худалдааны оролтын сагс (`SalesItem`) → `createOrder` items array.
  ///
  /// Backend (`warehouse-service`) одоогоор үлдэгдэл хасахдаа `item.quantity`-г ашигладаг.
  /// Тиймээс mobile → backend дээр:
  /// - `quantity` = **нийт физик ширхэг** (төлөх + үнэгүй)
  /// - `paidQuantity` = **төлөх ширхэг** (UI/лог/ирээдүйн нийцтэй байдалд)
  /// - `freeQuantity` = **үнэгүй ширхэг**
  ///
  /// Custom pricing (`priceMode=custom`) үед `unitPrice`-ийг mobile тооцоолсон мөрийн нийт
  /// (lineTotal)-д тааруулж илгээнэ:
  /// `unitPrice = lineTotal / quantity(нийт физик)`.
  static List<Map<String, dynamic>> buildItemsFromSalesCart(
    List<SalesItem> selectedItems, {
    required bool applyDiscountFromNotes,
    required String notesTrimmed,
  }) {
    final notePercent =
        applyDiscountFromNotes ? parsePercentFromNotes(notesTrimmed) : null;
    final noteMultiplier =
        (notePercent != null) ? (1 - (notePercent / 100.0)) : 1.0;
    final n = selectedItems.length;
    final resolved = List.generate(
      n,
      (i) => PromotionPricingUtils.resolveLinePromotion(selectedItems[i]),
    );
    final tierBase =
        resolved.fold<int>(0, (sum, r) => sum + r.paidPieces);
    return List.generate(n, (idx) {
      final item = selectedItems[idx];
      final productId = int.tryParse(item.productId);
      if (productId == null) {
        throw FormatException('Барааны ID буруу байна: ${item.productId}');
      }
      final paidWire = resolved[idx].paidPieces;
      // free <= total - paid (invariant). item.quantity = total physical pieces in cart.
      final rawFree = item.quantity - paidWire;
      final freeWire = rawFree <= 0 ? 0 : rawFree;
      final totalPiecesForStock = item.quantity;
      final qtyWire = totalPiecesForStock < 0 ? 0 : totalPiecesForStock;
      final cartBulkMult =
          PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
        item: item,
        eligiblePaidPiecesTotal: tierBase,
        isBuyOneGetOne: resolved[idx].isBogo,
      );
      // Мөрийн дүнг үргэлж сагсны [payableLineTotalInCart]-аас — finalLineTotal хуучирсан
      // (1+1 төлөх 2 гэж үлдсэн) үед серверт буруу дүн очихоос сэргийлнэ.
      final lineTotal = PromotionPricingUtils.roundMoney2(
        PromotionPricingUtils.payableLineTotalInCart(
          item,
          cartWidePaidPiecesTotal: tierBase,
          noteMultiplier: noteMultiplier,
          effectivePaidPieces: paidWire,
          isBuyOneGetOne: resolved[idx].isBogo,
        ),
      );
      final finU = item.finalUnitPrice;
      final double unit = (finU != null)
          ? finU
          : PromotionPricingUtils.discountedUnitPrice(
              unitPrice: item.price,
              noteMultiplier: noteMultiplier,
              cartBulkMultiplier: cartBulkMult,
            );
      // `lineTotal` нь сагсны тооцоолсон эцсийн мөрийн дүн. Weve/backend-д нэгж үнэ нь
      // үргэлж `unitPrice * paidQuantity == lineTotal` байх ёстой тул line-аас гаргана.
      final apiUnit = (paidWire > 0)
          ? PromotionPricingUtils.roundMoney2(lineTotal / paidWire)
          : PromotionPricingUtils.roundMoney2(unit);
      // Weve site дээр unitPrice-ийг каталогийн үнээр дахин бодож "үндсэн үнэ" гарахаас сэргийлнэ.
      // Хямдрал (tier 3%/5%, notes %, net→gross) болон 1+1 (үнэгүй) мөрүүдийг
      // backend-д "гараар үнэ" гэж тэмдэглүүлэхээр custom горим ашиглана.
      final shouldCustomPrice =
          freeWire > 0 ||
          noteMultiplier != 1.0 ||
          cartBulkMult != 1.0 ||
          item.finalUnitPrice != null;
      // Backend decrements stock by `quantity`, so send total physical.
      // To keep payable total correct even when quantity includes free pieces,
      // send custom unitPrice derived from lineTotal / totalPhysical.
      final apiUnitForBackend = (shouldCustomPrice && qtyWire > 0)
          ? PromotionPricingUtils.roundMoney2(lineTotal / qtyWire)
          : apiUnit;
      return <String, dynamic>{
        'productId': productId,
        // IMPORTANT: backend uses `quantity` to decrement stock → send total physical pieces.
        'quantity': qtyWire,
        'paidQuantity': paidWire,
        'freeQuantity': freeWire,
        'totalPiecesForStock': qtyWire,
        'unitPrice': apiUnitForBackend,
        // Custom mode үед backend каталогийн үнээр дахин бодохгүй.
        'lineTotal': PromotionPricingUtils.roundMoney2(lineTotal),
        if (shouldCustomPrice) 'priceMode': 'custom',
      };
    });
  }

  /// `OrderScreen`-ийн мөрүүд → `createOrder` items (төлөх/үнэгүй + lineTotal).
  static List<Map<String, dynamic>> buildItemsFromOrderScreenLines(
    List<OrderItem> lines,
  ) {
    return lines.map((item) {
      final productId = int.tryParse(item.productId);
      if (productId == null) {
        throw FormatException('Барааны ID буруу байна: ${item.productId}');
      }
      final paid = item.paidQuantity;
      final lineTotal = PromotionPricingUtils.roundMoney2(
        item.unitPrice * paid,
      );
      final qtyWire = item.quantity < 0 ? 0 : item.quantity;
      final apiUnit = (qtyWire > 0)
          ? PromotionPricingUtils.roundMoney2(lineTotal / qtyWire)
          : PromotionPricingUtils.roundMoney2(item.unitPrice);
      final maxFree = item.quantity - paid;
      return <String, dynamic>{
        'productId': productId,
        // Backend decrements stock by `quantity` → send total physical pieces.
        'quantity': qtyWire,
        'paidQuantity': paid,
        'freeQuantity': item.freeQuantity.clamp(0, maxFree < 0 ? 0 : maxFree),
        'totalPiecesForStock': qtyWire,
        'unitPrice': apiUnit,
        'lineTotal': lineTotal,
        'priceMode': 'custom',
      };
    }).toList();
  }

  static int? _retryAfterSeconds(DioException e) {
    final h = e.response?.headers;
    if (h == null) return null;
    final v = h.value('retry-after');
    if (v == null) return null;
    return int.tryParse(v.trim());
  }

  /// `createOrder` дуудлагыг 429 үед `Retry-After` эсвэл exponential backoff-оор дахин оролдоно.
  static Future<Map<String, dynamic>> createOrderWith429Retry(
    Future<Map<String, dynamic>> Function() createOnce, {
    int maxAttempts = 3,
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await createOnce();
      } on DioException catch (e) {
        final status = e.response?.statusCode;
        if (status != 429 || attempt == maxAttempts) rethrow;

        final ra = _retryAfterSeconds(e);
        final backoff = ra ?? (attempt * 2);
        if (kDebugMode) {
          debugPrint(
            '⏳ 429 Too Many Requests. Retrying in ${backoff}s (attempt $attempt/$maxAttempts)',
          );
        }
        await Future<void>.delayed(Duration(seconds: backoff));
      }
    }
    throw StateError('Create order retry loop failed unexpectedly');
  }
}
