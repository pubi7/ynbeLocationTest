import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:qr_flutter/qr_flutter.dart';
import '../models/sales_item_model.dart';
import '../models/user_model.dart';

class ReceiptService {
  static Future<Uint8List> _generateQrCodeImage(String data) async {
    final painter = QrPainter(
      data: data,
      version: QrVersions.auto,
      errorCorrectionLevel: QrErrorCorrectLevel.L,
      color: const Color(0xFF000000),
      emptyColor: const Color(0xFFFFFFFF),
    );

    final picRecorder = ui.PictureRecorder();
    final canvas = Canvas(picRecorder);
    const size = 200.0;
    painter.paint(canvas, const Size(size, size));

    final picture = picRecorder.endRecording();
    final image = await picture.toImage(size.toInt(), size.toInt());
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);

    return byteData!.buffer.asUint8List();
  }

  static Future<void> printReceipt({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    required String? notes,
    required User? salesperson,
  }) async {
    if (items.isEmpty) {
      throw Exception('Хамгийн багадаа нэг бараа сонгоно уу');
    }

    final totalAmount = items.fold(0.0, (sum, item) => sum + item.total);
    final now = DateTime.now();

    // QR code мэдээлэл үүсгэх (JSON формат)
    final qrData = {
      'items': items.map((item) => item.toJson()).toList(),
      'total': totalAmount,
      'paymentMethod': paymentMethod,
      'location': shopName,
      'date': now.toIso8601String(),
      'salesperson': salesperson?.name ?? '',
    };
    final qrDataString = jsonEncode(qrData);

    // QR code image үүсгэх
    final qrImageBytes = await _generateQrCodeImage(qrDataString);
    final qrImage = pw.MemoryImage(qrImageBytes);

    final pdf = pw.Document();

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.roll80,
        build: (pw.Context context) {
          return pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'БОРЛУУЛАЛТЫН БАРИМТ',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 10),
              pw.Text('Дэлгүүр: $shopName'),
              pw.SizedBox(height: 10),
              pw.Divider(),
              pw.SizedBox(height: 5),
              // Олон барааны мэдээлэл
              for (var item in items) ...[
                pw.Text('${item.productName}',
                    style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                pw.SizedBox(height: 3),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                        '${item.quantity} x ${item.price.toStringAsFixed(0)} ₮'),
                    pw.Text('${item.total.toStringAsFixed(0)} ₮',
                        style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
                  ],
                ),
                pw.SizedBox(height: 8),
              ],
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    'Нийт үнэ:',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.Text(
                    '${totalAmount.toStringAsFixed(0)} ₮',
                    style: pw.TextStyle(
                      fontSize: 14,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                ],
              ),
              pw.SizedBox(height: 10),
              if (notes != null && notes.isNotEmpty) ...[
                pw.Text('Тэмдэглэл: $notes'),
                pw.SizedBox(height: 10),
              ],
              pw.Divider(),
              pw.SizedBox(height: 5),
              pw.Text('Худалдагч: ${salesperson?.name ?? ''}'),
              pw.SizedBox(height: 5),
              pw.Text('Төлбөрийн төрөл: ${paymentMethod.toUpperCase()}'),
              pw.SizedBox(height: 5),
              pw.Text('Огноо: ${now.toString().split('.')[0]}'),
              pw.SizedBox(height: 10),
              pw.Text(
                'Баярлалаа!',
                style: pw.TextStyle(
                  fontSize: 12,
                  fontStyle: pw.FontStyle.italic,
                ),
                textAlign: pw.TextAlign.center,
              ),
              pw.SizedBox(height: 20),
              pw.Divider(),
              pw.SizedBox(height: 10),
              // QR Code
              pw.Center(
                child: pw.Column(
                  children: [
                    pw.Image(qrImage, width: 150, height: 150),
                    pw.SizedBox(height: 8),
                    pw.Text(
                      'QR Code',
                      style: pw.TextStyle(
                        fontSize: 10,
                        fontStyle: pw.FontStyle.italic,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
    );
  }
}
