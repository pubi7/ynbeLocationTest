import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'warehouse_web_bridge.dart';

/// Backend-аас **сугалааны дугаар / ДДТД** авах (mobile → warehouse → eBarimt/Pos).
///
/// - Захиалга үүсгэхийн JSON-оос талбар задлах
/// - `POST /api/ebarimt/register/:orderId` — PosAPI / ТТ-тэй ярилцахыг backend хийнэ
class SugalaaniiDugaar {
  SugalaaniiDugaar._();

  /// POST захиалга үүсгэхийн хариу — зөвхөн **fallback** (вэб шиг гол эх үүсвэр нь `ebarimt/register`).
  ///
  /// `qrData`-г сугалааны дугаар гэж үзэхгүй. Эхлээд сугалааны талбарууд, дараа нь ДДТД.
  static String? extractFromCreateOrderResponse(Map<String, dynamic> result) {
    String? fromMap(Map<String, dynamic> m) {
      const lotteryKeys = [
        'lotteryNumber',
        'lotteryNo',
        'lotteryCode',
        'lottery_code',
        'sugalaanyDugaar',
        'sugalaany_dugaar',
        'ebarimtLotteryNumber',
        'ebarimtLottery',
        'billIdPoll',
        'pollNumber',
        'lottery',
      ];
      for (final k in lotteryKeys) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      for (final k in ['billId', 'ebarimtBillId', 'ddtd', 'dtd']) {
        final v = m[k];
        if (v != null && v.toString().trim().isNotEmpty) {
          return v.toString().trim();
        }
      }
      final nested = m['ebarimt'];
      if (nested is Map) {
        return fromMap(nested.cast<String, dynamic>());
      }
      return null;
    }

    final order = result['order'];
    if (order is Map) {
      final hit = fromMap(Map<String, dynamic>.from(order));
      if (hit != null) return hit;
    }
    return fromMap(result);
  }

  /// `POST /api/ebarimt/register/:orderId`-ийн JSON хариу (backend-аас ирсэн).
  ///
  /// Ихэнх тохиолдолд сугалаа `lottery`-д ирнэ; зарим POS хувилбарт зөвхөн ДДТД
  /// (`id` / `billId`) ирж баримт/QR хэвлэхэд хангалттай.
  static String? extractFromRegisterResponse(Map<String, dynamic>? m) {
    if (m == null) return null;
    final nested = m['data'];
    if (nested is Map) {
      final inner = extractFromRegisterResponse(
        Map<String, dynamic>.from(nested),
      );
      if (inner != null) return inner;
    }
    for (final k in ['lottery', 'lotteryNumber', 'lotteryNo']) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    for (final k in ['id', 'billId', 'ebarimtBillId', 'ddtd', 'dtd']) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  /// `POST /api/ebarimt/register/:orderId`-ийн хариунаас зөвхөн **ДДТДХ / Bill ID** авах.
  ///
  /// `extractFromRegisterResponse` нь lottery-г түрүүлж авдаг тул байгуулгын баримт дээр
  /// BillId хэрэгтэй үед энэ helper-ийг ашиглана.
  static String? extractBillIdFromRegisterResponse(Map<String, dynamic>? m) {
    if (m == null) return null;
    final nested = m['data'];
    if (nested is Map) {
      final inner = extractBillIdFromRegisterResponse(
        Map<String, dynamic>.from(nested),
      );
      if (inner != null && inner.trim().isNotEmpty) return inner.trim();
    }
    for (final k in ['id', 'billId', 'ebarimtBillId', 'ddtd', 'dtd']) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  /// `POST /api/ebarimt/register/:orderId` — зөвхөн backend руу (token, merchant тэнд).
  static Future<Map<String, dynamic>?> tryEbarimtRegisterOrder(
    WarehouseWebBridge bridge,
    int orderId, {
    Map<String, dynamic>? data,
    Future<void> Function()? onUnauthorized,
  }) async {
    try {
      return await bridge.ebarimtRegisterOrder(
        orderId: orderId,
        data: data,
      );
    } catch (e) {
      if (kDebugMode) {
        if (e is DioException) {
          final code = e.response?.statusCode;
          final msg = e.response?.data?.toString();
          debugPrint(
            '[SugalaaniiDugaar] ebarimt/register/$orderId failed: HTTP $code $e\n'
            'Response: $msg',
          );
          if (code == 403) {
            debugPrint(
              '[SugalaaniiDugaar] 403: энэ хэрэглэгчийн үүрэг eBarimt register дуудах эрхгүй. '
              'Backend дээр POST /api/ebarimt/register-д зөвшөөрөгдсөн role-уудыг шалгана уу.',
            );
          }
        } else {
          debugPrint('[SugalaaniiDugaar] ebarimt/register/$orderId: $e');
        }
      }
      if (e is DioException && e.response?.statusCode == 401) {
        await onUnauthorized?.call();
      }
      return null;
    }
  }

  /// Вэб/dashboard-тай ижил: **`POST /api/ebarimt/register/:orderId`** хариу нь гол эх үүсвэр.
  ///
  /// `orderId` байвал эхлээд register дуудаж сугалаа/ДДТД авна; амжилтгүй бол л
  /// захиалга үүсгэхийн хариунаас fallback хийнэ.
  static Future<String?> resolveServerLotteryAfterOrderCreated({
    required Map<String, dynamic> createOrderResult,
    required int? orderId,
    required Future<Map<String, dynamic>?> Function(int orderId)
        tryRegisterOrder,
  }) async {
    if (orderId != null) {
      final regBody = await tryRegisterOrder(orderId);
      final fromRegister = extractFromRegisterResponse(regBody);
      if (fromRegister != null && fromRegister.isNotEmpty) {
        if (kDebugMode) {
          debugPrint(
            '   • Суглааны дугаар (backend ebarimt/register, вэбтэй ижил): $fromRegister',
          );
        }
        return fromRegister;
      }
    }

    final fallback = extractFromCreateOrderResponse(createOrderResult);
    if (kDebugMode && fallback != null) {
      debugPrint(
        '   • Суглааны дугаар (захиалгын хариу, fallback): $fallback',
      );
    }
    return fallback;
  }
}
