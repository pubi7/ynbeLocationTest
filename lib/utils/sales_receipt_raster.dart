import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:screenshot/screenshot.dart';

import '../models/sales_item_model.dart';
import '../widgets/sales_entry/ebarimt_receipt_layout.dart';

/// 58mm термаль — ихэнх принтер 384 px өргөн (203 DPI).
const int kThermalReceiptWidthPx = 384;

/// Монгол/кирилл текстийг системийн фонтоор widget-д зураад PNG болгон барьж авна.
class SalesReceiptRaster {
  SalesReceiptRaster._();

  static const double _pixelRatio = 2;

  /// PNG (alpha + RGB). Өргөн ойролцоогоор [kThermalReceiptWidthPx].
  static Future<Uint8List> capturePng({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    required double totalAmount,
    required DateTime now,
    String? notes,
    String? salesperson,
    required bool isOrganization,
    String? organizationName,
    String? organizationRegister,
    String? merchantTin,
    String? serverShopRegistration,
    String? lotteryNumber,
    String? qrDataFromServer,
    bool includeQr = true,
    BuildContext? themeContext,
  }) async {
    final logicalW = kThermalReceiptWidthPx / _pixelRatio;
    final ctrl = ScreenshotController();

    final content = SizedBox(
      width: logicalW,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: _ReceiptBody(
          items: items,
          shopName: shopName,
          paymentMethod: paymentMethod,
          totalAmount: totalAmount,
          now: now,
          notes: notes,
          salesperson: salesperson,
          isOrganization: isOrganization,
          organizationName: organizationName,
          organizationRegister: organizationRegister,
          merchantTin: merchantTin,
          serverShopRegistration: serverShopRegistration,
          lotteryNumber: lotteryNumber,
          qrDataFromServer: qrDataFromServer,
          includeQr: includeQr && !isOrganization,
        ),
      ),
    );

    final dpr = themeContext != null
        ? MediaQuery.devicePixelRatioOf(themeContext)
        : _pixelRatio;
    final textScaler = themeContext != null
        ? MediaQuery.textScalerOf(themeContext)
        : TextScaler.noScaling;

    Widget root = Material(color: Colors.white, child: content);
    if (themeContext != null) {
      root = InheritedTheme.captureAll(themeContext, root);
    }
    root = MediaQuery(
      data: MediaQueryData(
        size: Size(logicalW, 100000),
        devicePixelRatio: dpr,
        textScaler: textScaler,
        padding: EdgeInsets.zero,
        viewPadding: EdgeInsets.zero,
        viewInsets: EdgeInsets.zero,
      ),
      child: root,
    );

    return ctrl.captureFromLongWidget(
      root,
      pixelRatio: _pixelRatio,
      delay: const Duration(milliseconds: 250),
      context: null,
      constraints: BoxConstraints(maxWidth: logicalW),
    );
  }
}

class _ReceiptBody extends StatelessWidget {
  const _ReceiptBody({
    required this.items,
    required this.shopName,
    required this.paymentMethod,
    required this.totalAmount,
    required this.now,
    this.notes,
    this.salesperson,
    required this.isOrganization,
    this.organizationName,
    this.organizationRegister,
    this.merchantTin,
    this.serverShopRegistration,
    this.lotteryNumber,
    this.qrDataFromServer,
    required this.includeQr,
  });

  final List<SalesItem> items;
  final String shopName;
  final String paymentMethod;
  final double totalAmount;
  final DateTime now;
  final String? notes;
  final String? salesperson;
  final bool isOrganization;
  final String? organizationName;
  final String? organizationRegister;
  final String? merchantTin;
  final String? serverShopRegistration;
  final String? lotteryNumber;
  final String? qrDataFromServer;
  final bool includeQr;

  TextStyle get _base => const TextStyle(
        fontSize: 12,
        color: Colors.black,
        height: 1.25,
      );

  @override
  Widget build(BuildContext context) {
    final org = organizationRegister;
    final orgName = organizationName?.trim() ?? '';
    final sp = salesperson;
    final lot = lotteryNumber?.trim() ?? '';
    final small = _base.copyWith(fontSize: 10, color: Colors.black87);
    final headerStyle = _base.copyWith(
      fontSize: 9,
      fontWeight: FontWeight.w800,
      color: Colors.black,
    );
    final line = Text('─' * 18, style: small.copyWith(letterSpacing: 0));

    final tin = (merchantTin != null && merchantTin!.trim().isNotEmpty)
        ? merchantTin!.trim()
        : (serverShopRegistration != null &&
                serverShopRegistration!.trim().isNotEmpty)
            ? serverShopRegistration!.trim()
            : '—';
    final dtd = lot.isNotEmpty ? lot : '—';
    final qrPayload =
        (qrDataFromServer != null && qrDataFromServer!.trim().isNotEmpty)
            ? qrDataFromServer!.trim()
            : EbarimtReceiptLayout.qrPayload(lot);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        EbarimtReceiptLayout.headerBlock(
          shopName: shopName,
          merchantTinDisplay: tin,
          dtdDisplay: dtd,
          date: now,
          base: _base,
          small: small,
          iconSize: 26,
        ),
        const SizedBox(height: 8),
        line,
        const SizedBox(height: 6),
        EbarimtReceiptLayout.itemsTable(
          items: items,
          base: _base,
          small: small,
          headerStyle: headerStyle,
        ),
        line,
        const SizedBox(height: 6),
        EbarimtReceiptLayout.totalsBlock(
          grossTotal: totalAmount,
          base: _base,
          small: small,
        ),
        const SizedBox(height: 8),
        line,
        const SizedBox(height: 6),
        Text('Төлбөр: $paymentMethod', style: _base),
        Text(
          isOrganization ? 'Төрөл: Байгуулга' : 'Төрөл: Хувь хүн',
          style: _base,
        ),
        if (isOrganization && orgName.isNotEmpty)
          Text(
            'Байгууллага: $orgName',
            style: _base.copyWith(fontWeight: FontWeight.w800),
          ),
        if (isOrganization && (org != null && org.isNotEmpty))
          Text(
            'Худалдан авагчийн регистр: $org',
            style: _base.copyWith(fontWeight: FontWeight.w700),
          ),
        if (sp != null && sp.isNotEmpty) Text('Худалдагч: $sp', style: _base),
        if (notes != null && notes!.isNotEmpty)
          Text('Тэмдэглэл: $notes', style: small),
        Text(
          'Хэвлэсэн: ${now.toString().split('.')[0]}',
          style: small,
        ),
        const SizedBox(height: 8),
        if (!isOrganization && lot.isNotEmpty) ...[
          if (includeQr) ...[
            EbarimtReceiptLayout.qrBlock(data: qrPayload, size: 128),
          ],
          EbarimtReceiptLayout.barcodeBlock(lot, maxWidth: 172),
          if (!includeQr)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                '(QR дэмжихгүй)',
                textAlign: TextAlign.center,
                style: small.copyWith(fontSize: 10),
              ),
            ),
        ],
        const SizedBox(height: 12),
        Text(
          'Баярлалаа!',
          textAlign: TextAlign.center,
          style: _base.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
