import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../models/sales_item_model.dart';

class PosReceiptCreateData {
  final String id;
  final String? date;
  final String? billId;
  final String? lottery;
  final String? qrData;
  final String? message;

  PosReceiptCreateData({
    required this.id,
    this.date,
    this.billId,
    this.lottery,
    this.qrData,
    this.message,
  });

  factory PosReceiptCreateData.fromJson(Map<String, dynamic> json) {
    final id = (json['id'] ?? '').toString().trim();
    if (id.isEmpty) {
      throw ArgumentError('POS receipt response missing id');
    }
    return PosReceiptCreateData(
      id: id,
      date: json['date']?.toString(),
      billId: json['billId']?.toString(),
      lottery: json['lottery']?.toString(),
      qrData: json['qrData']?.toString(),
      message: json['message']?.toString(),
    );
  }
}

class PosReceiptApiService {
  PosReceiptApiService({
    Dio? dio,
  }) : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                receiveTimeout: const Duration(seconds: 30),
                headers: const {
                  'Content-Type': 'application/json',
                  'Accept': 'application/json',
                },
              ),
            );

  final Dio _dio;

  static String normalizeBaseUrl(String baseUrl) {
    var t = baseUrl.trim();
    if (t.endsWith('/')) t = t.substring(0, t.length - 1);
    return t;
  }

  /// Build POS `/rest/receipt` payload similar to warehouse-web `createEbarimtRequest`.
  static Map<String, dynamic> buildPosReceiptPayload({
    required List<Map<String, dynamic>> items,
    required String merchantTin,
    required String type, // 'B2C_RECEIPT' | 'B2B_RECEIPT'
    required String paymentType, // 'CASH' etc
    String? customerTin,
    String? consumerNo,
    String branchNo = '001',
    String posNo = '001',
    String billIdSuffix = '01',
    String districtCode = '2501',
    double totalCityTax = 0,
  }) {
    final totalAmount = items.fold<double>(
      0,
      (sum, it) => sum + ((it['totalAmount'] as num?)?.toDouble() ?? 0),
    );
    final totalVAT = items.fold<double>(
      0,
      (sum, it) => sum + ((it['totalVAT'] as num?)?.toDouble() ?? 0),
    );
    final totalCity = totalCityTax > 0
        ? totalCityTax
        : items.fold<double>(
            0,
            (sum, it) => sum + ((it['totalCityTax'] as num?)?.toDouble() ?? 0),
          );

    // POS зарим хувилбар дээр null талбаруудыг хатуу шалгаад 400 өгөх магадлалтай.
    // Тиймээс ашиглахгүй талбаруудыг payload-оос бүр мөсөн хасна.
    final totalAmount2 = double.parse(totalAmount.toStringAsFixed(2));
    final totalVat2 = double.parse(totalVAT.toStringAsFixed(2));
    final totalCity2 = double.parse(totalCity.toStringAsFixed(2));

    final isB2B = type == 'B2B_RECEIPT';
    final cTin = (customerTin ?? '').trim();
    final cNo = (consumerNo ?? '').trim();

    final receipt = <String, dynamic>{
      'totalAmount': totalAmount2,
      'taxType': 'VAT_ABLE',
      'merchantTin': merchantTin,
      if (isB2B) 'customerTin': cTin,
      'totalVAT': totalVat2,
      'totalCityTax': totalCity2,
      'bankAccountNo': '',
      'iBan': '',
      'items': items,
    };

    return <String, dynamic>{
      'version': '3.2.44',
      'branchNo': branchNo,
      'totalAmount': totalAmount2,
      'totalVAT': totalVat2,
      'totalCityTax': totalCity2,
      'districtCode': districtCode,
      'merchantTin': merchantTin,
      'posNo': posNo,
      if (isB2B) 'customerTin': cTin,
      if (!isB2B && cNo.isNotEmpty) 'consumerNo': cNo,
      'type': type,
      'billIdSuffix': billIdSuffix,
      'receipts': [receipt],
      'payments': [
        {
          'code': paymentType,
          'status': 'PAID',
          'paidAmount': totalAmount2,
        },
      ],
    };
  }

  /// Create items array for POS payload.
  /// POS 7080 ихэнхдээ `unitPrice`-ийг НӨАТ-тай (gross) гэж үздэг.
  static Map<String, dynamic> buildPosItem({
    required String name,
    required String barCode,
    required int qty,
    required double unitPriceGross,
    String barCodeType = 'GS1',
    String measureUnit = 'u',
    String classificationCode = '2399421',
    double totalCityTax = 0,
  }) {
    final q = qty <= 0 ? 1 : qty;
    final lineGross =
        double.parse((unitPriceGross * q).toStringAsFixed(2)); // VAT included
    final lineNet = double.parse((lineGross / 1.1).toStringAsFixed(2));
    final totalVAT = double.parse((lineGross - lineNet).toStringAsFixed(2));
    final city = double.parse(totalCityTax.toStringAsFixed(2));
    final totalAmount = double.parse((lineGross + city).toStringAsFixed(2));

    return {
      'name': name,
      'barCode': barCode,
      'barCodeType': barCodeType,
      'classificationCode': classificationCode,
      'taxProductCode': null,
      'measureUnit': measureUnit,
      'qty': q,
      'unitPrice': double.parse(unitPriceGross.toStringAsFixed(2)),
      'totalVAT': totalVAT,
      'totalCityTax': city,
      'totalAmount': totalAmount,
    };
  }

  static double unitPriceGrossFromSalesItem(SalesItem it) {
    // SalesItem.price is net when unitPriceExcludesVat=true; receipt needs gross.
    if (it.unitPriceExcludesVat) return it.price * 1.1;
    return it.price;
  }

  Future<PosReceiptCreateData> createReceipt({
    required String baseUrl,
    required Map<String, dynamic> payload,
  }) async {
    final root = normalizeBaseUrl(baseUrl);
    final url = '$root/rest/receipt';
    if (kDebugMode) {
      debugPrint('[PosReceiptApi] POST $url');
    }
    final res = await _dio.post<Object?>(
      url,
      data: payload,
      options: Options(validateStatus: (c) => c != null && c >= 200 && c < 500),
    );

    final status = res.statusCode ?? 0;
    if (status < 200 || status >= 300) {
      throw Exception('POS API HTTP $status: ${res.data}');
    }

    final data = res.data;
    if (data is Map<String, dynamic>) {
      return PosReceiptCreateData.fromJson(data);
    }
    if (data is Map) {
      return PosReceiptCreateData.fromJson(Map<String, dynamic>.from(data));
    }
    throw Exception('POS API response invalid: $data');
  }
}
