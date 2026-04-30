import 'dart:io' show Platform;
import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/order_model.dart';

/// POS receipt helper (80mm thermal roll).
///
/// - Builds a compact receipt PDF (Mongolian text via Noto when available)
/// - eBarimt: ДДТД, сугалаа, QR (backend-ээс ирсэн qrData)
/// - Prints via `printing` plugin (Web -> browser print, Mobile -> OS print flow)
class PosReceiptService {
  static const double _fsTitle = 12;
  static const double _fsBody = 10;
  static const double _fsSmall = 9;

  static pw.TextStyle _style(
    pw.Font? font, {
    double fontSize = _fsBody,
    pw.FontWeight weight = pw.FontWeight.normal,
  }) {
    return pw.TextStyle(
      font: font,
      fontSize: fontSize,
      fontWeight: weight,
    );
  }

  /// Preview dialog-тай хэвлэх
  static Future<void> printOrderReceipt(Order order) async {
    try {
      final pdf = await _buildOrderReceiptPdf(order);
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => pdf.save(),
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[POS] printOrderReceipt error: $e');
        debugPrint('$st');
      }
      rethrow;
    }
  }

  /// Шууд принтер руу хэвлэх (desktop дээр preview-гүй, mobile дээр OS dialog)
  static Future<void> directPrintOrderReceipt(Order order) async {
    try {
      final pdf = await _buildOrderReceiptPdf(order);
      final pdfBytes = await pdf.save();

      final isDesktop = !kIsWeb &&
          (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

      if (isDesktop) {
        try {
          final printers = await Printing.listPrinters();
          if (printers.isNotEmpty) {
            debugPrint('🖨️ Шууд хэвлэж байна: ${printers.first.name}');
            await Printing.directPrintPdf(
              printer: printers.first,
              onLayout: (_) async => pdfBytes,
            );
            return;
          }
        } catch (e) {
          debugPrint('⚠️ Direct print алдаа: $e');
        }
      }

      await Printing.layoutPdf(
        onLayout: (_) async => pdfBytes,
      );
    } catch (e, st) {
      if (kDebugMode) {
        debugPrint('[POS] directPrintOrderReceipt error: $e');
        debugPrint('$st');
      }
      rethrow;
    }
  }

  static Future<pw.Document> _buildOrderReceiptPdf(Order order) async {
    pw.Font? font;
    try {
      font = await PdfGoogleFonts.notoSansRegular();
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[POS] Noto font ачаалахад алдаа (Cyrillic □□ болно): $e');
      }
    }

    final doc = pw.Document();
    final createdAt = order.orderDate;

    pw.TextStyle st(double s, {bool bold = false}) {
      return _style(
        font,
        fontSize: s,
        weight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      );
    }

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        margin: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        build: (context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Center(
                child: pw.Text(
                  'ЗАХИАЛГЫН БАРИМТ',
                  style: st(_fsTitle, bold: true),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text('Огноо: ${createdAt.toString().split(".")[0]}',
                  style: st(_fsBody)),
              pw.Text('Дэлгүүр: ${order.customerName}', style: st(_fsBody)),
              if (order.customerPhone.trim().isNotEmpty)
                pw.Text('Утас: ${order.customerPhone}', style: st(_fsBody)),
              if (order.customerAddress.trim().isNotEmpty)
                pw.Text('Хаяг: ${order.customerAddress}', style: st(_fsBody)),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text('БҮТЭЭГДЭХҮҮН', style: st(_fsBody, bold: true)),
              pw.SizedBox(height: 4),
              ...order.items.expand((it) sync* {
                yield pw.Text(it.productName, style: st(_fsBody, bold: true));
                yield pw.SizedBox(height: 2);
                yield pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        '${it.quantity} x ${it.unitPrice.toStringAsFixed(0)}',
                        style: st(_fsBody)),
                    pw.Text(
                      '${it.totalPrice.toStringAsFixed(0)} ₮',
                      style: st(_fsBody, bold: true),
                    ),
                  ],
                );
                yield pw.SizedBox(height: 4);
              }),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('НИЙТ', style: st(_fsBody, bold: true)),
                  pw.Text(
                    '${order.totalAmount.toStringAsFixed(0)} ₮',
                    style: st(_fsBody, bold: true),
                  ),
                ],
              ),
              if (order.ebarimtRegistered ||
                  order.ebarimtBillId != null ||
                  (order.ebarimtLottery != null &&
                      order.ebarimtLottery!.isNotEmpty) ||
                  (order.ebarimtQrData != null &&
                      order.ebarimtQrData!.isNotEmpty) ||
                  (order.ebarimtStatus != null &&
                      order.ebarimtStatus!.isNotEmpty)) ...[
                pw.SizedBox(height: 6),
                pw.Divider(),
                pw.Text('И-БАРИМТ', style: st(_fsBody, bold: true)),
                if (order.ebarimtStatus != null &&
                    order.ebarimtStatus!.trim().isNotEmpty)
                  pw.Text('Төлөв: ${order.ebarimtStatus}', style: st(_fsSmall)),
                if (order.ebarimtBillId != null &&
                    order.ebarimtBillId!.trim().isNotEmpty)
                  pw.Text('ДДТД: ${order.ebarimtBillId}', style: st(_fsBody)),
                if (order.ebarimtLottery != null &&
                    order.ebarimtLottery!.trim().isNotEmpty)
                  pw.Text('Сугалаа: ${order.ebarimtLottery}',
                      style: st(_fsBody)),
                if (order.ebarimtQrData != null &&
                    order.ebarimtQrData!.trim().isNotEmpty) ...[
                  pw.SizedBox(height: 8),
                  pw.Center(
                    child: pw.BarcodeWidget(
                      barcode: Barcode.qrCode(),
                      data: order.ebarimtQrData!,
                      width: 100,
                      height: 100,
                    ),
                  ),
                ],
              ],
              if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Divider(),
                pw.Text('Тэмдэглэл: ${order.notes!.trim()}',
                    style: st(_fsSmall)),
              ],
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('Баярлалаа!', style: st(_fsBody))),
            ],
          );
        },
      ),
    );

    return doc;
  }
}
