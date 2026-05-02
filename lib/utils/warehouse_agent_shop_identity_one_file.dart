/// **Ажилтан (agent / profile)** болон **дэлгүүр (customer / shop)**-ийг серверийн
/// өгөгдлөөс ялгах, `SharedPreferences`-д `agent_id` хадгалах, сагсан дахь дэлгүүр
/// олох дүрмүүдийг **нэг газар** төвлөрүүлсэн.
///
/// Backend-тай ажиллах **үндсэн загварууд** (том системд ихэвчлэн хослуулна):
///
/// 1. **Endpoint** — жишээ `GET /customers`, `GET /employees` (энгийн нэг дуудлага жижиг өгөгдөлд).
/// 2. **Pagination** — `?page=1&limit=20` гэх мэт давтан татах (**production** — энэ файлыг
///    `warehouseShopExtractMapsForCompute` нь хуудас бүрийн жагсаалтаар дуудагдана).
/// 3. **Role / filter** — жишээ `GET /users?role=employee` эсвэл query-д `forAllAgents` гэх мэт
///    (зөвхөн шаардлагатай дэд олонлог).
/// 4. **Real-time** — Firestore listener / WebSocket (энэ төсөлд байхгүй; шаардлагатай бол тусад нь).
///
/// **Анхаар:** бүх бүртгэлийг нэг response-д татах нь ихэнхдээ performance/API хязгаарт таарахгүй.
///
/// HTTP/Dio: [WarehouseWebBridge] (`lib/services/warehouse_web_bridge.dart`).

import 'package:flutter/foundation.dart';

import '../models/shop_model.dart';

// ---------------------------------------------------------------------------
// Isolate: [compute] зөвхөн top-level эсвэл static дамжуулалтанд тохирно.
// ---------------------------------------------------------------------------

/// `customers` / `stores` жагсаалтыг олох — зарим хариу `{ data: { customers } }`
/// эсвэл бүхэл body map-аар ирж болно; шууд [List] ч байна.
List<dynamic> warehouseShopCoerceCustomerLikeList(dynamic raw) {
  if (raw is List) return raw;
  if (raw is! Map) return const [];
  final m = Map<String, dynamic>.from(raw);
  final customers = m['customers'];
  if (customers is List) return customers;
  final stores = m['stores'];
  if (stores is List) return stores;
  final data = m['data'];
  if (data is Map<String, dynamic>) {
    return warehouseShopCoerceCustomerLikeList(data);
  }
  if (data is Map) {
    return warehouseShopCoerceCustomerLikeList(
        Map<String, dynamic>.from(data));
  }
  if (data is List) return data;
  return const [];
}

/// Customer / store мөрийг [Shop] үүсгэхэд ашиглах талбарууд (API-ийн олон нэршил).
///
/// [raw] = жагсаалт **эсвэл** `{ customers | stores | data }` бүтэцтэй map.
List<Map<String, dynamic>> warehouseShopExtractMapsForCompute(dynamic raw) {
  if (kDebugMode) {
    debugPrint('[ShopExtract] RAW TYPE: ${raw.runtimeType}');
    if (raw is Map) {
      debugPrint('[ShopExtract] RAW keys: ${raw.keys.toList()}');
    }
  }

  final list = warehouseShopCoerceCustomerLikeList(raw);
  if (kDebugMode) {
    debugPrint('[ShopExtract] coerced list length: ${list.length}');
  }

  final out = <Map<String, dynamic>>[];

  for (final c0 in list) {
    if (c0 is! Map) continue;
    final c = c0.cast<String, dynamic>();

    final id = c['id'];
    if (id == null) continue;
    final idStr = id.toString().trim();
    if (idStr.isEmpty || idStr == 'null') continue;

    out.add({
      'id': idStr,
      'name': (c['name'] ?? '').toString(),
      'district': (c['district'] ?? '').toString(),
      'address': (c['address'] ?? '').toString(),
      'detailedAddress': (c['detailedAddress'] ?? '').toString(),
      'phoneNumber': (c['phoneNumber'] ?? '').toString(),
      'registrationNumber': (c['registrationNumber'] ??
              c['companyRegistrationNumber'] ??
              c['regNo'] ??
              c['registration_no'] ??
              c['customerRegNo'])
          ?.toString(),
      'customerTypeId': (c['customerTypeId'] is num)
          ? (c['customerTypeId'] as num).toInt()
          : int.tryParse((c['customerTypeId'] ?? '').toString()),
      'maxPurchaseAmount': (c['maxPurchaseAmount'] ??
              c['purchaseLimit'] ??
              c['maxOrderAmount'] ??
              c['creditLimit'])
          ?.toString(),
      'locationLatitude': (c['locationLatitude'] is num)
          ? (c['locationLatitude'] as num).toDouble()
          : null,
      'locationLongitude': (c['locationLongitude'] is num)
          ? (c['locationLongitude'] as num).toDouble()
          : null,
    });
  }

  return out;
}

/// Ажилтан + дэлгүүр таних нэгдсэн API.
class WarehouseAgentShopIdentity {
  WarehouseAgentShopIdentity._();

  /// [SharedPreferences] түлхүүр — байршил / захиалгын эзэн зэрэгт ашиглана.
  static const String prefsAgentIdKey = 'agent_id';

  /// `GET customers` — борлуулалтад **бүх дэлгүүр** (ажилтан тус бүрт бүртгэлгүй ч).
  ///
  /// Backend нь энд `forAllAgents` / `includeAllCustomers`-ийг уншиж agent-scope шүүлтийг
  /// унтрааж болно; эсвэл **role/query**-г өөр endpoint (`/employees`, `/users?role=`) дээр
  /// шийдэж болно. Танихгүй query түлхүүрийг сервер үл тоомсорлож болно.
  static Map<String, dynamic> customersListQueryForAllAgents({
    required int page,
    required int limit,
  }) {
    return <String, dynamic>{
      'limit': limit,
      'page': page,
      'allShops': 'true',
      'forAllAgents': 'true',
      'includeAllCustomers': 'true',
    };
  }

  /// `pagination` map-аас нийт customer тоо (хуудаслалт дууссан эсэхийг шалгахад).
  static int? customersTotalHintFromPagination(
      Map<String, dynamic> pagination) {
    for (final k in ['total', 'totalCount', 'totalItems', 'count', 'rowCount']) {
      final v = pagination[k];
      if (v is num) {
        final i = v.toInt();
        if (i >= 0) return i;
      }
      final s = v?.toString().trim();
      if (s == null || s.isEmpty) continue;
      final i = int.tryParse(s);
      if (i != null && i >= 0) return i;
    }
    return null;
  }

  /// `data` (unwrap хариу) — `pagination` эсвэл үндсэн түвшний `total` / `totalCount`.
  static int? customersTotalHintFromListData(Map<String, dynamic> data) {
    final pag = data['pagination'];
    if (pag is Map) {
      final h = customersTotalHintFromPagination(
        Map<String, dynamic>.from(pag),
      );
      if (h != null) return h;
    }
    for (final k in ['total', 'totalCount', 'totalItems']) {
      final v = data[k];
      if (v is num) {
        final i = v.toInt();
        if (i >= 0) return i;
      }
      final i = int.tryParse((v ?? '').toString().trim());
      if (i != null && i >= 0) return i;
    }
    return null;
  }

  static Map<String, dynamic>? mapFromDynamic(dynamic v) {
    if (v == null) return null;
    if (v is Map<String, dynamic>) return v;
    if (v is Map) {
      return v.map((k, val) => MapEntry(k.toString(), val));
    }
    return null;
  }

  static int? _coercePositiveInt(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString().trim());
  }

  /// `auth/agent-login`-ийн **unwrap data** — `data.agent` доторх Weve ажилтан.
  static int? parseAgentIdFromAgentLoginAgent(Map<String, dynamic> agent) {
    return _coercePositiveInt(agent['id']);
  }

  /// `auth/profile` дээрх user/employee — олон backend дээр `id` = **хэрэглэгчийн** ID;
  /// борлуулагчийн тоон ID зөвхөн `agentId` / `salesAgentId` эсвэл nested `agent`.
  static int? parseAgentIdFromProfileOrUserMap(Map<String, dynamic> m) {
    final explicit = _coercePositiveInt(m['agentId']) ??
        _coercePositiveInt(m['salesAgentId']);
    if (explicit != null) return explicit;
    final nested = mapFromDynamic(m['agent']);
    if (nested != null) {
      return parseAgentIdFromAgentLoginAgent(nested);
    }
    return null;
  }

  /// `auth/agent-login`-ийн шууд буцаасан **agent** map: энд `id` нь ажилтны ID.
  static int? parseAgentIdFromEmbeddedLoginPersonMap(
      Map<String, dynamic> m) {
    return _coercePositiveInt(m['agentId']) ?? _coercePositiveInt(m['id']);
  }

  /// Agent-login payload: `data.agent` эсвэл `data.user`.
  static Map<String, dynamic>? personFromAgentLoginData(
      Map<String, dynamic> unwrapped) {
    return mapFromDynamic(unwrapped['agent']) ??
        mapFromDynamic(unwrapped['user']);
  }

  /// [warehouseShopExtractMapsForCompute]-ийн нэг мөр → [Shop].
  static Shop shopFromExtractedCustomerRow(Map<String, dynamic> s) {
    final idStr = (s['id'] ?? '').toString().trim();
    if (idStr.isEmpty || idStr == 'null') {
      throw StateError('shopFromExtractedCustomerRow: хоосон эсвэл буруу id');
    }
    final name = (s['name'] ?? 'N/A').toString();
    final district = (s['district'] ?? '').toString().trim();
    final address = (s['address'] ?? '').toString().trim();
    final detailedAddress = (s['detailedAddress'] ?? '').toString().trim();
    final fullAddress = [district, address, detailedAddress]
        .where((x) => x.trim().isNotEmpty)
        .join(', ');
    final maxPurchaseAmount =
        double.tryParse((s['maxPurchaseAmount'] ?? '').toString());
    final ct = s['customerTypeId'];
    final customerTypeId = ct is int
        ? ct
        : (ct is num ? ct.toInt() : int.tryParse((ct ?? '').toString()));

    return Shop(
      id: idStr,
      name: name,
      address: fullAddress.isEmpty ? 'N/A' : fullAddress,
      latitude: (s['locationLatitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (s['locationLongitude'] as num?)?.toDouble() ?? 0.0,
      phone: (s['phoneNumber'] ?? '').toString(),
      email: null,
      registrationNumber: s['registrationNumber']?.toString(),
      maxPurchaseAmount: maxPurchaseAmount,
      customerTypeId: customerTypeId,
      status: 'active',
      orders: const [],
      sales: const [],
      lastVisit: DateTime.now(),
    );
  }

  /// Дэлгүүрийг нэрээр олох (trim + case + contains fallback) — [ShopProvider]-тай ижил.
  static Shop? findShopByDisplayName(Iterable<Shop> shops, String name) {
    final q = name.trim().toLowerCase();
    if (q.isEmpty) return null;
    for (final s in shops) {
      if (s.name.trim().toLowerCase() == q) return s;
    }
    for (final s in shops) {
      final sn = s.name.trim().toLowerCase();
      if (sn.isEmpty) continue;
      if (sn.contains(q) || q.contains(sn)) return s;
    }
    return null;
  }
}
