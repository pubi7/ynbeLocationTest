/// **1+1 / 1+N үнэгүй**, `promotionText`-ийн **bulk %**, **сагсны олон ширхэгийн хөнгөлөлт**
/// (урамшуулалтай мөрүүдэд 50+ → 3%, 100+ → 5%) — бүх боломжит хямдрал/урамшууллын тооцооллыг **нэг файлд** төвлөрүүлсэн.
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
  /// Каталогийн нэр + API-ийн `promotionText`-ийг нэгтгэхдээ зөвхөн серверээс ирсэн
  /// текстийг буцаана; хоосон бол null (барааны нэрээр 1+1 **автоматаар** оноохгүй).
  ///
  /// Дашида saehan/saebom 1кг, Сахар бор 1кг: өмнө нь апп дээр 50+/100+ **мөрийн** 3%/5%
  /// байсан; одоо идэвхгүй тул ижил хувийн текстийг эндээс хасна ([_stripLegacyLinePieceBulkTierPhrasesFromPromo]).
  static String? mergeCatalogPromotionText(
    String productName,
    String? apiPromotionText,
  ) {
    try {
      var api = (apiPromotionText ?? '').trim();
      if (api.isEmpty) return null;
      if (_legacyLinePieceBulkTierSku(productName)) {
        api = _stripLegacyLinePieceBulkTierPhrasesFromPromo(api).trim();
        api = api
            .replaceAll(RegExp(r',\s*,+'), ',')
            .replaceAll(RegExp(r'^\s*,+\s*|\s*,+\s*$'), '')
            .trim();
      }
      return api.isEmpty ? null : api;
    } catch (_) {
      final t = apiPromotionText?.trim();
      if (t == null || t.isEmpty) return null;
      return t;
    }
  }

  /// Өмнө мөрийн 50+/100+ tier-т зориулсан SKU-ууд (одоо tier **идэвхгүй**).
  static bool _legacyLinePieceBulkTierSku(String productName) {
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

  static String _stripLegacyLinePieceBulkTierPhrasesFromPromo(String s) {
    var t = s;
    for (final p in const [
      r'50\s*ш\s*\+\s*[-]?\s*3\s*%',
      r'100\s*ш\s*\+\s*[-]?\s*5\s*%',
      r'50ш\+\s*[-]?\s*3\s*%',
      r'100ш\+\s*[-]?\s*5\s*%',
      r'50\s*ш\+\s*[-]?\s*3\s*%',
      r'100\s*ш\+\s*[-]?\s*5\s*%',
    ]) {
      t = t.replaceAll(RegExp(p, caseSensitive: false), '');
    }
    return t.trim();
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
    // "50ш+ 3%" гэх мэтээс buy/free том тоо гарвал BOGO биш — бүх дуудлагаас хамгаална.
    if (buy > 20 || free > 20 || buy + free > 40) return null;
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

  /// Нэг удаа [mergeCatalogPromotionText] + [parseBuyFree] — төлөх ширхэг ба 1+1 эсэх.
  static ({int paidPieces, bool isBogo}) resolveLinePromotion(SalesItem item) {
    final promo = mergeCatalogPromotionText(
      item.productName,
      item.promotionText,
    );
    final bf = parseBuyFree(promo);
    if (bf == null) {
      return (paidPieces: item.paidQuantity, isBogo: false);
    }
    final isBogo = bf.buy == 1 && bf.free == 1;
    if (item.freeQuantity > 0) {
      return (paidPieces: item.paidQuantity, isBogo: isBogo);
    }
    if (item.quantity <= 0) {
      return (paidPieces: 0, isBogo: isBogo);
    }
    final int paid;
    if (isBogo) {
      paid = buyOneGetOnePaidFreeFromQuantity(item.quantity).paid;
    } else {
      paid = billablePaidPiecesForBuyFreePhysical(
        physicalPieces: item.quantity,
        bf: bf,
      ).clamp(0, item.quantity);
    }
    return (paidPieces: paid, isBogo: isBogo);
  }

  /// Нэг мөр **1+1** (buy=1, free=1) урамшуулал эсэх — сагсны 50+/100+ tier-ийг энэ мөрт **хэрэглэхгүй**.
  static bool isBuyOneGetOnePromotionLine(SalesItem item) {
    return resolveLinePromotion(item).isBogo;
  }

  /// `1+1` гэх мэт buy-free тексттэй мөр дээр `freeQuantity` алдагдсан үед ч зөв төлөх
  /// ширхэгийг ашиглана (сервер/API болон [payableLineTotalInCart]-тай нийцнэ).
  static int effectiveBillablePaidPiecesForPricing(SalesItem item) {
    return resolveLinePromotion(item).paidPieces;
  }

  /// Статистик / шүүлт: зөвхөн урамшуулалтай (line-only биш) мөрүүдийн төлөх нийлбэр.
  /// **Tier суурь биш** — tier-ийг [cartWideBillablePaidPiecesSum]-аар тогтооно.
  static int cartBulkEligiblePaidPiecesTotal(Iterable<SalesItem> items) {
    var s = 0;
    for (final i in items) {
      if (!i.hasPromotionBenefit) continue;
      s += effectiveBillablePaidPiecesForPricing(i);
    }
    return s;
  }

  /// Сагсны 50+/100+ tier: **бүх мөрийн** [effectiveBillablePaidPiecesForPricing] нийлбэр.
  static int cartWideBillablePaidPiecesSum(Iterable<SalesItem> items) {
    var s = 0;
    for (final i in items) {
      s += resolveLinePromotion(i).paidPieces;
    }
    return s;
  }

  /// Урамшуулалгүй мөр: **1.0**. **1+1** мөр: **1.0** (сагсны 3%/5% tier давхардахгүй).
  /// Бусад урамшуулалтай мөр: [cartPaidPiecesBulkPriceMultiplier](eligiblePaidPiecesTotal).
  static double cartBulkPriceMultiplierForCartLine({
    required SalesItem item,
    required int eligiblePaidPiecesTotal,
    bool? isBuyOneGetOne,
  }) {
    if (!item.hasPromotionBenefit) return 1.0;
    final bogo = isBuyOneGetOne ?? isBuyOneGetOnePromotionLine(item);
    if (bogo) return 1.0;
    return cartPaidPiecesBulkPriceMultiplier(eligiblePaidPiecesTotal);
  }

  /// Сагсны **«Төлөх нийт»**-той мөр бүрээр тааруулах мөрийн дүн (хүснэгийн «Нийт»-ээс
  /// өөр байж болно — энэ нь сагсны bulk-ийг нэгж дээр оруулсны дараа).
  ///
  /// [cartWidePaidPiecesTotal] нь дуудагч [cartWideBillablePaidPiecesSum]-ээр нэг удаа
  /// тооцоолсон tier суурь байх ёстой — энд дахин O(n) гүйлгээ хийхгүй.
  static double payableLineTotalInCart(
    SalesItem item, {
    required int cartWidePaidPiecesTotal,
    double noteMultiplier = 1.0,
    int? effectivePaidPieces,
    bool? isBuyOneGetOne,
  }) {
    final paid =
        effectivePaidPieces ?? effectiveBillablePaidPiecesForPricing(item);
    final m = cartBulkPriceMultiplierForCartLine(
      item: item,
      eligiblePaidPiecesTotal: cartWidePaidPiecesTotal,
      isBuyOneGetOne: isBuyOneGetOne,
    );
    return lineTotalFromDiscountedUnit(
      unitPrice: item.price,
      noteMultiplier: noteMultiplier,
      cartBulkMultiplier: m,
      paidPieces: paid,
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
    if (parseBuyFree(promotionText) != null) return null;

    final m1 = RegExp(r'(\d+)\s*(?:ш|ширхэг|pcs?)?.*?(\d+)\s*%').firstMatch(s);
    if (m1 != null) {
      final q = int.tryParse(m1.group(1) ?? '');
      final p = int.tryParse(m1.group(2) ?? '');
      if (q != null && p != null && q > 0 && p > 0) {
        if (p < 5) return null;
        return (minQty: q, percent: p.clamp(0, 100));
      }
    }

    final m2 = RegExp(r'>=\s*(\d+)\s*(\d+)\s*%').firstMatch(s);
    if (m2 != null) {
      final q = int.tryParse(m2.group(1) ?? '');
      final p = int.tryParse(m2.group(2) ?? '');
      if (q != null && p != null && q > 0 && p > 0) {
        if (p < 5) return null;
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
  ///
  /// [cartWidePaidPiecesTotal]: сагсны бүх мөрийн [effectiveBillablePaidPiecesForPricing]
  /// нийлбэр (жишээ [cartWideBillablePaidPiecesSum]) — 50+/100+ tier-ийг энд оруулна.
  /// **1+1** мөрт tier давхардахгүй ([isBuyOneGetOnePromotionLine]-тай ижил нөхцөл).
  static PromotionDecision decide({
    required int paidPieces,
    required double baseUnitPrice,
    required bool apply,
    String? promotionText,
    int? baseDiscountPercent,
    List<Map<String, dynamic>>? rules,
    String? catalogProductName,
    int cartWidePaidPiecesTotal = 0,
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

    final mergedPromotionText = mergeCatalogPromotionText(
      (catalogProductName ?? '').trim(),
      promotionText,
    );

    final bf = parseBuyFree(mergedPromotionText);
    final isBogo = bf != null && bf.buy == 1 && bf.free == 1;

    int bestPercent = (baseDiscountPercent ?? 0).clamp(0, 100);
    int freePieces = 0;

    final safeCartWide =
        cartWidePaidPiecesTotal < 0 ? 0 : cartWidePaidPiecesTotal;
    if (!isBogo && safeCartWide > 0) {
      final tierPercent = cartPaidPiecesBulkDiscountPercent(safeCartWide);
      if (tierPercent > bestPercent) bestPercent = tierPercent;
    }

    if (rules != null && rules.isNotEmpty) {
      for (final r in rules) {
        final type = (r['type'] ?? '').toString();
        if (type == 'bulk_percent') {
          final minQty = _intish(r['minQty']) ?? 0;
          final percent = _intish(r['percent']) ?? 0;
          if (minQty > 0 &&
              minQty < 10000 &&
              percent > 0 &&
              safePaid >= minQty) {
            if (percent > bestPercent) bestPercent = percent.clamp(0, 100);
          }
        } else if (type == 'percent') {
          final percent = _intish(r['percent']) ?? 0;
          if (percent > bestPercent) bestPercent = percent.clamp(0, 100);
        } else if (type == 'buy_free') {
          final buy = _intish(r['buy']) ?? 0;
          final free = _intish(r['free']) ?? 0;
          if (buy > 0 &&
              free > 0 &&
              buy <= 20 &&
              free <= 20 &&
              buy + free <= 40) {
            final groups = safePaid ~/ buy;
            final f = (groups * free).clamp(0, 1 << 30);
            if (f > freePieces) freePieces = f;
          }
        }
      }
    } else {
      freePieces = freePiecesForPromotionFromPaid(
        paidPieces: safePaid,
        promotionText: mergedPromotionText,
      );
      bestPercent = effectiveDiscountPercent(
        paidPieces: safePaid,
        promotionText: mergedPromotionText,
        baseDiscountPercent: bestPercent,
        apply: true,
      );
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
    final resolved = cart.map(resolveLinePromotion).toList();
    final paidPiecesList = resolved.map((r) => r.paidPieces).toList();
    final tierBase =
        paidPiecesList.fold<int>(0, (sum, p) => sum + p);

    return List<SalesItem>.generate(cart.length, (i) {
      final item = cart[i];
      final paid = paidPiecesList[i];
      final isBogo = resolved[i].isBogo;
      final cartBulkMult = cartBulkPriceMultiplierForCartLine(
        item: item,
        eligiblePaidPiecesTotal: tierBase,
        isBuyOneGetOne: isBogo,
      );
      final unit = discountedUnitPrice(
        unitPrice: item.price,
        noteMultiplier: noteMultiplier,
        cartBulkMultiplier: cartBulkMult,
      );
      final lineTotal = roundToWholeMnt(unit * paid);
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
    });
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
