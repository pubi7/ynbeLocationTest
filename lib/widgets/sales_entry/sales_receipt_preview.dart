import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../models/sales_item_model.dart';
import 'ebarimt_receipt_layout.dart';

/// И-баримтын дэлгэцийн загвар (58mm орчим өргөн).
class SalesReceiptPreview extends StatelessWidget {
  const SalesReceiptPreview({
    super.key,
    required this.items,
    required this.shopName,
    required this.paymentMethod,
    required this.customerType,
    this.notes,
    this.salesperson,
    this.organizationRegister,
    this.serverShopRegistration,

    /// Худалдагч талын ТТД (дэлгүүр / серверийн регистр).
    this.merchantTin,
    this.lotteryFromServer = false,
    this.lotteryPendingFromServer = false,
    required this.lotteryNumber,

    /// POS-оос ирсэн `qrData` байвал QR-д энэ байна; эсвэл [lotteryNumber].
    this.qrDataFromServer,
    required this.previewTime,
  });

  final List<SalesItem> items;
  final String shopName;
  final String paymentMethod;
  final String customerType;
  final String? notes;
  final String? salesperson;
  final String? organizationRegister;
  final String? serverShopRegistration;
  final String? merchantTin;
  final bool lotteryFromServer;
  final bool lotteryPendingFromServer;
  final String lotteryNumber;
  final String? qrDataFromServer;
  final DateTime previewTime;

  static const String _line = '--------------------------------';

  @override
  Widget build(BuildContext context) {
    final total = items.fold(0.0, (s, i) => s + i.receiptLineGross);
    final isOrg = customerType == 'Байгуулга';
    final mono = TextStyle(
      fontSize: 11,
      height: 1.35,
      fontFamily: 'monospace',
      color: Colors.grey.shade900,
    );
    final small = mono.copyWith(fontSize: 10);
    final headerStyle = mono.copyWith(
      fontWeight: FontWeight.w800,
      fontSize: 9,
    );

    final tin = (merchantTin != null && merchantTin!.trim().isNotEmpty)
        ? merchantTin!.trim()
        : (serverShopRegistration != null &&
                serverShopRegistration!.trim().isNotEmpty)
            ? serverShopRegistration!.trim()
            : '—';
    final dtd = lotteryNumber.trim().isNotEmpty ? lotteryNumber.trim() : '—';
    final qrPayload =
        (qrDataFromServer != null && qrDataFromServer!.trim().isNotEmpty)
            ? qrDataFromServer!.trim()
            : EbarimtReceiptLayout.qrPayload(lotteryNumber);

    return Center(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 280),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: DefaultTextStyle(
          style: mono,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EbarimtReceiptLayout.headerBlock(
                shopName: shopName,
                merchantTinDisplay: tin,
                dtdDisplay: dtd,
                date: previewTime,
                base: mono,
                small: small,
                iconSize: 28,
              ),
              const SizedBox(height: 10),
              Text(_line, style: mono),
              const SizedBox(height: 8),
              EbarimtReceiptLayout.itemsTable(
                items: items,
                base: mono,
                small: small,
                headerStyle: headerStyle,
              ),
              Text(_line, style: mono),
              const SizedBox(height: 6),
              EbarimtReceiptLayout.totalsBlock(
                grossTotal: total,
                base: mono,
                small: small,
              ),
              const SizedBox(height: 8),
              Text(_line, style: mono),
              Text('Төлбөр: $paymentMethod'),
              Text('Төрөл: $customerType'),
              if (isOrg)
                Text(
                  'Худалдан авагчийн регистр: ${organizationRegister?.trim().isNotEmpty == true ? organizationRegister! : '—'}',
                  style: mono.copyWith(fontWeight: FontWeight.w600),
                ),
              if (salesperson != null && salesperson!.trim().isNotEmpty)
                Text('Худалдагч: $salesperson'),
              if (notes != null && notes!.trim().isNotEmpty)
                Text('Тэмдэглэл: $notes'),
              Text(
                'Хэвлэсэн: ${DateFormat('yyyy-MM-dd HH:mm:ss').format(previewTime)}',
                style: small,
              ),
              if (!isOrg) ...[
                const SizedBox(height: 10),
                if (lotteryPendingFromServer)
                  Text(
                    'ДДТД / QR: «Хэвлэх» дармагц сервер / POS-оос авагдана.',
                    style: mono.copyWith(
                      fontWeight: FontWeight.bold,
                      fontStyle: FontStyle.italic,
                      color: Colors.grey.shade700,
                    ),
                  )
                else if (lotteryNumber.trim().isEmpty)
                  Text(
                    'ДДТД: POS/eBarimt-аас ирээгүй (B2B эсвэл бүртгэл хүлээгдэж байна).',
                    style: mono.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade700,
                    ),
                  )
                else ...[
                  if (lotteryFromServer)
                    Text(
                      'ДДТД (сервер / POS): $lotteryNumber',
                      style: mono.copyWith(fontWeight: FontWeight.bold),
                    ),
                  const SizedBox(height: 8),
                  EbarimtReceiptLayout.qrBlock(
                    data: qrPayload,
                    size: 112,
                  ),
                  EbarimtReceiptLayout.barcodeBlock(lotteryNumber.trim()),
                ],
              ],
              const SizedBox(height: 8),
              Text(
                'Баярлалаа!',
                textAlign: TextAlign.center,
                style: mono.copyWith(fontWeight: FontWeight.w500),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
