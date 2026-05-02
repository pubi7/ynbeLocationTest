/// **1+1 / 1+N үнэгүй**, `promotionText`-ийн **bulk %**, **сагсны олон ширхэгийн хөнгөлөлт**
/// (50+ → 3%, 100+ → 5%) — бүх боломжит хямдрал/урамшууллын тооцооллыг **нэг файлд** төвлөрүүлсэн.
/// **1+1** (`buy=1`,`free=1`) мөр дээр сагсны tier **давхардахгүй** ([cartBulkPriceMultiplierForCartLine] → 1.0).
///
/// Хэрэглээ: [PromotionPricingUtils.decide] (сагс, нэмэх урсгал), [PromotionPricingUtils.parseBuyFree],
/// [PromotionPricingUtils.cartWideBillablePaidPiecesSum] (tier суурь),
/// [PromotionPricingUtils.cartBulkPriceMultiplierForCartLine] (сагсны bulk).
///
/// Бусад файлууд ихэвчлэн `promotion_pricing_utils.dart` импортолно (тэр нь энэ файлыг export хийнэ).

import '../models/sales_item_model.dart';

/// Promotion / discount — нэг эх үүсвэр.
///
/// - `1+1`, `1 + 2`, fullwidth `＋` зэрэг `promotionText`-аас parse
/// - Төлөх ширхэгээр үнэгүй ширхэг тооцох
/// - Хувийн хямдрал + текстэн bulk + ирээдүйн `rules` JSON
/// - Сагсны олон ширхэгийн %: зөвхөн **урамшуулалтай** мөрүүдийн төлөх ширхэгийн нийлбэрээр
class PromotionPricingUtils {
  /// `1+1`, `1 + 2` гэх мэт — ASCII `+` болон fullwidth `＋`.
  /// Каталогоос `promotionText` дутуу / буруу ирсэн ч тодорхой бараанд 1+1 үйлчлүүлнэ.
  /// Жишээ: «Чикен spicy соус 2.1кг» — 1 төлөхөд 1 үнэгүй.
  static String? mergeCatalogPromotionText(
    String productName,
    String? apiPromotionText,
  ) {
    final api = (apiPromotionText ?? '').trim();
    if (_isChickenSpicySauce21kg(productName)) {
      if (api.isEmpty) return '1+1';
      if (parseBuyFree(api) != null) return api;
      return '$api 1+1';
    }
    return api.isEmpty ? null : api;
  }

  static bool _isChickenSpicySauce21kg(String productName) {
    final n = productName.toLowerCase();
    final hasChicken =
        n.contains('чикен') || n.contains('chicken') || n.contains('тахиан');
    final hasSauce = n.contains('соус');
    final hasSpicy =
        n.contains('spicy') || n.contains('спайси') || n.contains('spайси');
    final has21 =
        n.contains('2.1') || n.contains('2,1') || n.contains('2.1кг');
    return hasChicken && hasSauce && hasSpicy && has21;
  }

  /// Дашида saebom / saehan 1кг, Сахар бор 1кг: **зөвхөн энэ мөрийн** төлөх ширхэгээр
  /// 50+ → 3%, 100+ → 5% ([cartPaidPiecesBulkDiscountPercent]). Сагсны нийлбэрийн bulk-д орохгүй.
  static bool isLineOnlyPieceBulkTierProduct(String productName) {
    final n = productName.toLowerCase();
    final has1kg = n.contains('1кг') || n.contains('1 кг');
    if (!has1kg) return false;
    if (n.contains('сахар') && n.contains('бор')) return true;
    if (n.contains('дашида')) {
      if (n.contains('saebom')) return true;
      if (n.contains('saehan')) return true;
    }
    return false;
  }

  /// Хэрэглэгчийн оруулсан **нийт физ ширхэг** (жишээ 1+1-д 2 савлах) → [decide]-ийн
  /// [paidPieces]: `ceil(physical * buy / (buy+free))` (1+1, 2 физ → 1 төлөх).
  static int billablePaidPiecesForBuyFreePhysical({
    required int physicalPieces,
    required ({int buy, int free}) bf,
  }) {
    if (physicalPieces <= 0) return 0;
    final bundle = bf.buy + bf.free;
    if (bundle <= 0) return physicalPieces;
    return ((physicalPieces * bf.buy) + bundle - 1) ~/ bundle;
  }

  /// **1+1** зөвхөн: физ ширхэг → (төлөх, үнэгүй). `төлөх = ceil(qty/2)`, `үнэгүй = qty - төлөх`.
  ///
  /// | qty | төлөх | үнэгүй |
  /// |-----|-------|--------|
  /// | 1   | 1     | 0      |
  /// | 2   | 1     | 1      |
  /// | 3   | 2     | 1      |
  /// | 4   | 2     | 2      |
  ///
  /// Эквивалент: `free = quantity ~/ 2`, `paid = quantity - free` (1+1-д л).
  /// `paid = quantity ~/ 2` гэж биш — 1 ширхэгт төлөх 0 болно.
  static ({int paid, int free}) buyOneGetOnePaidFreeFromQuantity(int quantity) {
    if (quantity <= 0) return (paid: 0, free: 0);
    final paid = (quantity + 1) ~/ 2;
    return (paid: paid, free: quantity - paid);
  }

  static ({int buy, int free})? parseBuyFree(String? promotionText) {
    final s = (promotionText ?? '').toLowerCase();
    var m = RegExp(r'(\d+)\s*[\u002b\uff0b]\s*(\d+)').firstMatch(s);
    // "1:1", "2:1" гэх мэт (зарим каталог)
    m ??= RegExp(r'(\d+)\s*:\s*(\d+)').firstMatch(s);
    if (m == null) return null;
    final buy = int.tryParse(m.group(1) ?? '');
    final free = int.tryParse(m.group(2) ?? '');
    if (buy == null || free == null) return null;
    if (buy <= 0 || free <= 0) return null;
    return (buy: buy, free: free);
  }

  /// Төлөх ширхэг (`paidPieces`) → үнэгүй ширхэг.
  ///
  /// **Стандарт (давтагддаг buy N get M free):** `floor(paid / buy) * free`.
  /// - `1+1` (`buy=1`, `free=1`): төлөх 1 → үнэгүй 1, төлөх 2 → 2, … (таны хүснэгттэй таарна).
  /// - `2+1`: төлөх 2 → үнэгүй 1, төлөх 4 → 2, төлөх 1 → 0.
  ///
  /// `paid ~/ (buy+free)` гэсэн тооцоо нь **энд** (`paid` = зөвхөн төлөх ширхэг) буруу:
  /// `1+1`-д төлөх 1 үед `1 ~/ 2 = 0` → үнэгүй 0 болно.
  ///
  /// **Нэг удаагийн** «төлөх ≥ 1 бол үнэгүй 1» гэдгийг энд оруулаагүй — тусад нь дүрэм/флаг шаардлагатай.
  static int freePiecesForPromotionFromPaid({
    required int paidPieces,
    required String? promotionText,
  }) {
    if (paidPieces <= 0) return 0;
    final bf = parseBuyFree(promotionText);
    if (bf == null) return 0;
    final groups = paidPieces ~/ bf.buy;
    if (groups <= 0) return 0;
    return (groups * bf.free).clamp(0, 1 << 30);
  }

  static double applyPercentDiscount({
    required double unitPrice,
    required int? discountPercent,
    required bool apply,
  }) {
    if (!apply) return unitPrice;
    final dp = discountPercent ?? 0;
    if (dp <= 0) return unitPrice;
    final m = 1 - (dp / 100.0);
    if (m <= 0) return 0;
    return unitPrice * m;
  }

  /// [totalPaidPieces] = сагсан дахь **бүх мөр**ийн төлөх ширхэгийн нийлбэр
  /// ([cartWideBillablePaidPiecesSum]) → 100+ **5%**, 50–99 **3%**.
  /// Хөнгөлөлтийг хэн авч болохыг [cartBulkPriceMultiplierForCartLine] шийднэ.
  static int cartPaidPiecesBulkDiscountPercent(int totalPaidPieces) {
    if (totalPaidPieces < 0) return 0;
    if (totalPaidPieces >= 100) return 5;
    if (totalPaidPieces >= 50) return 3;
    return 0;
  }

  static double cartPaidPiecesBulkPriceMultiplier(int totalPaidPieces) {
    final p = cartPaidPiecesBulkDiscountPercent(totalPaidPieces);
    if (p <= 0) return 1.0;
    return 1.0 - (p / 100.0);
  }

  /// Нэг мөр **1+1** (buy=1, free=1) урамшуулал эсэх — сагсны 50+/100+ tier-ийг энэ мөрт **хэрэглэхгүй**.
  static bool isBuyOneGetOnePromotionLine(SalesItem item) {
    if (isLineOnlyPieceBulkTierProduct(item.productName)) return false;
    final promoForBuyFree = mergeCatalogPromotionText(
      item.productName,
      item.promotionText,
    );
    final bf = parseBuyFree(promoForBuyFree);
    if (bf == null) return false;
    if (bf.buy > 20 || bf.free > 20 || bf.buy + bf.free > 40) return false;
    return bf.buy == 1 && bf.free == 1;
  }

  /// `1+1` гэх мэт buy-free тексттэй мөр дээр `freeQuantity` алдагдсан үед ч зөв төлөх
  /// ширхэгийг ашиглана (сервер/API болон [payableLineTotalInCart]-тай нийцнэ).
  static int effectiveBillablePaidPiecesForPricing(SalesItem item) {
    if (isLineOnlyPieceBulkTierProduct(item.productName)) {
      return item.paidQuantity;
    }
    // Каталогийн нэрээр нэгдсэн текст (жишээ чикен 2.1кг → API-д promo байхгүй ч «1+1»).
    final promoForBuyFree = mergeCatalogPromotionText(
      item.productName,
      item.promotionText,
    );
    final bf = parseBuyFree(promoForBuyFree);
    if (bf == null) return item.paidQuantity;
    // "50ш+ 3%, 100ш+ 5%" гэх мэтээс parseBuyFree буруу том тоо авч болно — зөвхөн жинхэнэ BOGO.
    if (bf.buy > 20 || bf.free > 20 || bf.buy + bf.free > 40) {
      return item.paidQuantity;
    }
    if (item.freeQuantity > 0) return item.paidQuantity;
    if (item.quantity <= 0) return 0;
    if (bf.buy == 1 && bf.free == 1) {
      return buyOneGetOnePaidFreeFromQuantity(item.quantity).paid;
    }
    return billablePaidPiecesForBuyFreePhysical(
      physicalPieces: item.quantity,
      bf: bf,
    ).clamp(0, item.quantity);
  }

  /// Статистик / шүүлт: зөвхөн урамшуулалтай (line-only биш) мөрүүдийн төлөх нийлбэр.
  /// **Tier суурь биш** — tier-ийг [cartWideBillablePaidPiecesSum]-аар тогтооно.
  static int cartBulkEligiblePaidPiecesTotal(Iterable<SalesItem> items) {
    var s = 0;
    for (final i in items) {
      if (!i.hasPromotionBenefit) continue;
      if (isLineOnlyPieceBulkTierProduct(i.productName)) continue;
      s += effectiveBillablePaidPiecesForPricing(i);
    }
    return s;
  }

  /// Сагсны 50+/100+ tier: **бүх мөрийн** [effectiveBillablePaidPiecesForPricing] нийлбэр.
  static int cartWideBillablePaidPiecesSum(Iterable<SalesItem> items) {
    var s = 0;
    for (final i in items) {
      s += effectiveBillablePaidPiecesForPricing(i);
    }
    return s;
  }

  /// Урамшуулалгүй мөр: **1.0**. **1+1** мөр: **1.0** (сагсны 3%/5% tier давхардахгүй).
  /// Бусад урамшуулалтай мөр: [cartPaidPiecesBulkPriceMultiplier](eligiblePaidPiecesTotal).
  static double cartBulkPriceMultiplierForCartLine({
    required SalesItem item,
    required int eligiblePaidPiecesTotal,
  }) {
    if (!item.hasPromotionBenefit) return 1.0;
    if (isLineOnlyPieceBulkTierProduct(item.productName)) return 1.0;
    if (isBuyOneGetOnePromotionLine(item)) return 1.0;
    return cartPaidPiecesBulkPriceMultiplier(eligiblePaidPiecesTotal);
  }

  /// Сагсны **«Төлөх нийт»**-той мөр бүрээр тааруулах мөрийн дүн (хүснэгийн «Нийт»-ээс
  /// өөр байж болно — энэ нь сагсны bulk-ийг нэгж дээр оруулсны дараа).
  static double payableLineTotalInCart(
    SalesItem item,
    Iterable<SalesItem> cart, {
    double noteMultiplier = 1.0,
  }) {
    final tierBase = cartWideBillablePaidPiecesSum(cart);
    final m = cartBulkPriceMultiplierForCartLine(
      item: item,
      eligiblePaidPiecesTotal: tierBase,
    );
    return lineTotalFromDiscountedUnit(
      unitPrice: item.price,
      noteMultiplier: noteMultiplier,
      cartBulkMultiplier: m,
      paidPieces: effectiveBillablePaidPiecesForPricing(item),
    );
  }

  /// Мөнгө: 2 аравтын бутархайг тэгшитгэнэ (бусад баримтын тооцоонд).
  static double roundMoney2(double value) =>
      (value * 100).roundToDouble() / 100;

  /// Бүхэл ₮ (хамгийн ойрын бүхэл тоо) — жишээ: 11,690×0.97=11,339.3 → **11,339**.
  static double roundToWholeMnt(double value) {
    if (value.isNaN || value.isInfinite) return 0;
    return value.roundToDouble();
  }

  /// Хөнгөлөлтийг мөрийн **нийт** дээр биш, **нэгжийн үнэ** дээр хэрэглээд **бүхэл ₮** болгож,
  /// дараа нь төлөх ширхэгээр үржүүлнэ (жишээ: 11,339×50=566,950).
  static double discountedUnitPrice({
    required double unitPrice,
    double noteMultiplier = 1.0,
    required double cartBulkMultiplier,
  }) {
    final m = noteMultiplier * cartBulkMultiplier;
    if (m <= 0) return 0;
    return roundToWholeMnt(unitPrice * m);
  }

  /// [unitPrice] = нэгж (НӨАТ-тай эсвэл татваргүй — дуудагчийн контекст), [paidPieces] = төлөх ширхэг.
  static double lineTotalFromDiscountedUnit({
    required double unitPrice,
    double noteMultiplier = 1.0,
    required double cartBulkMultiplier,
    required int paidPieces,
  }) {
    if (paidPieces <= 0) return 0;
    final u = discountedUnitPrice(
      unitPrice: unitPrice,
      noteMultiplier: noteMultiplier,
      cartBulkMultiplier: cartBulkMultiplier,
    );
    return roundToWholeMnt(u * paidPieces);
  }

  /// Текстэн bulk: "10 ширхэг … 20%", ">=10 20%" гэх мэт.
  static ({int minQty, int percent})? parseBulkDiscount(String? promotionText) {
    final s = (promotionText ?? '').toLowerCase();
    if (s.trim().isEmpty) return null;

    final m1 = RegExp(r'(\d+)\s*(?:ш|ширхэг|pcs?)?.*?(\d+)\s*%').firstMatch(s);
    if (m1 != null) {
      final q = int.tryParse(m1.group(1) ?? '');
      final p = int.tryParse(m1.group(2) ?? '');
      if (q != null && p != null && q > 0 && p > 0) {
        return (minQty: q, percent: p.clamp(0, 100));
      }
    }

    final m2 = RegExp(r'>=\s*(\d+)\s*(\d+)\s*%').firstMatch(s);
    if (m2 != null) {
      final q = int.tryParse(m2.group(1) ?? '');
      final p = int.tryParse(m2.group(2) ?? '');
      if (q != null && p != null && q > 0 && p > 0) {
        return (minQty: q, percent: p.clamp(0, 100));
      }
    }

    return null;
  }

  static int effectiveDiscountPercent({
    required int paidPieces,
    required String? promotionText,
    required int? baseDiscountPercent,
    required bool apply,
  }) {
    if (!apply) return 0;
    var best = (baseDiscountPercent ?? 0).clamp(0, 100);
    final bulk = parseBulkDiscount(promotionText);
    if (bulk != null && paidPieces >= bulk.minQty) {
      if (bulk.percent > best) best = bulk.percent;
    }
    return best;
  }

  /// Нэгжийн хувь + үнэгүй ширхэг — бүх урамшууллын нэгдсэн гаралт.
  static PromotionDecision decide({
    required int paidPieces,
    required double baseUnitPrice,
    required bool apply,
    String? promotionText,
    int? baseDiscountPercent,
    List<Map<String, dynamic>>? rules,
    /// Мөрийн tier (жишээ [isLineOnlyPieceBulkTierProduct]) — нэрээр идэвхжинэ.
    String? catalogProductName,
  }) {
    final safePaid = paidPieces < 0 ? 0 : paidPieces;
    final safeBase = baseUnitPrice < 0 ? 0.0 : baseUnitPrice;
    if (!apply || safePaid <= 0) {
      return PromotionDecision(
        paidPieces: safePaid,
        totalPieces: safePaid,
        freePieces: 0,
        appliedDiscountPercent: 0,
        unitPriceAfterDiscount: safeBase,
      );
    }

    int bestPercent = (baseDiscountPercent ?? 0).clamp(0, 100);
    int freePieces = 0;

    if (rules != null && rules.isNotEmpty) {
      for (final r in rules) {
        final type = (r['type'] ?? '').toString();
        if (type == 'bulk_percent') {
          final minQty = _intish(r['minQty']) ?? 0;
          final percent = _intish(r['percent']) ?? 0;
          if (minQty > 0 && percent > 0 && safePaid >= minQty) {
            if (percent > bestPercent) bestPercent = percent.clamp(0, 100);
          }
        } else if (type == 'percent') {
          final percent = _intish(r['percent']) ?? 0;
          if (percent > bestPercent) bestPercent = percent.clamp(0, 100);
        } else if (type == 'buy_free') {
          final buy = _intish(r['buy']) ?? 0;
          final free = _intish(r['free']) ?? 0;
          if (buy > 0 && free > 0) {
            final groups = safePaid ~/ buy;
            final f = (groups * free).clamp(0, 1 << 30);
            if (f > freePieces) freePieces = f;
          }
        }
      }
    } else {
      freePieces = freePiecesForPromotionFromPaid(
        paidPieces: safePaid,
        promotionText: promotionText,
      );
      bestPercent = effectiveDiscountPercent(
        paidPieces: safePaid,
        promotionText: promotionText,
        baseDiscountPercent: baseDiscountPercent,
        apply: true,
      );
      final name = (catalogProductName ?? '').trim();
      if (name.isNotEmpty && isLineOnlyPieceBulkTierProduct(name)) {
        final tier = cartPaidPiecesBulkDiscountPercent(safePaid);
        if (tier > bestPercent) bestPercent = tier;
      }
    }

    final unitAfter = applyPercentDiscount(
      unitPrice: safeBase,
      discountPercent: bestPercent,
      apply: bestPercent > 0,
    );

    return PromotionDecision(
      paidPieces: safePaid,
      totalPieces: safePaid + freePieces,
      freePieces: freePieces,
      appliedDiscountPercent: bestPercent,
      unitPriceAfterDiscount: unitAfter,
    );
  }

  /// Сагсны мөр бүрт **нэг удаа** тооцоолсон [SalesItem.finalUnitPrice] / [SalesItem.finalLineTotal].
  /// ([noteMultiplier]: 1 эсвэл тэмдэглэлийн %).
  static List<SalesItem> applyFinalPricingToCart(
    List<SalesItem> cart, {
    double noteMultiplier = 1.0,
  }) {
    if (cart.isEmpty) return cart;
    final tierBase = cartWideBillablePaidPiecesSum(cart);
    return cart
        .map(
          (item) {
            final cartBulkMult = cartBulkPriceMultiplierForCartLine(
              item: item,
              eligiblePaidPiecesTotal: tierBase,
            );
            final lineTotal = payableLineTotalInCart(
              item,
              cart,
              noteMultiplier: noteMultiplier,
            );
            final unit = discountedUnitPrice(
              unitPrice: item.price,
              noteMultiplier: noteMultiplier,
              cartBulkMultiplier: cartBulkMult,
            );
            return SalesItem(
              productId: item.productId,
              productName: item.productName,
              price: item.price,
              quantity: item.quantity,
              orderedUnit: item.orderedUnit,
              orderedQuantity: item.orderedQuantity,
              unitsPerBox: item.unitsPerBox,
              freeQuantity: item.freeQuantity,
              unitPriceExcludesVat: item.unitPriceExcludesVat,
              discountPercent: item.discountPercent,
              promotionText: item.promotionText,
              finalUnitPrice: unit,
              finalLineTotal: roundMoney2(lineTotal),
            );
          },
        )
        .toList();
  }

  static int? _intish(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }
}

/// [PromotionPricingUtils.decide]-ийн үр дүн.
class PromotionDecision {
  final int paidPieces;
  final int totalPieces;
  final int freePieces;
  final int appliedDiscountPercent;
  final double unitPriceAfterDiscount;

  const PromotionDecision({
    required this.paidPieces,
    required this.totalPieces,
    required this.freePieces,
    required this.appliedDiscountPercent,
    required this.unitPriceAfterDiscount,
  });
}
