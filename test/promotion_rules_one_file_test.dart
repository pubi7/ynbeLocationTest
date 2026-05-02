import 'package:flutter_test/flutter_test.dart';

import 'package:aguulgav3/models/sales_item_model.dart';
import 'package:aguulgav3/utils/promotion_pricing_utils.dart';

void main() {
  group('freePiecesForPromotionFromPaid (төлөх ширхэг)', () {
    test('1+1 давтагддаг: төлөх = үнэгүй', () {
      const t = '1+1';
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 1,
          promotionText: t,
        ),
        1,
      );
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 2,
          promotionText: t,
        ),
        2,
      );
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 3,
          promotionText: t,
        ),
        3,
      );
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 4,
          promotionText: t,
        ),
        4,
      );
    });

    test('2+1: төлөх 2 тутамд үнэгүй 1', () {
      const t = '2+1';
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 1,
          promotionText: t,
        ),
        0,
      );
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 2,
          promotionText: t,
        ),
        1,
      );
      expect(
        PromotionPricingUtils.freePiecesForPromotionFromPaid(
          paidPieces: 4,
          promotionText: t,
        ),
        2,
      );
    });

    test('decide 1+1: нийт = төлөх + үнэгүй', () {
      final d = PromotionPricingUtils.decide(
        paidPieces: 1,
        baseUnitPrice: 100,
        apply: true,
        promotionText: '1+1',
      );
      expect(d.freePieces, 1);
      expect(d.totalPieces, 2);
    });

    test('buyOneGetOnePaidFreeFromQuantity — qty 1..4 хүснэг', () {
      expect(PromotionPricingUtils.buyOneGetOnePaidFreeFromQuantity(1), (paid: 1, free: 0));
      expect(PromotionPricingUtils.buyOneGetOnePaidFreeFromQuantity(2), (paid: 1, free: 1));
      expect(PromotionPricingUtils.buyOneGetOnePaidFreeFromQuantity(3), (paid: 2, free: 1));
      expect(PromotionPricingUtils.buyOneGetOnePaidFreeFromQuantity(4), (paid: 2, free: 2));
    });

    test('billablePaidPiecesForBuyFreePhysical: 2 физ 1+1 → 1 төлөх', () {
      const bf = (buy: 1, free: 1);
      expect(
        PromotionPricingUtils.billablePaidPiecesForBuyFreePhysical(
          physicalPieces: 2,
          bf: bf,
        ),
        1,
      );
      expect(
        PromotionPricingUtils.billablePaidPiecesForBuyFreePhysical(
          physicalPieces: 4,
          bf: bf,
        ),
        2,
      );
    });

    test('олон ширхэгийн tier: 50→3%, 100→5%; 49-оос доош 0%', () {
      expect(
        PromotionPricingUtils.cartPaidPiecesBulkDiscountPercent(50),
        3,
      );
      expect(
        PromotionPricingUtils.cartPaidPiecesBulkDiscountPercent(1),
        0,
      );
      expect(
        PromotionPricingUtils.cartPaidPiecesBulkPriceMultiplier(50),
        lessThan(1.0),
      );
      expect(
        PromotionPricingUtils.cartPaidPiecesBulkPriceMultiplier(1),
        1.0,
      );
    });

    test('сагсны bulk tier: бүх мөрийн төлөх нийлбэр; mult зөвхөн урамшуулалтай мөр', () {
      final promo50 = SalesItem(
        productId: 'a',
        productName: 'Promo',
        price: 1000,
        quantity: 50,
        promotionText: '1+1',
      );
      final normal10 = SalesItem(
        productId: 'b',
        productName: 'Normal',
        price: 500,
        quantity: 10,
      );
      final items = [promo50, normal10];
      // 50 физ 1+1 → төлөх 25; + энгийн 10
      expect(PromotionPricingUtils.cartBulkEligiblePaidPiecesTotal(items), 25);
      expect(PromotionPricingUtils.cartWideBillablePaidPiecesSum(items), 35);
      // 1+1 мөр: сагсны 50+/100+ tier (3%/5%) давхардахгүй
      expect(
        PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
          item: promo50,
          eligiblePaidPiecesTotal: 60,
        ),
        1.0,
      );
      expect(
        PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
          item: normal10,
          eligiblePaidPiecesTotal: 60,
        ),
        1.0,
      );

      final promo30 = SalesItem(
        productId: 'c',
        productName: 'P2',
        price: 100,
        quantity: 30,
        promotionText: 'sale',
      );
      final normal30 = SalesItem(
        productId: 'd',
        productName: 'N2',
        price: 100,
        quantity: 30,
      );
      final mix = [promo30, normal30];
      expect(
        PromotionPricingUtils.cartBulkEligiblePaidPiecesTotal(mix),
        30,
      );
      expect(PromotionPricingUtils.cartWideBillablePaidPiecesSum(mix), 60);
      expect(
        PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
          item: promo30,
          eligiblePaidPiecesTotal: 60,
        ),
        PromotionPricingUtils.cartPaidPiecesBulkPriceMultiplier(60),
      );
    });

    test('нэгж бүхэл ₮ → нийт (11,690×0.97 → 11,339; ×50=566,950)', () {
      const unit = 11690.0;
      const mult = 0.97;
      const qty = 50;
      expect(
        PromotionPricingUtils.discountedUnitPrice(
          unitPrice: unit,
          cartBulkMultiplier: mult,
        ),
        11339.0,
      );
      expect(
        PromotionPricingUtils.lineTotalFromDiscountedUnit(
          unitPrice: unit,
          cartBulkMultiplier: mult,
          paidPieces: qty,
        ),
        566950.0,
      );
    });
  });

  group('mergeCatalogPromotionText — Чикен spicy соус 2.1кг', () {
    test('API promo хоосон бол 1+1', () {
      expect(
        PromotionPricingUtils.mergeCatalogPromotionText(
          'Чикен spicy соус 2.1кг',
          null,
        ),
        '1+1',
      );
    });

    test('Нэр англи + 1 төлөх → үнэгүй 1', () {
      final promo = PromotionPricingUtils.mergeCatalogPromotionText(
        'Chicken spicy соус 2.1kg',
        null,
      );
      final d = PromotionPricingUtils.decide(
        paidPieces: 1,
        baseUnitPrice: 100,
        apply: true,
        promotionText: promo,
      );
      expect(d.freePieces, 1);
      expect(d.totalPieces, 2);
    });

    test('Өөр бараанд API/null буцаана', () {
      expect(
        PromotionPricingUtils.mergeCatalogPromotionText('Өөр бараа', null),
        isNull,
      );
      expect(
        PromotionPricingUtils.mergeCatalogPromotionText('Өөр бараа', '10ш 5%'),
        '10ш 5%',
      );
    });
  });

  group('isLineOnlyPieceBulkTierProduct — Дашида / Сахар бор 1кг', () {
    test('дашида saebom 1кг', () {
      expect(
        PromotionPricingUtils.isLineOnlyPieceBulkTierProduct(
          'Дашида saebom 1кг',
        ),
        isTrue,
      );
    });
    test('дашида saehan 1кг', () {
      expect(
        PromotionPricingUtils.isLineOnlyPieceBulkTierProduct(
          'Дашида saehan 1кг',
        ),
        isTrue,
      );
    });
    test('сахар бор 1кг', () {
      expect(
        PromotionPricingUtils.isLineOnlyPieceBulkTierProduct('Сахар бор 1кг'),
        isTrue,
      );
    });
    test('decide: төлөх 60 → 3%, 100 → 5%', () {
      final d60 = PromotionPricingUtils.decide(
        paidPieces: 60,
        baseUnitPrice: 10000,
        apply: true,
        promotionText: null,
        catalogProductName: 'Сахар бор 1кг',
      );
      expect(d60.appliedDiscountPercent, 3);
      final d100 = PromotionPricingUtils.decide(
        paidPieces: 100,
        baseUnitPrice: 10000,
        apply: true,
        promotionText: null,
        catalogProductName: 'Дашида saebom 1кг',
      );
      expect(d100.appliedDiscountPercent, 5);
    });
    test('сагсны eligible-д line-only мөр орохгүй', () {
      final sugar = SalesItem(
        productId: '1',
        productName: 'Сахар бор 1кг',
        price: 100,
        quantity: 60,
        promotionText: '50ш+ 3%, 100ш+ 5%',
      );
      final promo = SalesItem(
        productId: '2',
        productName: 'Promo',
        price: 100,
        quantity: 50,
        promotionText: '1+1',
      );
      expect(
        PromotionPricingUtils.cartBulkEligiblePaidPiecesTotal([sugar, promo]),
        25,
      );
    });
  });

  group('effectiveBillablePaidPiecesForPricing — buy-free текст, freeQuantity 0', () {
    test('2 физ 1+1, үнэгүй талбар 0 → төлөх 1, мөрийн дүн = 1×нэгж', () {
      final item = SalesItem(
        productId: '1',
        productName: 'Чикен spicy соус 2.1кг',
        price: 24990,
        quantity: 2,
        promotionText: '1+1',
      );
      expect(PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item), 1);
      expect(
        PromotionPricingUtils.payableLineTotalInCart(item, [item]),
        24990.0,
      );
    });

    test('API promo хоосон ч нэрээр 1+1 — төлөх 1 (илгээлтийн 49980 алдааг засна)', () {
      final item = SalesItem(
        productId: '1',
        productName: 'Чикен spicy соус 2.1кг',
        price: 24990,
        quantity: 2,
        promotionText: null,
      );
      expect(PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item), 1);
      expect(
        PromotionPricingUtils.payableLineTotalInCart(item, [item]),
        24990.0,
      );
    });

    test('«спайси» кирилл — API promo хоосон, төлөх 1', () {
      final item = SalesItem(
        productId: '1',
        productName: 'Чикен спайси соус 2.1кг',
        price: 24990,
        quantity: 2,
        promotionText: null,
      );
      expect(
        PromotionPricingUtils.mergeCatalogPromotionText(
          item.productName,
          null,
        ),
        '1+1',
      );
      expect(PromotionPricingUtils.effectiveBillablePaidPiecesForPricing(item), 1);
    });
  });

  group('applyFinalPricingToCart', () {
    test('нэг мөр — finalLineTotal = payableLineTotalInCart', () {
      final cart = [
        SalesItem(
          productId: '1',
          productName: 'X',
          price: 100,
          quantity: 2,
        ),
      ];
      final priced = PromotionPricingUtils.applyFinalPricingToCart(
        cart,
        noteMultiplier: 1.0,
      );
      final expected = PromotionPricingUtils.roundMoney2(
        PromotionPricingUtils.payableLineTotalInCart(cart.first, cart),
      );
      expect(priced.single.finalLineTotal, expected);
      expect(priced.single.finalUnitPrice, isNotNull);
    });
  });
}
