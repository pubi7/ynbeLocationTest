import 'package:flutter/foundation.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/order_model.dart';

/// POS receipt helper (80mm thermal roll).
///
/// - Builds a compact receipt PDF
/// - Prints via `printing` plugin (Web -> browser print, Mobile -> OS print flow)
class PosReceiptService {
  static Future<void> printOrderReceipt(Order order) async {
    try {
      final pdf = _buildOrderReceiptPdf(order);
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

  static pw.Document _buildOrderReceiptPdf(Order order) {
    final doc = pw.Document();
    final createdAt = order.orderDate;

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
                  style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
                ),
              ),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text('Огноо: ${createdAt.toString().split(".")[0]}'),
              pw.Text('Дэлгүүр: ${order.customerName}'),
              if (order.customerPhone.trim().isNotEmpty) pw.Text('Утас: ${order.customerPhone}'),
              if (order.customerAddress.trim().isNotEmpty) pw.Text('Хаяг: ${order.customerAddress}'),
              pw.SizedBox(height: 6),
              pw.Divider(),
              pw.Text('БҮТЭЭГДЭХҮҮН', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 6),
              ...order.items.expand((it) sync* {
                yield pw.Text(it.productName, style: pw.TextStyle(fontWeight: pw.FontWeight.bold));
                yield pw.SizedBox(height: 2);
                yield pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('${it.quantity} x ${it.unitPrice.toStringAsFixed(0)}'),
                    pw.Text('${it.totalPrice.toStringAsFixed(0)} ₮', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                );
                yield pw.SizedBox(height: 6);
              }),
              pw.Divider(),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('НИЙТ', style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold)),
                  pw.Text(
                    '${order.totalAmount.toStringAsFixed(0)} ₮',
                    style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
                  ),
                ],
              ),
              if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
                pw.SizedBox(height: 6),
                pw.Divider(),
                pw.Text('Тэмдэглэл: ${order.notes!.trim()}'),
              ],
              pw.SizedBox(height: 10),
              pw.Center(child: pw.Text('Баярлалаа!')),
            ],
          );
        },
      ),
    );

    return doc;
  }
}

