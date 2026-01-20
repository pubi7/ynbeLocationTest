import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import '../config/api_config.dart';
import 'receipt_queue_service.dart';

/// Ebarimt 3.0 API Service
/// 
/// ⚠️ Шууд Ebarimt API-г дуудах боломжгүй
/// Backend middleware заавал шаардлагатай:
/// Flutter → Backend Middleware → Ebarimt 3.0 Server
class EbarimtApiService {
  /// Backend middleware URL
  String get _backendUrl {
    return '${ApiConfig.backendServerUrl}/api/ebarimt';
  }

  /// Баримт илгээх (Backend middleware-р дамжуулан)
  /// 
  /// ⚠️ Шууд Ebarimt API-г дуудахгүй, backend middleware ашиглана
  Future<EbarimtResponse> submitReceipt(QueuedReceipt receipt) async {
    try {
      final url = Uri.parse('$_backendUrl/receipt');
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: jsonEncode(receipt.toJson()),
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          throw Exception('Backend серверт холбогдож чадсангүй (timeout)');
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return EbarimtResponse(
          success: true,
          receiptId: data['receiptId'],
          message: data['message'] ?? 'Баримт амжилттай илгээгдлээ',
        );
      } else {
        final errorData = jsonDecode(response.body);
        return EbarimtResponse(
          success: false,
          message: errorData['message'] ?? 'Баримт илгээхэд алдаа гарлаа',
          errorCode: errorData['errorCode'],
        );
      }
    } catch (e) {
      debugPrint('❌ Ebarimt API алдаа: $e');
      return EbarimtResponse(
        success: false,
        message: 'Backend серверт холбогдож чадсангүй: $e',
      );
    }
  }

  /// Баримт статус шалгах
  Future<EbarimtResponse> checkReceiptStatus(String receiptId) async {
    try {
      final url = Uri.parse('$_backendUrl/receipt/$receiptId/status');
      
      final response = await http.get(url).timeout(
        const Duration(seconds: 5),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return EbarimtResponse(
          success: true,
          receiptId: receiptId,
          message: data['status'] ?? 'Тодорхойгүй',
        );
      } else {
        return EbarimtResponse(
          success: false,
          message: 'Баримт статус шалгах алдаа',
        );
      }
    } catch (e) {
      debugPrint('❌ Receipt status check error: $e');
      return EbarimtResponse(
        success: false,
        message: 'Статус шалгах алдаа: $e',
      );
    }
  }
}

/// Ebarimt API Response
class EbarimtResponse {
  final bool success;
  final String? receiptId;
  final String message;
  final String? errorCode;

  EbarimtResponse({
    required this.success,
    this.receiptId,
    required this.message,
    this.errorCode,
  });
}



