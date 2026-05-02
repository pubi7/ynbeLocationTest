import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../../models/order_model.dart';
import '../../providers/auth_provider.dart';
import '../../providers/order_provider.dart';
import '../../providers/warehouse_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/sugalaanii_dugaar.dart';
import '../../models/sales_item_model.dart';
import '../../utils/ebarimt_order_return.dart';
import '../../utils/order_owner_utils.dart';
import '../../utils/role_utils.dart';
import '../../utils/sales_agent_order_cancel.dart';
import '../../utils/warehouse_agent_shop_identity_one_file.dart';
import '../../widgets/go_pop_scope.dart';

class OrderDetailsScreen extends StatefulWidget {
  final String orderId;
  final Order? order;

  const OrderDetailsScreen({
    super.key,
    required this.orderId,
    this.order,
  });

  @override
  State<OrderDetailsScreen> createState() => _OrderDetailsScreenState();
}

class _OrderDetailsScreenState extends State<OrderDetailsScreen> {
  bool _busy = false;
  bool _printLocked = false;
  bool _printedLoaded = false;
  final Set<String> _printedOrderIds = <String>{};
  int? _prefsAgentId;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) {
      if (!mounted) return;
      setState(() => _prefsAgentId =
          p.getInt(WarehouseAgentShopIdentity.prefsAgentIdKey));
    });
  }

  Future<void> _loadPrintedOrders() async {
    if (_printedLoaded) return;
    _printedLoaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kPrintedEbarimtOrderIdsPrefKey);
      if (raw == null || raw.trim().isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is List) {
        _printedOrderIds
          ..clear()
          ..addAll(decoded.map((e) => e.toString()).where((s) => s.isNotEmpty));
        if (mounted) setState(() {});
      }
    } catch (_) {}
  }

  Future<void> _markOrderPrinted(String orderId) async {
    try {
      final id = orderId.trim();
      if (id.isEmpty) return;
      _printedOrderIds.add(id);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          kPrintedEbarimtOrderIdsPrefKey, jsonEncode(_printedOrderIds.toList()));
    } catch (_) {}
  }

  /// Захиалгын түвшинд: баримт / eBarimt-ийн товч төлөв.
  String _receiptStatusSummary(Order o) {
    final id = o.id.trim();
    if (o.ebarimtReturnId != null && o.ebarimtReturnId!.trim().isNotEmpty) {
      return 'Буцаагдсан';
    }
    if (o.ebarimtRegistered ||
        (o.ebarimtBillId != null && o.ebarimtBillId!.trim().isNotEmpty) ||
        (o.ebarimtLottery != null && o.ebarimtLottery!.trim().isNotEmpty) ||
        (o.ebarimtQrData != null && o.ebarimtQrData!.trim().isNotEmpty)) {
      return 'eBarimt бүртгэгдсэн';
    }
    if (_printLocked || _printedOrderIds.contains(id)) {
      return 'Гар утсаар хэвлэгдсэн';
    }
    return 'Хэвлэгдээгүй';
  }

  Future<({String? tin, String? name, String? message})> _getTinInfoDirect(
    String regNo,
  ) async {
    try {
      final clean = regNo.trim().replaceAll(RegExp(r'[\s\-\._/\\]'), '');
      if (clean.isEmpty) {
        return (tin: null, name: null, message: 'Регистр хоосон байна');
      }
      final uri = Uri.parse('https://api.ebarimt.mn/api/info/check/getTinInfo')
          .replace(queryParameters: {'regno': clean, 'regNo': clean});
      final res = await http.get(
        uri,
        headers: const {'Accept': 'application/json'},
      );
      if (res.statusCode < 200 || res.statusCode >= 300) {
        return (
          tin: null,
          name: null,
          message: 'HTTP ${res.statusCode}',
        );
      }
      final data = jsonDecode(res.body);
      if (data is! Map) {
        return (tin: null, name: null, message: 'Хариу буруу байна');
      }
      final m = Map<String, dynamic>.from(data);
      final nested = m['data'];

      String pickName(Map<String, dynamic> x) {
        return (x['name'] ??
                x['companyName'] ??
                x['orgName'] ??
                x['organizationName'] ??
                '')
            .toString()
            .trim();
      }

      String pickTin(dynamic v) {
        final t = (v ?? '').toString().trim();
        if (t == clean) return '';
        return t;
      }

      String? tin;
      String? name;
      if (nested is num || nested is String) {
        tin = pickTin(nested);
        name = null;
      } else if (nested is Map) {
        final x = Map<String, dynamic>.from(nested);
        tin = pickTin(x['tin'] ??
            x['TIN'] ??
            x['tinNumber'] ??
            x['taxId'] ??
            x['regnoTin'] ??
            x['data']);
        name = pickName(x);
      } else {
        tin = pickTin(m['tin'] ?? m['TIN'] ?? m['tinNumber']);
        name = pickName(m);
      }

      return (
        tin: tin.isNotEmpty ? tin : null,
        name: (name != null && name.isNotEmpty) ? name : null,
        message: null,
      );
    } catch (e) {
      return (tin: null, name: null, message: e.toString());
    }
  }

  Future<String?> _getInfoNameByTin(String tin) async {
    try {
      final clean = tin.trim();
      if (clean.isEmpty) return null;
      final uri = Uri.parse('https://api.ebarimt.mn/api/info/check/getInfo')
          .replace(queryParameters: {'tin': clean});
      final res = await http.get(uri, headers: const {'Accept': 'application/json'});
      if (res.statusCode < 200 || res.statusCode >= 300) return null;
      final data = jsonDecode(res.body);
      if (data is! Map) return null;
      final m = Map<String, dynamic>.from(data);
      final d = m['data'];
      if (d is Map) {
        final dm = Map<String, dynamic>.from(d);
        final n = (dm['name'] ??
                dm['companyName'] ??
                dm['orgName'] ??
                dm['organizationName'] ??
                '')
            .toString()
            .trim();
        return n.isEmpty ? null : n;
      }
      final n = (m['name'] ?? m['companyName'] ?? m['orgName'] ?? '')
          .toString()
          .trim();
      return n.isEmpty ? null : n;
    } catch (_) {
      return null;
    }
  }

  String? _extractQrData(Map<String, dynamic>? m) {
    if (m == null) return null;
    final nested = m['data'];
    if (nested is Map) {
      final inner = _extractQrData(Map<String, dynamic>.from(nested));
      if (inner != null && inner.trim().isNotEmpty) return inner.trim();
    }
    for (final k in ['qrData', 'ebarimtQrData', 'qr', 'qrcode', 'qr_code']) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) {
        return v.toString().trim();
      }
    }
    return null;
  }

  Future<String?> _pickPaymentMethod() async {
    return showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: false,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        Widget option({
          required IconData icon,
          required String title,
          required String value,
          Color? color,
        }) {
          return ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: (color ?? const Color(0xFF3B82F6)).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color ?? const Color(0xFF3B82F6)),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(ctx, value),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Төлбөрийн төрөл',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Төлбөрийн төрлөө сонгоно уу.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                option(
                  icon: Icons.payments_rounded,
                  title: 'Бэлэн',
                  value: 'Cash',
                  color: const Color(0xFF10B981),
                ),
                option(
                  icon: Icons.account_balance_rounded,
                  title: 'Банк',
                  value: 'BankTransfer',
                  color: const Color(0xFF6366F1),
                ),
                option(
                  icon: Icons.credit_card_rounded,
                  title: 'Зээл',
                  value: 'Credit',
                  color: const Color(0xFFF59E0B),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Болих'),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<({String customerType, String? register, String? orgName, String? tin})?>
      _pickCustomerType() async {
    final type = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        Widget opt({
          required IconData icon,
          required String title,
          required String value,
          required Color color,
          String? subtitle,
        }) {
          return ListTile(
            leading: Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            subtitle:
                subtitle == null ? null : Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.chevron_right_rounded),
            onTap: () => Navigator.pop(ctx, value),
          );
        }

        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Харилцагчийн төрөл',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  'Хувь хүн эсвэл байгуулга сонгоно уу.',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 12),
                opt(
                  icon: Icons.person_rounded,
                  title: 'Хувь хүн',
                  value: 'Хувь хүн',
                  color: const Color(0xFF3B82F6),
                  subtitle: 'Сугалаа + QR‑тай eBarimt',
                ),
                opt(
                  icon: Icons.apartment_rounded,
                  title: 'Байгуулга',
                  value: 'Байгуулга',
                  color: const Color(0xFF0D9488),
                  subtitle: 'Регистрээр нэр шалгаад хэвлэнэ',
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => Navigator.pop(ctx),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text('Болих'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (type == null) return null;
    if (type != 'Байгуулга') {
      return (customerType: 'Хувь хүн', register: null, orgName: null, tin: null);
    }

    final regCtrl = TextEditingController();
    String? orgNameFromCheck;
    String? orgTinFromCheck;
    final res = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        bool checking = false;
        String? checkedName;
        String? checkedTin;
        String? err;

        String normalizeReg(String input) {
          var t = input.trim().toUpperCase();
          t = t.replaceAll(RegExp(r'[\\s\\-\\._/\\\\]'), '');
          return t;
        }

        Future<void> doCheck(void Function(void Function()) setState) async {
          final reg = normalizeReg(regCtrl.text);
          if (reg.isEmpty) {
            setState(() => err = 'Регистр оруулна уу.');
            return;
          }
          setState(() {
            checking = true;
            err = null;
            checkedName = null;
            checkedTin = null;
          });
          try {
            final wh = Provider.of<WarehouseProvider>(context, listen: false);
            final org = await wh.tryGetEtaxOrganization(reg);
            final orgMap = (org?['organization'] is Map)
                ? Map<String, dynamic>.from(org!['organization'] as Map)
                : (org ?? const <String, dynamic>{});

            // Backend (`warehouse-service-main`) response shape:
            // { status: "success", data: { organization: { regno, name, ... } } }
            // Mobile bridge unwraps "data" -> { organization: {...} }.
            final n = (orgMap['organizationName'] ??
                    orgMap['name'] ??
                    orgMap['orgName'] ??
                    org?['organizationName'] ??
                    org?['name'] ??
                    org?['orgName'] ??
                    '')
                .toString()
                .trim();
            // ETax service returns no tin field; keep best-effort for other backends.
            final t = (orgMap['tin'] ??
                    orgMap['tinNumber'] ??
                    orgMap['ttd'] ??
                    org?['tin'] ??
                    org?['tinNumber'] ??
                    org?['ttd'] ??
                    '')
                .toString();
            if (n.isEmpty) {
              // Fallback: эхлээд TIN аваад, түүнээс нэрийг авах (api.ebarimt.mn getTinInfo)
              final direct = await _getTinInfoDirect(reg);
              final dn = (direct.name ?? '').trim();
              final dt = (direct.tin ?? '').trim();
              if (dn.isNotEmpty) {
                setState(() {
                  checkedName = dn;
                  checkedTin = dt.isEmpty ? null : dt;
                });
              } else if (dt.isNotEmpty) {
                final name2 = await _getInfoNameByTin(dt);
                if (name2 != null && name2.trim().isNotEmpty) {
                  setState(() {
                    checkedName = name2.trim();
                    checkedTin = dt;
                    err = null;
                  });
                } else {
                setState(() {
                  checkedName = null;
                  checkedTin = dt;
                  err =
                      'TIN олдлоо ($dt) гэхдээ байгуулгын нэр олдсонгүй. Регистр зөв эсэхийг шалгана уу.';
                });
                }
              } else {
                setState(() {
                  err =
                      'Байгуулгын нэр олдсонгүй. Регистрээ шалгана уу.${direct.message != null ? '\n\nТехник: ${direct.message}' : ''}';
                });
              }
            } else {
              setState(() {
                checkedName = n;
                checkedTin = t.trim().isEmpty ? null : t.trim();
              });
            }
          } catch (e) {
            setState(() {
              err = 'Шалгах үед алдаа: $e';
            });
          } finally {
            setState(() => checking = false);
          }
        }

        return StatefulBuilder(
          builder: (ctx, setState) => SafeArea(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                8,
                16,
                16 + MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Байгуулгын регистр шалгах',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Регистр оруулаад нэрээ шалгаад дараа нь хэвлэнэ.',
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: regCtrl,
                    keyboardType: TextInputType.text,
                    decoration: InputDecoration(
                      labelText: 'Регистр',
                      hintText: 'Ж: 1234567',
                      prefixIcon: const Icon(Icons.badge_rounded),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onChanged: (_) {
                      setState(() {
                        checkedName = null;
                        checkedTin = null;
                        err = null;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  ElevatedButton.icon(
                    onPressed: checking ? null : () => doCheck(setState),
                    icon: checking
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.search_rounded),
                    label: Text(checking ? 'Шалгаж байна...' : 'Нэр шалгах'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D9488),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  if (err != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.20),
                        ),
                      ),
                      child: Text(err!, style: const TextStyle(color: Colors.red)),
                    ),
                  ],
                  if (checkedName != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: const Color(0xFF10B981).withValues(alpha: 0.20),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            checkedName!,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          if (checkedTin != null && checkedTin!.trim().isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'TIN: ${checkedTin!.trim()}',
                                style: const TextStyle(color: Colors.black54),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Болих'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: (checkedName == null || checking)
                              ? null
                              : () {
                                  orgNameFromCheck = checkedName;
                                  orgTinFromCheck = checkedTin;
                                  Navigator.pop(ctx, true);
                                },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          child: const Text('Үргэлжлүүлэх'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (res != true) return null;
    final reg = regCtrl.text.trim();
    return (
      customerType: 'Байгуулга',
      register: reg.isEmpty ? null : reg,
      orgName: orgNameFromCheck,
      tin: orgTinFromCheck,
    );
  }

  Future<void> _printEbarimtFromDetails(Order o) async {
    if (_busy) return;
    if (_printLocked) return;
    setState(() => _busy = true);
    try {
      final role = Provider.of<AuthProvider>(context, listen: false).userRole;
      if (isAgentRole(role)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Agent эрхээр eBarimt/хэвлэх хийхгүй (зөвхөн захиалга).'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final warehouse = Provider.of<WarehouseProvider>(context, listen: false);
      if (!warehouse.connected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Серверт холбогдоогүй байна'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final paymentMethod = await _pickPaymentMethod();
      if (paymentMethod == null) return;

      final customerPick = await _pickCustomerType();
      if (customerPick == null) return;

      final bt = BluetoothPrinterService();
      final connected = await bt.checkConnection();
      if (!connected) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              '⚠️ Bluetooth принтер холбогдоогүй байна.\nSettings → Bluetooth Принтер хэсгээс холбоно уу.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 4),
          ),
        );
        return;
      }

      final oid = int.tryParse(o.id) ?? int.tryParse(widget.orderId);
      if (oid == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Захиалгын ID буруу байна')),
        );
        return;
      }

      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => const PopScope(
          canPop: false,
          child: Center(child: CircularProgressIndicator()),
        ),
      );

      // Хувь хүн: ebarimt/register-оос сугалаа/QR авна.
      Map<String, dynamic>? regBody;
      if (customerPick.customerType == 'Хувь хүн' &&
          (!o.ebarimtRegistered || (o.ebarimtLottery ?? '').trim().isEmpty)) {
        regBody = await warehouse.tryEbarimtRegisterOrder(oid);
        if (regBody == null) {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
          }
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('eBarimt бүртгэл амжилтгүй (сугалаа/ДДТД ирсэнгүй).'),
              backgroundColor: Colors.red,
            ),
          );
          return;
        }
      }

      final lottery = (o.ebarimtLottery ?? '').trim().isNotEmpty
          ? o.ebarimtLottery!.trim()
          : (SugalaaniiDugaar.extractFromRegisterResponse(regBody) ?? '').trim();
      final qr = (o.ebarimtQrData ?? '').trim().isNotEmpty
          ? o.ebarimtQrData!.trim()
          : (_extractQrData(regBody) ?? '').trim();

      // Order -> SalesItem хувиргаад BT баримтын QR/сугалаатай хэвлэлтийг ашиглана.
      final salesItems = o.items
          .map(
            (it) => SalesItem(
              productId: it.productId,
              productName: it.productName,
              price: it.unitPrice,
              quantity: it.quantity,
              orderedUnit: it.orderedUnit,
              orderedQuantity: it.orderedQuantity ?? it.quantity,
              unitsPerBox: it.unitsPerBox,
              freeQuantity: it.freeQuantity,
              unitPriceExcludesVat: false,
            ),
          )
          .toList();

      final shopProvider = Provider.of<ShopProvider>(context, listen: false);
      final shopReg = shopProvider
          .getShopByName(o.customerName)
          ?.registrationNumber
          ?.toString()
          .trim();

      String? billIdForPrint;
      if (customerPick.customerType == 'Байгуулга') {
        billIdForPrint = (o.ebarimtBillId ?? '').trim();
        if (billIdForPrint.isEmpty) {
          final reg2 = await warehouse.tryEbarimtRegisterOrder(oid);
          billIdForPrint =
              (SugalaaniiDugaar.extractBillIdFromRegisterResponse(reg2) ?? '')
                  .trim();
        }
      }

      final ok = await bt.printSalesReceipt(
        items: salesItems,
        shopName: o.customerName,
        paymentMethod: paymentMethod,
        notes: o.notes,
        salesperson: o.salespersonName,
        customerType: customerPick.customerType,
        organizationRegister: customerPick.register,
        organizationName: customerPick.orgName,
        merchantTin: shopReg,
        serverShopRegistration: shopReg,
        ebarimtBillId: billIdForPrint,
        // Байгуулга дээр raster (зураг) горим BillId дэмжихгүй тул текст ESC/POS горим ашиглана.
        useRasterReceipt: customerPick.customerType != 'Байгуулга',
        qrDataFromServer:
            (customerPick.customerType == 'Хувь хүн' && qr.isNotEmpty) ? qr : null,
        lotteryNumberOverride:
            customerPick.customerType == 'Хувь хүн' ? lottery : null,
      );

      // Байгуулга: Weve website дээр харагдуулахын тулд reg/tin/name-г захиалгад хадгална.
      if (customerPick.customerType == 'Байгуулга') {
        final reg = (customerPick.register ?? '').trim();
        final name = (customerPick.orgName ?? '').trim();
        final tin = (customerPick.tin ?? '').trim();
        if (reg.isNotEmpty && (tin.isNotEmpty || name.isNotEmpty)) {
          try {
            await warehouse.updateOrderEbarimtInfo(
              orderId: oid,
              tin: tin,
              regNo: reg,
              orgName: name.isEmpty ? null : name,
            );
          } catch (_) {}
        }
      }

      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok ? '🖨️ eBarimt баримт хэвлэгдлээ!' : '❌ Хэвлэхэд алдаа гарлаа'),
          backgroundColor: ok ? Colors.green : Colors.red,
        ),
      );
      if (ok && mounted) {
        // Нэг удаа сугалаа/QR авч хэвлэсэн бол дахин хэвлэхийг UI дээр хориглоно.
        await _markOrderPrinted(o.id);
        setState(() => _printLocked = true);
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).maybePop();
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('eBarimt хэвлэхэд алдаа: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Best-effort load once; don't block first frame.
    _loadPrintedOrders();
    final resolved =
        widget.order ?? context.watch<OrderProvider>().getOrderById(widget.orderId);

    if (resolved == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Захиалгын дэлгэрэнгүй'),
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
        ),
        body: const Center(child: Text('Захиалга олдсонгүй')),
      );
    }

    final o = resolved;
    final auth = context.watch<AuthProvider>();
    final role = auth.userRole;
    final canSalesAgentCancel = isAgentRole(role) &&
        !isManagerRole(role) &&
        !_printLocked &&
        orderCanSalesAgentCancelOwnPending(
          o,
          currentUserId: auth.user?.id,
          prefsAgentNumericId: _prefsAgentId,
          locallyPrintedOrderIds: _printedOrderIds,
        );
    final myId = (auth.user?.id ?? '').trim();
    final ownOrder = myId.isNotEmpty &&
        orderSalespersonMatchesCurrentUser(
          orderSalespersonId: o.salespersonId,
          currentUserId: myId,
          agentNumericIdFromPrefs: _prefsAgentId,
        );
    final pendingLike = o.status.toLowerCase() == 'pending' ||
        o.status.toLowerCase() == 'confirmed';
    final receiptBlocksSimpleCancel =
        orderReceiptPrintedForAgentCancel(o, _printedOrderIds) ||
            _printLocked;
    final showAgentReceiptPrintedHint = isAgentRole(role) &&
        !isManagerRole(role) &&
        ownOrder &&
        pendingLike &&
        receiptBlocksSimpleCancel &&
        !orderCanReturnEbarimtReceipt(o) &&
        o.status.toLowerCase() != 'cancelled';
    final dateText =
        MaterialLocalizations.of(context).formatMediumDate(o.orderDate);
    final timeText = MaterialLocalizations.of(context)
        .formatTimeOfDay(TimeOfDay.fromDateTime(o.orderDate));

    Color statusColor(String s) => switch (s.toLowerCase()) {
          'pending' => const Color(0xFFF59E0B),
          'confirmed' => const Color(0xFF3B82F6),
          'delivered' => const Color(0xFF10B981),
          'cancelled' => const Color(0xFFEF4444),
          _ => const Color(0xFF64748B),
        };

    final sc = statusColor(o.status);
    final alreadyHasEbarimt = o.ebarimtRegistered ||
        (o.ebarimtBillId != null && o.ebarimtBillId!.trim().isNotEmpty) ||
        (o.ebarimtLottery != null && o.ebarimtLottery!.trim().isNotEmpty) ||
        (o.ebarimtQrData != null && o.ebarimtQrData!.trim().isNotEmpty);
    final alreadyPrinted = _printedOrderIds.contains(o.id.trim());
    if (alreadyPrinted && !_printLocked) {
      // Keep local state consistent if orderId is persisted.
      _printLocked = true;
    }
    final canPrintNow = !_busy && !_printLocked && !alreadyHasEbarimt;

    return GoPopScope(
      fallbackRoute: '/sales-orders',
      child: Scaffold(
        backgroundColor: const Color(0xFFF8FAFC),
        appBar: AppBar(
          title: const Text('Захиалгын дэлгэрэнгүй'),
          backgroundColor: const Color(0xFF3B82F6),
          foregroundColor: Colors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_ios_new_rounded),
            tooltip: 'Буцах',
            onPressed: () => context.go('/sales-orders'),
          ),
        ),
        body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          o.customerName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: sc.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(999),
                        ),
                        child: Text(
                          o.status,
                          style: TextStyle(
                              color: sc,
                              fontWeight: FontWeight.w800,
                              fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _kv('Огноо / Цаг', '$dateText • $timeText'),
                  _kv('Утас', o.customerPhone),
                  _kv('Хаяг', o.customerAddress),
                  if (o.notes != null && o.notes!.trim().isNotEmpty)
                    _kv('Тэмдэглэл', o.notes!.trim()),
                  _kv('Баримт', _receiptStatusSummary(o)),
                  if (o.ebarimtRegistered ||
                      (o.ebarimtReturnId != null &&
                          o.ebarimtReturnId!.isNotEmpty)) ...[
                    const Divider(height: 20),
                    _kv('eBarimt', o.ebarimtRegistered ? 'Бүртгэгдсэн' : '—'),
                    if (o.ebarimtBillId != null && o.ebarimtBillId!.isNotEmpty)
                      _kv('ДДТД', o.ebarimtBillId!),
                    if (o.ebarimtReturnId != null &&
                        o.ebarimtReturnId!.isNotEmpty)
                      _kv('Буцаалт', 'Буцаагдсан (${o.ebarimtReturnId!})'),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (orderCanReturnEbarimtReceipt(o))
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => confirmReturnEbarimtReceipt(context, o),
                    icon: const Icon(Icons.receipt_long_outlined),
                    label: const Text('Баримт буцаах (eBarimt/POS)'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB45309),
                      side: const BorderSide(color: Color(0xFFF59E0B)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

            if (canSalesAgentCancel)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final ok =
                          await confirmSalesAgentCancelPendingOrder(context, o);
                      if (!context.mounted) return;
                      if (ok) context.go('/sales-orders');
                    },
                    icon: const Icon(Icons.cancel_schedule_send_rounded),
                    label: const Text('Захиалга цуцлах'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFB91C1C),
                      side: const BorderSide(color: Color(0xFFDC2626)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
              ),

            if (showAgentReceiptPrintedHint)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade800),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Баримт хэвлэгдсэн тул энэ захиалгыг эндээс цуцлах боломжгүй.',
                          style: TextStyle(
                            color: Colors.orange.shade900,
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // eBarimt хэвлэх
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: canPrintNow ? () => _printEbarimtFromDetails(o) : null,
                  icon: const Icon(Icons.print_rounded),
                  label: Text(
                    _busy
                        ? 'Боловсруулж байна...'
                        : (alreadyHasEbarimt || _printLocked)
                            ? 'eBarimt хэвлэсэн'
                            : 'eBarimt хэвлэх',
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // Items
            Text(
              'Авсан бараа',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E293B),
                  ),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: o.items.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, color: Colors.grey.shade200),
                itemBuilder: (context, i) {
                  final it = o.items[i];
                  return Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                it.productName,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Төлөх: ${it.paidQuantity} ш',
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              if (it.freeQuantity > 0) ...[
                                const SizedBox(height: 2),
                                Text(
                                  'Бэлэг: +${it.freeQuantity} ш',
                                  style: TextStyle(
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${it.totalPrice.toStringAsFixed(0)} ₮',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),

            // Total
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFFEFF6FF),
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: const Color(0xFF3B82F6).withOpacity(0.2)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Нийт дүн',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text(
                    '${o.totalAmount.toStringAsFixed(0)} ₮',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF3B82F6),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _kv(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              k,
              style: TextStyle(
                  color: Colors.grey.shade600, fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(
            child: Text(
              v,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
