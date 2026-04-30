import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import '../config/api_config.dart';

/// Байгууллагын мэдээлэл — **шууд opendatalab.mn биш**, backend proxy дамжуулна.
///
/// Хүлээгдэх endpoint: `GET {backendServerUrl}/api/opendatalab/organization/:reg`
/// (жишээ нь энэ төслийн `server.js`). Ингэснээр CORS, public API дутмаг зэргийг сервер шийднэ.
class OpendatalabService {
  static final OpendatalabService _instance = OpendatalabService._internal();
  factory OpendatalabService() => _instance;
  OpendatalabService._internal();

  /// [registrationNumber] — бүртгэлийн дугаар (зай, зураас автоматаар хасагдана).
  ///
  /// Амжилттай: `name`, `type`, `registrationNumber`, `address`, `phone`, `email`.
  /// Алдаа: `error` + `message`. Олдохгүй: `null`.
  Future<Map<String, dynamic>?> searchOrganization(
    String registrationNumber,
  ) async {
    final clean = registrationNumber.replaceAll(RegExp(r'[\s\-]'), '').trim();
    if (clean.isEmpty) {
      return null;
    }

    final base = ApiConfig.backendServerUrl.trim();
    if (base.isEmpty || !ApiConfig.isBackendServerEnabled) {
      return {
        'error': 'no_backend',
        'message':
            'Backend хаяг тохируулагдаагүй. Тохиргоонд warehouse/proxy URL оруулна уу.',
      };
    }

    final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    final uri = '$root/api/opendatalab/organization/$clean';

    if (kDebugMode) {
      debugPrint('[OpendatalabService] GET $uri');
    }

    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        headers: const {
          'Accept': 'application/json',
        },
      ),
    );

    try {
      final response = await dio.get<Map<String, dynamic>>(uri);

      if (response.statusCode == 200 && response.data != null) {
        final raw = response.data!;
        if (raw['error'] == true) {
          return {
            'error': 'api',
            'message': raw['message']?.toString() ?? 'Backend-аас алдаа ирлээ.',
          };
        }
        final mapped = _mapToAppFormat(raw, clean);
        if (mapped != null) {
          return mapped;
        }
        return null;
      }

      return null;
    } on DioException catch (e) {
      if (kDebugMode) {
        debugPrint('[OpendatalabService] DioException: ${e.type} ${e.message}');
      }

      final status = e.response?.statusCode;
      final body = e.response?.data;

      if (status == 404) {
        String? msg;
        if (body is Map && body['message'] != null) {
          msg = body['message'].toString();
        }
        return {
          'error': 'not_found',
          'message': msg ??
              'Бүртгэл олдсонгүй эсвэл backend дээр opendatalab proxy байхгүй байж магадгүй.',
        };
      }

      if (e.type == DioExceptionType.connectionTimeout ||
          e.type == DioExceptionType.receiveTimeout ||
          e.type == DioExceptionType.connectionError) {
        return {
          'error': 'network',
          'message':
              'Серверт холбогдож чадсангүй. Сүлжээ, backend асаалт шалгана уу.',
        };
      }

      if (body is Map && body['message'] != null) {
        return {
          'error': 'api',
          'message': body['message'].toString(),
        };
      }

      return {
        'error': 'unknown',
        'message': 'Алдаа гарлаа (${status ?? e.type}). Гараар оруулж болно.',
      };
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[OpendatalabService] $e');
      }
      return {
        'error': 'unknown',
        'message': 'Алдаа гарлаа. Гараар мэдээлэл оруулж болно.',
      };
    }
  }

  static Map<String, dynamic>? _mapToAppFormat(
    Map<String, dynamic> data,
    String fallbackReg,
  ) {
    dynamic nested = data['data'];
    Map<String, dynamic> m = data;
    if (nested is Map<String, dynamic>) {
      m = nested;
    } else if (data['success'] == true && nested is List && nested.isNotEmpty) {
      final first = nested.first;
      if (first is Map<String, dynamic>) {
        m = first;
      }
    }

    final organizationName = m['name'] ??
        m['organizationName'] ??
        m['companyName'] ??
        m['orgName'] ??
        m['businessName'] ??
        m['title'] ??
        m['company_name'] ??
        m['org_name'] ??
        m['legal_name'] ??
        m['legalName'] ??
        m['entity_name'] ??
        m['entityName'] ??
        m['companyNameMn'] ??
        m['companyNameEn'];

    if (organizationName == null ||
        organizationName.toString().trim().isEmpty) {
      return null;
    }

    final organizationType = m['type'] ??
        m['organizationType'] ??
        m['businessType'] ??
        m['category'] ??
        m['orgType'] ??
        m['company_type'] ??
        m['entity_type'] ??
        '';

    String typeDisplay = '';
    final ot = organizationType.toString().toLowerCase();
    if (ot.contains('shop') || ot.contains('store') || ot.contains('дэлгүүр')) {
      typeDisplay = 'Дэлгүүр';
    } else if (organizationType.toString().trim().isNotEmpty) {
      typeDisplay = organizationType.toString().trim();
    } else {
      final nameLower = organizationName.toString().toLowerCase();
      if (nameLower.contains('дэлгүүр') ||
          nameLower.contains('shop') ||
          nameLower.contains('store')) {
        typeDisplay = 'Дэлгүүр';
      } else {
        typeDisplay = 'Байгууллага';
      }
    }

    return {
      'name': organizationName.toString().trim(),
      'type': typeDisplay,
      'registrationNumber': m['regNo'] ??
          m['regno'] ??
          m['registrationNumber'] ??
          m['regNumber'] ??
          m['reg_no'] ??
          m['reg_number'] ??
          m['registration_number'] ??
          m['tin'] ??
          fallbackReg,
      'address': m['address'] ??
          m['location'] ??
          m['fullAddress'] ??
          m['registeredAddress'] ??
          m['registered_address'] ??
          m['address_full'] ??
          m['legal_address'] ??
          m['legalAddress'] ??
          '',
      'phone': m['phone'] ??
          m['phoneNumber'] ??
          m['contactPhone'] ??
          m['tel'] ??
          m['phone_number'] ??
          m['telephone'] ??
          m['contact_phone'] ??
          '',
      'email': m['email'] ??
          m['emailAddress'] ??
          m['contactEmail'] ??
          m['email_address'] ??
          m['contact_email'] ??
          '',
    };
  }
}
