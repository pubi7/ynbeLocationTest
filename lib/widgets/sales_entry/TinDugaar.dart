/// TIN дугаар
///
/// Агуулга:
/// - TinDugaarService: API дуудлага (getTinInfo)
/// - GetTinInfoResult: API хариуны модель
/// - CustomerEbarimtInfo: Ebarimt callback-д ашиглах мэдээлэл
/// - TinDugaarInput: Байгуулгийн регистр + TIN оруулах widget
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../config/api_config.dart';
import '../../config/pos_ip.dart';
import '../../providers/warehouse_provider.dart';

const String _tokenKey = 'warehouse_token';

/// Регистрийг харьцуулахад: том, хоосон зай, зураас зэргийг хасна.
String normalizeOrgRegistration(String input) {
  var t = input.trim().toUpperCase();
  t = t.replaceAll(RegExp(r'[\s\-\._/\\]'), '');
  return t;
}

/// Серверээс ирсэн мэдээлэлтэй регистр таарч байгаа эсэх.
/// [serverShopRegistration] байвал энэ нь сонгосон дэлгүүртэй яг таарах ёстой.
/// Хоосон бол [serverKnownRegistrationKeys] (normalizeOrgRegistration хийсэн set)-д байх ёстой.
String? validateWarehouseRegistration({
  required String reg,
  String? serverShopRegistration,
  String? selectedShopName,
  Set<String>? serverKnownRegistrationKeys,
}) {
  final key = normalizeOrgRegistration(reg);
  if (key.isEmpty) return null;

  final shopReg = serverShopRegistration?.trim() ?? '';
  if (shopReg.isNotEmpty) {
    final expected = normalizeOrgRegistration(shopReg);
    if (expected.isNotEmpty && key != expected) {
      final name = (selectedShopName ?? 'энэ дэлгүүр').trim();
      return 'Оруулсан регистр сонгосон дэлгүүр ($name)-ийн серверийн бүртгэлтэй таарахгүй байна. '
          'Сервер: $shopReg';
    }
    return null;
  }

  if (serverKnownRegistrationKeys != null &&
      serverKnownRegistrationKeys.isNotEmpty) {
    if (!serverKnownRegistrationKeys.contains(key)) {
      return 'Энэ регистр серверийн харилцагчдын жагсаалтад байхгүй. '
          'Жагсаалтад байгаа байгууллагын регистр оруулна уу.';
    }
  }

  return null;
}

// =============================================================================
// 1. API SERVICE - getTinInfo дуудлага
// =============================================================================

/// TIN дугаар авах сервис (api.ebarimt.mn getTinInfo)
/// Урсгал: Гараар оруулсан регистр → API дуудах → Өгөгдөл харуулах → Хадгалах → Weve руу илгээх
class TinDugaarService {
  /// eBarimt getTinInfo endpoint.
  ///
  /// Зарим орчинд query param нь `regno` гэж явдаг (вэб талын axios), заримд нь `regNo`.
  /// Иймээс direct дуудлагад хоёуланг нь явуулж нийцтэй болгов.
  static const String _apiEbarimtUrl =
      'https://api.ebarimt.mn/api/info/check/getTinInfo';

  /// POS/eBarimt service base URL (7080 гэх мэт) — зарим орчинд getTinInfo proxy энд байдаг.
  /// Override: `--dart-define=POS_SERVICE_DOC_URL=http://43.231.115.209:7080`
  static const String _posServiceBaseUrl = PosIpConfig.docDefaultPosLocalBaseUrl;

  /// Backend proxy URL - server.js (port 3000) дээр getTinInfo байдаг
  Future<String> _getEbarimtBackendUrl() async {
    String base = ApiConfig.backendServerUrl;
    if (ApiConfig.allowWarehouseUrlOverride) {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('warehouse_api_base_url');
      if (saved != null && saved.trim().isNotEmpty) {
        var s = saved.trim();
        if (s.endsWith('/')) s = s.substring(0, s.length - 1);
        if (s.toLowerCase().endsWith('/api')) s = s.substring(0, s.length - 4);
        final uri = Uri.tryParse(s);
        if (uri != null && uri.host.isNotEmpty) {
          base = '${uri.scheme}://${uri.host}:${uri.port}';
        }
      }
    }
    if (base.isEmpty) return '';
    return '$base/api/ebarimt';
  }

  /// Регистрийн дугаараас TIN авах
  /// - Flutter Web: CORS-ын улмаас api.ebarimt.mn шууд дуудах боломжгүй → Backend proxy ашиглана
  /// - Mobile: Шууд api.ebarimt.mn → (боломжтой бол POS 7080 proxy) → backend proxy
  Future<GetTinInfoResult> getTinInfo(String regNo) async {
    if (kDebugMode) {
      debugPrint('🧾 getTinInfo(regNo=$regNo) start');
    }
    if (kIsWeb) {
      // Web дээр CORS хориглосон тул зөвхөн backend proxy ашиглах
      return _getTinInfoViaBackend(regNo);
    }
    final direct = await _getTinInfoDirect(regNo);
    if (kDebugMode) {
      debugPrint(
          '🧾 getTinInfo direct: success=${direct.success} tin=${direct.tin} msg=${direct.message}');
    }
    if (direct.success) return direct;
    final viaPos = await _getTinInfoViaPosService(regNo);
    if (kDebugMode) {
      debugPrint(
          '🧾 getTinInfo POS: success=${viaPos.success} tin=${viaPos.tin} msg=${viaPos.message}');
    }
    if (viaPos.success) return viaPos;
    return _getTinInfoViaBackend(regNo);
  }

  /// POS/eBarimt service (ихэвчлэн 7080): GET /api/ebarimt/getTinInfo?regNo={regNo}
  Future<GetTinInfoResult> _getTinInfoViaPosService(String regNo) async {
    try {
      final base = _posServiceBaseUrl.trim();
      if (base.isEmpty) {
        return GetTinInfoResult(success: false, message: 'POS base URL хоосон');
      }
      final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
      final url = Uri.parse('$root/api/ebarimt/getTinInfo').replace(
        queryParameters: {'regNo': regNo},
      );
      debugPrint('📡 getTinInfo: POS proxy $url');
      final response = await http.get(url, headers: const {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));
      if (response.statusCode == 404) {
        return GetTinInfoResult(
          success: false,
          message: 'POS (7080) дээр getTinInfo endpoint олдсонгүй',
        );
      }
      return _parseTinResponse(response.body, regNo);
    } catch (e) {
      debugPrint('❌ getTinInfo (POS) алдаа: $e');
      return GetTinInfoResult(
        success: false,
        message: 'POS (7080) серверт холбогдож чадсангүй: $e',
      );
    }
  }

  /// Backend proxy: GET /api/ebarimt/getTinInfo?regNo={regNo}
  Future<GetTinInfoResult> _getTinInfoViaBackend(String regNo) async {
    try {
      final backendUrl = await _getEbarimtBackendUrl();
      if (backendUrl.isEmpty) {
        return GetTinInfoResult(
          success: false,
          message:
              'Серверийн холболт тохируулаагүй байна. Дахин нэвтэрч оролдоно уу.',
        );
      }
      final url = Uri.parse('$backendUrl/getTinInfo').replace(
        queryParameters: {'regNo': regNo},
      );
      debugPrint('📡 getTinInfo: backend proxy $url');
      final prefs = await SharedPreferences.getInstance();
      final token = prefs.getString(_tokenKey);
      final headers = <String, String>{
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      };
      if (token != null && token.isNotEmpty) {
        headers['Authorization'] = 'Bearer $token';
      }
      final response = await http.get(url, headers: headers).timeout(
            const Duration(seconds: 15),
          );
      if (response.statusCode == 401) {
        return GetTinInfoResult(
          success: false,
          message:
              'Нэвтрэх шаардлагатай. Дахин нэвтэрч оролдоно уу.',
        );
      }
      return _parseTinResponse(response.body, regNo);
    } catch (e) {
      debugPrint('❌ getTinInfo (backend) алдаа: $e');
      return GetTinInfoResult(
        success: false,
        message: 'Backend серверт холбогдож чадсангүй: $e',
      );
    }
  }

  /// Шууд api.ebarimt.mn дуудах: GET ?regNo={regNo}
  Future<GetTinInfoResult> _getTinInfoDirect(String regNo) async {
    try {
      final url = Uri.parse(_apiEbarimtUrl).replace(
        queryParameters: {
          // compat: some servers expect `regno`
          'regno': regNo,
          'regNo': regNo,
        },
      );
      debugPrint('📡 getTinInfo: api.ebarimt.mn шууд дуудаж байна $url');
      final response = await http.get(url, headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 15));
      if (kDebugMode) {
        debugPrint(
            '📡 getTinInfo direct status=${response.statusCode} body=${response.body}');
      }
      final parsed = _parseTinResponse(response.body, regNo);
      final tin = (parsed.tin ?? '').trim();
      final name = (parsed.name ?? '').trim();
      if (tin.isNotEmpty && name.isEmpty) {
        // Fallback: getInfo?tin=... нь ихэвчлэн нэр буцаадаг.
        final infoUrl = Uri.parse('https://api.ebarimt.mn/api/info/check/getInfo')
            .replace(queryParameters: {'tin': tin});
        debugPrint('📡 getInfo(tin): api.ebarimt.mn -> $infoUrl');
        final r2 = await http.get(infoUrl, headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        }).timeout(const Duration(seconds: 15));
        if (kDebugMode) {
          debugPrint(
              '📡 getInfo direct status=${r2.statusCode} body=${r2.body}');
        }
        if (r2.statusCode >= 200 && r2.statusCode < 300) {
          try {
            final obj = jsonDecode(r2.body);
            if (obj is Map) {
              final m = Map<String, dynamic>.from(obj);
              final d = m['data'];
              Map<String, dynamic>? dm;
              if (d is Map) dm = Map<String, dynamic>.from(d);
              final n = ((dm?['name'] ??
                          dm?['companyName'] ??
                          dm?['orgName'] ??
                          dm?['organizationName'] ??
                          m['name'] ??
                          m['companyName'] ??
                          m['orgName'] ??
                          '') as Object?)
                      ?.toString()
                      .trim() ??
                  '';
              if (n.isNotEmpty) {
                return GetTinInfoResult(
                  success: true,
                  tin: tin,
                  name: n,
                  regNo: regNo,
                );
              }
            }
          } catch (_) {}
        }
      }
      return parsed;
    } catch (e) {
      debugPrint('❌ getTinInfo (direct) алдаа: $e');
      return GetTinInfoResult(
        success: false,
        message: 'api.ebarimt.mn холбогдож чадсангүй: $e',
      );
    }
  }

  GetTinInfoResult _parseTinResponse(String body, String regNo) {
    try {
      final resp = jsonDecode(body);
      if (resp == null) {
        return GetTinInfoResult(success: false, message: 'Хариу хоосон');
      }
      final data = resp is Map ? resp as Map<String, dynamic> : null;
      if (data == null) {
        return GetTinInfoResult(
            success: false, message: 'Хариу буруу бүтэцтэй');
      }

      // api.ebarimt.mn: { "msg": "Амжилттай", "status": 200, "data": 76000822749 }
      // Зарим хувилбар: { "status": "success", "data": { ... } }
      // data нь TIN дугаар шууд (тоо эсвэл string) эсвэл object байж болно.
      final statusVal = data['status'];
      final msgVal = (data['msg'] ?? data['message'])?.toString();
      final success = statusVal == 200 ||
          statusVal == 'success' ||
          statusVal == true ||
          data['success'] == true ||
          msgVal == 'Амжилттай';

      if (success) {
        String tin = '';
        String name = '';

        // 1) Backend proxy: { success: true, tin: "76000822749", name: "", regNo }
        final topTin = data['tin'] ?? data['TIN'] ?? data['tinNumber'];
        if (topTin != null && topTin.toString().trim().isNotEmpty) {
          tin = topTin.toString().trim();
          // Регистртой ижил бол ТИН биш - API буруу буцаасан
          if (tin == regNo.trim()) tin = '';
          name = (data['name'] ?? data['companyName'] ?? data['orgName'] ?? '')
              .toString();
        } else {
          // 2) api.ebarimt.mn шууд: { status: 200, data: 76000822749 }
          final dataVal = data['data'];
          if (dataVal is num || dataVal is String) {
            tin = dataVal.toString().trim();
            if (tin == regNo.trim()) tin = '';
          } else if (dataVal is Map) {
            final obj = dataVal as Map<String, dynamic>;
            // Зарим POS/proxy дээр `data: { tin: ..., name: ... }` эсвэл `data: { data: <tin> }`
            tin = (obj['tin'] ??
                    obj['TIN'] ??
                    obj['tinNumber'] ??
                    obj['taxId'] ??
                    obj['regnoTin'] ??
                    obj['data'] ??
                    '')
                .toString()
                .trim();
            if (tin == regNo.trim()) tin = '';
            name = (obj['name'] ??
                    obj['companyName'] ??
                    obj['orgName'] ??
                    obj['organizationName'] ??
                    '')
                .toString();
          }
        }

        return GetTinInfoResult(
          success: true,
          tin: tin,
          name: name,
          regNo: regNo,
          message: tin.isEmpty ? 'TIN олдсонгүй, гараар оруулна уу' : null,
        );
      }

      return GetTinInfoResult(
        success: false,
        message: msgVal ?? 'Бүртгэл олдсонгүй',
      );
    } catch (_) {
      return GetTinInfoResult(
        success: false,
        message: 'Хариу унших алдаа',
      );
    }
  }
}

// =============================================================================
// 2. MODELS
// =============================================================================

/// getTinInfo API хариу
class GetTinInfoResult {
  final bool success;
  final String? tin;
  final String? name;
  final String? regNo;
  final String? message;

  GetTinInfoResult({
    required this.success,
    this.tin,
    this.name,
    this.regNo,
    this.message,
  });
}

/// Ebarimt/хэвлэхэд ашиглах худалдан авагчийн мэдээлэл
class CustomerEbarimtInfo {
  final String customerType; // 'Хувь хүн' | 'Байгуулга'
  final String? registerNumber;
  final String? tinNumber;
  final String? companyName;

  CustomerEbarimtInfo({
    required this.customerType,
    this.registerNumber,
    this.tinNumber,
    this.companyName,
  });
}

// =============================================================================
// 3. WIDGET - Байгуулгийн регистр + TIN оруулах
// =============================================================================

/// TIN дугаар оруулах widget (регистр + Шалгах + гараар оруулах)
class TinDugaarInput extends StatefulWidget {
  final ValueChanged<CustomerEbarimtInfo?>? onChanged;

  /// Сонгосон дэлгүүрийн серверээс ирсэн регистр (байвал оруулсан регистр энэ утгатай таарах ёстой).
  final String? serverShopRegistration;
  final String? selectedShopName;

  /// Серверээс татсан харилцагчдын регистр (normalizeOrgRegistration хийсэн set).
  final Set<String>? serverKnownRegistrationKeys;

  const TinDugaarInput({
    super.key,
    this.onChanged,
    this.serverShopRegistration,
    this.selectedShopName,
    this.serverKnownRegistrationKeys,
  });

  @override
  State<TinDugaarInput> createState() => _TinDugaarInputState();
}

class _TinDugaarInputState extends State<TinDugaarInput> {
  final _orgRegisterController = TextEditingController();
  final _tinController = TextEditingController();
  String? _tinName;

  /// API-аас ирсэн бодит TIN (гараас оруулсан биш)
  String? _verifiedTinFromApi;
  bool _isCheckingTin = false;
  String? _tinError;

  @override
  void dispose() {
    _orgRegisterController.dispose();
    _tinController.dispose();
    super.dispose();
  }

  Future<void> _checkTin() async {
    final reg = _orgRegisterController.text.trim();
    if (reg.isEmpty) {
      setState(() {
        _tinError = 'Регистрийн дугаар оруулна уу';
        _tinController.clear();
      });
      return;
    }
    final whErr = validateWarehouseRegistration(
      reg: reg,
      serverShopRegistration: widget.serverShopRegistration,
      selectedShopName: widget.selectedShopName,
      serverKnownRegistrationKeys: widget.serverKnownRegistrationKeys,
    );
    if (whErr != null) {
      setState(() {
        _tinError = whErr;
        _tinController.clear();
        _verifiedTinFromApi = null;
        _notifyChanged();
      });
      return;
    }
    setState(() {
      _isCheckingTin = true;
      _tinError = null;
    });
    // Сервертэй үед: GET /api/etax/organization/:regno — Web-тай ижил (auth).
    // Зарим регистр 7 орон биш байдаг тул "цэвэрлээд" шууд туршина.
    String? etaxName;
    String? etaxTin;
    try {
      if (mounted) {
        final wh = Provider.of<WarehouseProvider>(context, listen: false);
        if (wh.connected) {
          final clean = reg.replaceAll(RegExp(r'[\s\-]'), '');
          if (clean.isNotEmpty) {
            final org = await wh.tryGetEtaxOrganization(clean);
            if (org != null) {
              // Backend (`warehouse-service-main`) response after unwrap:
              // { organization: { regno, name, ... } }
              final orgMap = (org['organization'] is Map)
                  ? Map<String, dynamic>.from(org['organization'] as Map)
                  : org;
              final n = (orgMap['name'] ??
                      orgMap['companyName'] ??
                      orgMap['orgName'] ??
                      orgMap['organizationName'] ??
                      org['name'] ??
                      org['organizationName'] ??
                      '')
                  .toString()
                  .trim();
              if (n.isNotEmpty) etaxName = n;
              final t = (orgMap['tin'] ??
                      orgMap['TIN'] ??
                      orgMap['tinNumber'] ??
                      orgMap['taxId'] ??
                      orgMap['vatNo'] ??
                      org['tin'] ??
                      org['tinNumber'] ??
                      org['ttd'] ??
                      '')
                  .toString()
                  .trim();
              if (t.isNotEmpty && t != reg.trim()) {
                etaxTin = t;
              }
            }
          }
        }
      }
    } catch (e) {
      debugPrint('ETax organization: $e');
    }

    // ETax-аас TIN олдсон бол шууд ашиглая (direct ebarimt.mn алдаа/CORS/proxy асуудлаас хамгаална).
    GetTinInfoResult result;
    if (etaxTin != null && etaxTin.isNotEmpty) {
      result = GetTinInfoResult(
        success: true,
        tin: etaxTin,
        name: etaxName,
        regNo: reg,
      );
    } else {
      result = await TinDugaarService().getTinInfo(reg);
    }
    if (!mounted) return;
    setState(() {
      _isCheckingTin = false;
      if (result.success) {
        final apiName = (result.name ?? '').trim();
        _tinName = (etaxName != null && etaxName.isNotEmpty)
            ? etaxName
            : (apiName.isNotEmpty ? apiName : null);
        final apiTin = (result.tin ?? '').trim();
        _verifiedTinFromApi = apiTin.isNotEmpty ? apiTin : null;
        _tinController.text = apiTin;
        if (apiTin.isEmpty) {
          _tinError = result.message ?? 'TIN олдсонгүй, гараар оруулна уу';
        } else {
          _tinError = null;
        }
        _notifyChanged();
      } else {
        _tinError = result.message ?? 'Бүртгэл олдсонгүй';
        _tinController.clear();
        _verifiedTinFromApi = null;
        _notifyChanged();
      }
    });
  }

  void _notifyChanged() {
    widget.onChanged?.call(getInfo());
  }

  CustomerEbarimtInfo? getInfo() {
    final reg = _orgRegisterController.text.trim();
    final tin = _tinController.text.trim();
    if (reg.isEmpty || tin.isEmpty) return null;
    final whErr = validateWarehouseRegistration(
      reg: reg,
      serverShopRegistration: widget.serverShopRegistration,
      selectedShopName: widget.selectedShopName,
      serverKnownRegistrationKeys: widget.serverKnownRegistrationKeys,
    );
    if (whErr != null) return null;
    return CustomerEbarimtInfo(
      customerType: 'Байгуулга',
      registerNumber: reg,
      tinNumber: tin,
      companyName: _tinName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasValidData = _orgRegisterController.text.trim().isNotEmpty &&
        _tinController.text.trim().isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          widget.serverShopRegistration != null &&
                  widget.serverShopRegistration!.trim().isNotEmpty
              ? '1. Регистр нь сонгосон дэлгүүрийн серверийн бүртгэлтэй таарах ёстой. Дараа нь «Шалгах» (ebarimt).'
              : (widget.serverKnownRegistrationKeys != null &&
                      widget.serverKnownRegistrationKeys!.isNotEmpty
                  ? '1. Регистр серверийн харилцагчдын жагсаалтад байх ёстой. «Шалгах» (ebarimt).'
                  : '1. Регистр оруулаад «Шалгах» дарна (api.ebarimt.mn getTinInfo).'),
          style: const TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _orgRegisterController,
          decoration: const InputDecoration(
            labelText: 'Байгуулгийн регистр',
            hintText: 'Регистрийн дугаар оруулна уу',
            border: OutlineInputBorder(),
          ),
          keyboardType: TextInputType.text,
          onChanged: (v) {
            setState(() {
              _tinError = null;
              _verifiedTinFromApi = null; // Регистр өөрчлөгдөв
              if (v.trim().isEmpty) _tinController.clear();
              _notifyChanged();
            });
          },
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _tinController,
          decoration: InputDecoration(
            labelText: 'TIN дугаар',
            hintText: 'Шалгах эсвэл гараар оруулна уу',
            border: const OutlineInputBorder(),
            suffixIcon: _tinName != null && _tinName!.isNotEmpty
                ? Tooltip(
                    message: _tinName!,
                    child: Icon(
                      Icons.check_circle,
                      color: Colors.green.shade600,
                      size: 20,
                    ),
                  )
                : null,
          ),
          keyboardType: TextInputType.number,
          onChanged: (_) {
            setState(() {
              _tinError = null;
              _verifiedTinFromApi = null; // Гараас өөрчилсөн - API-ийн утга биш
              _notifyChanged();
            });
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isCheckingTin ? null : _checkTin,
              icon: _isCheckingTin
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.search, size: 18),
              label: Text(_isCheckingTin ? 'Шалгаж байна...' : 'Шалгах'),
            ),
            const SizedBox(width: 12),
            if (_tinError != null)
              Expanded(
                child: Text(
                  _tinError!,
                  style: const TextStyle(fontSize: 12, color: Colors.red),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
          ],
        ),
        if (hasValidData) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green.shade200),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Олдсон мэдээлэл (хадгална):',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.green.shade800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Регистр: ${_orgRegisterController.text.trim()}',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                Text(
                  _verifiedTinFromApi != null
                      ? 'TIN: $_verifiedTinFromApi (API-аас)'
                      : 'TIN: ${_tinController.text.trim()} (гараас оруулсан)',
                  style: const TextStyle(
                      fontSize: 13, fontWeight: FontWeight.w500),
                ),
                if (_tinName != null && _tinName!.isNotEmpty)
                  Text('Байгууллага: $_tinName',
                      style: const TextStyle(fontSize: 12)),
                const SizedBox(height: 6),
                Text(
                  'Хэвлэх дарснаар Weve сайт руу илгээнэ',
                  style: TextStyle(fontSize: 11, color: Colors.green.shade700),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
