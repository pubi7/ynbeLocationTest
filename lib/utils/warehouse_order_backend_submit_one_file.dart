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
    debugPrint('📋 Backend items: ${items.length} мөр (quantity=нийт төлөх+үнэгүй)');
    for (var i = 0; i < items.length; i++) {
      final m = items[i];
      final id = m['productId'];
      final q = m['quantity'];
      final paid = m['paidQuantity'];
      final free = m['freeQuantity'];
      final unit = m['unitPrice'];
      final line = m['lineTotal'];
      final mode = m['priceMode'];
      final name = (productNames != null && i < productNames.length)
          ? productNames[i].trim()
          : '';
      final suffix = name.isNotEmpty ? ' — $name' : '';
      debugPrint(
        '   [$i] productId=$id$suffix → quantity(нийт ш)=$q, paidQuantity=$paid, '
        'freeQuantity=$free, unitPrice=$unit, lineTotal=$line'
        '${mode != null ? ', priceMode=$mode' : ''}',
      );
    }
  }

  /// Сервер `grossAmount` дээр [extractVAT] (НӨАТ орсон дүн гэж) задалдаг.
  /// Сагсны үнэ **НӨАТ-гүй** ([SalesItem.unitPriceExcludesVat]) бол нэгж/мөрийг +10% болгон илгээнэ.
  static ({double unit, double line}) _apiGrossUnitAndLineIfNet({
    required SalesItem item,
    required double unit,
    required double line,
  }) {
    if (!item.unitPriceExcludesVat) {
      return (
        unit: unit,
        line: PromotionPricingUtils.roundMoney2(line),
      );
    }
    return (
      unit: PromotionPricingUtils.roundMoney2(unit * 1.1),
      line: PromotionPricingUtils.roundMoney2(line * 1.1),
    );
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
  static List<Map<String, dynamic>> buildItemsFromSalesCart(
    List<SalesItem> selectedItems, {
    required bool applyDiscountFromNotes,
    required String notesTrimmed,
  }) {
    final notePercent =
        applyDiscountFromNotes ? parsePercentFromNotes(notesTrimmed) : null;
    final noteMultiplier =
        (notePercent != null) ? (1 - (notePercent / 100.0)) : 1.0;
    return selectedItems.map((item) {
      final productId = int.tryParse(item.productId);
      if (productId == null) {
        throw FormatException('Барааны ID буруу байна: ${item.productId}');
      }
      final paidWire =
          PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item);
      final freeWire = (item.quantity - paidWire).clamp(0, item.quantity);
      final tierBase =
          PromotionPricingUtils.cartWideBillablePaidPiecesSum(selectedItems);
      final cartBulkMult =
          PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
        item: item,
        eligiblePaidPiecesTotal: tierBase,
      );
      // Мөрийн дүнг үргэлж сагсны [payableLineTotalInCart]-аас — finalLineTotal хуучирсан
      // (1+1 төлөх 2 гэж үлдсэн) үед серверт буруу дүн очихоос сэргийлнэ.
      final lineTotal = PromotionPricingUtils.roundMoney2(
        PromotionPricingUtils.payableLineTotalInCart(
          item,
          selectedItems,
          noteMultiplier: noteMultiplier,
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
      final gross = _apiGrossUnitAndLineIfNet(
        item: item,
        unit: unit,
        line: lineTotal,
      );
      return <String, dynamic>{
        'productId': productId,
        'quantity': item.quantity,
        'paidQuantity': paidWire,
        'freeQuantity': freeWire,
        'unitPrice': gross.unit,
        'lineTotal': gross.line,
        // Сервер `auto`-оор каталогийн үнээр дахин бодохгүй — зөвхөн үнэгүйтэй BOGO мөр.
        if (freeWire > 0) 'priceMode': 'custom',
      };
    }).toList();
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
      return <String, dynamic>{
        'productId': productId,
        'quantity': item.quantity,
        'paidQuantity': paid,
        if (item.freeQuantity > 0) 'freeQuantity': item.freeQuantity,
        'unitPrice': item.unitPrice,
        'lineTotal': lineTotal,
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
