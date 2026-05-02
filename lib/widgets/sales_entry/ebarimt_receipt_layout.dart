import 'package:barcode_widget/barcode_widget.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../models/sales_item_model.dart';
import '../../utils/promotion_pricing_utils.dart';
import '../../utils/receipt_vat.dart';

/// И-баримтын албан жишигт ойролцоо толгой + хүснэгт + дүн (preview болон raster-д хуваалцана).
class EbarimtReceiptLayout {
  EbarimtReceiptLayout._();

  static String money2(double v) => v.toStringAsFixed(2);
  static String money0(double v) => v.toStringAsFixed(0);

  /// QR-д оруулах өгөгдөл (ДДТД эсвэл POS-ийн `qrData` — одоогоор ДДТД/сугалаа).
  static String qrPayload(String lotteryOrQr) => lotteryOrQr.trim();

  static Widget headerBlock({
    required String shopName,
    required String merchantTinDisplay,
    required String dtdDisplay,
    required DateTime date,
    required TextStyle base,
    required TextStyle small,
    double iconSize = 32,
  }) {
    final dateStr = DateFormat('yyyy-MM-dd').format(date);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.receipt_long, color: Colors.blue.shade700, size: iconSize),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                shopName,
                style: base.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: base.fontSize != null ? base.fontSize! + 1 : 13,
                ),
              ),
              const SizedBox(height: 4),
              Text('ТТД: $merchantTinDisplay', style: small),
              Text('ДДТД: $dtdDisplay', style: small),
              Text('Огноо: $dateStr', style: small),
            ],
          ),
        ),
      ],
    );
  }

  static Widget itemsTable({
    required List<SalesItem> items,
    required TextStyle base,
    required TextStyle small,
    required TextStyle headerStyle,
  }) {
    final cartBulkEligiblePaid =
        PromotionPricingUtils.cartWideBillablePaidPiecesSum(items);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            SizedBox(
              width: 18,
              child: Text('\u2116',
                  style: headerStyle, textAlign: TextAlign.center),
            ),
            Expanded(child: Text('Бараа', style: headerStyle)),
            SizedBox(
              width: 26,
              child:
                  Text('т/ш', style: headerStyle, textAlign: TextAlign.right),
            ),
            SizedBox(
              width: 44,
              child:
                  Text('үнэ', style: headerStyle, textAlign: TextAlign.right),
            ),
            SizedBox(
              width: 48,
              child:
                  Text('Дүн', style: headerStyle, textAlign: TextAlign.right),
            ),
          ],
        ),
        const SizedBox(height: 4),
        for (var i = 0; i < items.length; i++) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 18,
                child: Text(
                  '${i + 1}',
                  style: small,
                  textAlign: TextAlign.center,
                ),
              ),
              Expanded(
                child: Text(
                  items[i].productName,
                  style: base.copyWith(fontWeight: FontWeight.w600),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(
                width: 26,
                child: Text(
                  '${items[i].paidQuantity}',
                  style: small,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 44,
                child: Text(
                  money0(
                    PromotionPricingUtils.discountedUnitPrice(
                      unitPrice: items[i].receiptUnitGross,
                      cartBulkMultiplier:
                          PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
                        item: items[i],
                        eligiblePaidPiecesTotal: cartBulkEligiblePaid,
                      ),
                    ),
                  ),
                  style: small,
                  textAlign: TextAlign.right,
                ),
              ),
              SizedBox(
                width: 48,
                child: Text(
                  money0(
                    PromotionPricingUtils.lineTotalFromDiscountedUnit(
                      unitPrice: items[i].receiptUnitGross,
                      cartBulkMultiplier:
                          PromotionPricingUtils.cartBulkPriceMultiplierForCartLine(
                        item: items[i],
                        eligiblePaidPiecesTotal: cartBulkEligiblePaid,
                      ),
                      paidPieces: items[i].paidQuantity,
                    ),
                  ),
                  style: small,
                  textAlign: TextAlign.right,
                ),
              ),
            ],
          ),
          if (items[i].freeQuantity > 0) ...[
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Text(
                '+${items[i].freeQuantity} үнэгүй',
                style: small.copyWith(color: Colors.black54, fontSize: 9),
              ),
            ),
          ],
          const SizedBox(height: 6),
        ],
      ],
    );
  }

  /// Summary: net, VAT, NHAT (0), gross (Бүгд үнэ).
  static Widget totalsBlock({
    required double grossTotal,
    required TextStyle base,
    required TextStyle small,
  }) {
    final vatBr = ReceiptVatFromGross.fromGrossTotal(grossTotal);
    const nhhat = 0.0;
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Нийт үнэ:',
                style: base.copyWith(fontWeight: FontWeight.w700)),
            Text(money2(vatBr.netAmount), style: base),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('\u041d\u04e8\u0410\u0422:', style: small),
            Text(money2(vatBr.vatAmount), style: small),
          ],
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('НХАТ:', style: small),
            Text(money2(nhhat), style: small),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Бүгд үнэ:',
              style: base.copyWith(fontWeight: FontWeight.w800),
            ),
            Text(
              money2(grossTotal),
              style: base.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ],
    );
  }

  static Widget qrBlock({
    required String data,
    double size = 128,
  }) {
    if (data.isEmpty) return const SizedBox.shrink();
    return Column(
      children: [
        Center(
          child: QrImageView(
            data: data,
            version: QrVersions.auto,
            size: size,
            gapless: true,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  /// ДДТД доор Code128 (өргөн хязгаарт тааруулна).
  static Widget barcodeBlock(String dtd, {double maxWidth = 260}) {
    final s = dtd.trim();
    if (s.isEmpty) return const SizedBox.shrink();
    final code128Data = s.replaceAll(RegExp(r'[^0-9A-Za-z]'), '');
    final encodable = code128Data.length >= 4
        ? code128Data
        : '${code128Data}0000'.substring(0, 4);
    return Column(
      children: [
        if (code128Data.isNotEmpty)
          Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: BarcodeWidget(
                barcode: Barcode.code128(),
                data: encodable,
                drawText: false,
                color: Colors.black,
                backgroundColor: Colors.white,
                height: 48,
              ),
            ),
          ),
        const SizedBox(height: 4),
        Text(
          s,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            letterSpacing: 0.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
