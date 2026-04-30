import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../../models/sales_item_model.dart';
import '../../providers/product_provider.dart';
import '../../providers/shop_provider.dart';
import '../../services/bluetooth_printer_service.dart';
import '../../services/pos_receipt_api_service.dart';
import 'sales_receipt_preview.dart';
import 'TinDugaar.dart';

/// Төлбөр сонгосны дараа: баримттай (хэвлэх дуусах хүртэл сервер руу биш) /
/// зөвхөн баримттай урсгал.
class SuccessReceiptDialog extends StatefulWidget {
  final String paymentMethod;
  final List<SalesItem> savedItems;
  final String savedShopName;
  final String? savedNotes;
  final String? salespersonName;
  final String? shopRegistrationFromServer;
  final bool directPosDelivery;
  final String? directPosBaseUrl;
  final Future<({int orderId, String? serverLotteryNumber})?> Function()
      onCommitWarehouseOrder;
  final Future<void> Function(
    String paymentMethod,
    CustomerEbarimtInfo info,
    int orderId,
  ) onEbarimtSubmit;

  const SuccessReceiptDialog({
    super.key,
    required this.paymentMethod,
    required this.savedItems,
    required this.savedShopName,
    this.savedNotes,
    this.salespersonName,
    this.shopRegistrationFromServer,
    this.directPosDelivery = false,
    this.directPosBaseUrl,
    required this.onCommitWarehouseOrder,
    required this.onEbarimtSubmit,
  });

  @override
  State<SuccessReceiptDialog> createState() => _SuccessReceiptDialogState();
}

class _SuccessReceiptDialogState extends State<SuccessReceiptDialog> {
  String _customerType = 'Хувь хүн';
  CustomerEbarimtInfo? _baiguulgaInfo;

  late String _previewLottery;
  bool _lotteryFromServer = false;
  bool _warehouseCommitted = false;
  bool _committingWarehouse = false;
  int? _orderId;
  final DateTime _previewTime = DateTime.now();
  String? _posQrData;

  /// Диалог дотор тодорхой харуулах (SnackBar нь цонхны ард/доог дарагдаж болно).
  String? _bannerMessage;
  bool _bannerIsWarning = false;

  double get _total =>
      widget.savedItems.fold(0.0, (sum, item) => sum + item.total);

  @override
  void initState() {
    super.initState();
    // Суглааны дугаарыг апп өөрөө зохиохгүй: сервер / eBarimt POS-оос ирсний дараа л тохируулна.
    _previewLottery = '';
  }

  void _clearBanner() {
    if (_bannerMessage != null) {
      setState(() => _bannerMessage = null);
    }
  }

  String _shortError(Object e) {
    final s = e.toString().trim();
    if (s.length > 600) return '${s.substring(0, 600)}…';
    return s;
  }

  void _showBanner(String message, {bool warning = false}) {
    if (!mounted) return;
    final t = message.trim();
    if (t.isEmpty) return;
    final forState = t.length > 1200 ? '${t.substring(0, 1200)}…' : t;
    setState(() {
      _bannerMessage = forState;
      _bannerIsWarning = warning;
    });
    final forSnack = t.length > 280 ? '${t.substring(0, 280)}…' : t;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(forSnack),
        backgroundColor: warning ? Colors.orange.shade800 : Colors.red.shade800,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 88),
        duration: const Duration(seconds: 10),
      ),
    );
  }

  Future<bool> _ensureWarehouseOrder({required bool applyServerLottery}) async {
    if (_warehouseCommitted) return true;
    if (_committingWarehouse) return false;
    setState(() => _committingWarehouse = true);
    try {
      final result = await widget.onCommitWarehouseOrder();
      if (!mounted) return false;
      if (result == null) {
        setState(() => _committingWarehouse = false);
        _showBanner(
          'Захиалга сервер руу илгээгдсэнгүй.\n\n'
          'Шалгах:\n'
          '• Нэвтэрсэн эсэх, Warehouse холболт\n'
          '• Server URL зөв эсэх (бодит утас: PC-ийн Wi‑Fi IP, жишээ 192.168.0.x:3000)\n'
          '• Backend асаалттай эсэх, интернет / Wi‑Fi\n'
          '• Windows Firewall: TCP 3000 портыг зөвшөөрсөн эсэх',
        );
        return false;
      }
      final serverLottery = result.serverLotteryNumber?.trim();
      setState(() {
        _warehouseCommitted = true;
        _orderId = result.orderId;
        _committingWarehouse = false;
        if (applyServerLottery &&
            serverLottery != null &&
            serverLottery.isNotEmpty) {
          _previewLottery = serverLottery;
          _lotteryFromServer = true;
        }
      });
      return true;
    } catch (e) {
      if (mounted) {
        setState(() => _committingWarehouse = false);
        _showBanner('Сервер руу илгээхэд алдаа:\n\n${_shortError(e)}');
      }
      return false;
    }
  }

  CustomerEbarimtInfo _buildEbarimtInfo() {
    return _customerType == 'Хувь хүн'
        ? CustomerEbarimtInfo(customerType: 'Хувь хүн')
        : _baiguulgaInfo!;
  }

  bool _validateOrgIfNeeded() {
    if (_customerType != 'Байгуулга') return true;
    if (_baiguulgaInfo == null ||
        _baiguulgaInfo!.registerNumber == null ||
        _baiguulgaInfo!.registerNumber!.isEmpty ||
        _baiguulgaInfo!.tinNumber == null ||
        _baiguulgaInfo!.tinNumber!.isEmpty) {
      _showBanner(
        'Байгуулга: регистр болон TIN дугаар оруулна уу («Шалгах» эсвэл гараар).',
        warning: true,
      );
      return false;
    }
    final keys = Provider.of<ShopProvider>(context, listen: false)
        .shops
        .map((s) => s.registrationNumber)
        .whereType<String>()
        .where((r) => r.trim().isNotEmpty)
        .map(normalizeOrgRegistration)
        .where((k) => k.isNotEmpty)
        .toSet();
    final wh = validateWarehouseRegistration(
      reg: _baiguulgaInfo!.registerNumber!.trim(),
      serverShopRegistration: widget.shopRegistrationFromServer,
      selectedShopName: widget.savedShopName,
      serverKnownRegistrationKeys: keys.isEmpty ? null : keys,
    );
    if (wh != null) {
      _showBanner(wh, warning: true);
      return false;
    }
    return true;
  }

  /// Баримттай:
  /// - Хувь хүн: эхлээд сервер руу захиалга илгээж сугалааны дугаар авна, дараа нь хэвлэнэ.
  /// - Байгуулга: эхлээд хэвлэх, дараа нь сервер + ebarimt.
  Future<void> _doPrint() async {
    if (!_validateOrgIfNeeded()) return;
    _clearBanner();

    final info = _buildEbarimtInfo();
    final btPrinter = BluetoothPrinterService();

    // Хүргэлт: POS API (7080) руу шууд илгээнэ — website/backend order үүсгэхгүй.
    if (widget.directPosDelivery) {
      final base =
          (widget.directPosBaseUrl ?? 'http://43.231.115.209:7080').trim();
      try {
        final pos = PosReceiptApiService();
        final productProvider =
            Provider.of<ProductProvider>(context, listen: false);

        final posItems = widget.savedItems.map((it) {
          final product = productProvider.getProductById(it.productId);
          final bar = (product?.barcode ?? product?.productCode ?? it.productId)
              .toString();
          final unitGross = PosReceiptApiService.unitPriceGrossFromSalesItem(it);
          return PosReceiptApiService.buildPosItem(
            name: it.productName,
            barCode: bar.isNotEmpty ? bar : it.productId,
            qty: it.paidQuantity,
            unitPriceGross: unitGross,
          );
        }).toList();

        final merchantTin =
            (widget.shopRegistrationFromServer ?? '').trim().isNotEmpty
                ? widget.shopRegistrationFromServer!.trim()
                : '37900846788';

        final isB2B = _customerType == 'Байгуулга';
        final payload = PosReceiptApiService.buildPosReceiptPayload(
          items: posItems,
          merchantTin: merchantTin,
          type: isB2B ? 'B2B_RECEIPT' : 'B2C_RECEIPT',
          paymentType: 'CASH',
          customerTin: isB2B ? (info.tinNumber ?? '') : null,
          consumerNo: isB2B ? null : '',
        );

        final created =
            await pos.createReceipt(baseUrl: base, payload: payload);
        final lot = (created.lottery ?? '').trim();
        final bill = (created.billId ?? created.id).trim();
        setState(() {
          _posQrData = (created.qrData ?? '').trim().isEmpty
              ? null
              : created.qrData!.trim();
          _previewLottery = lot.isNotEmpty ? lot : bill;
          _lotteryFromServer = lot.isNotEmpty;
        });
      } catch (e) {
        _showBanner('POS (7080) руу илгээхэд алдаа:\n\n${_shortError(e)}');
        return;
      }

      // Manager requirement:
      // POS/eBarimt сугалаа (эсвэл ДДТД) амжилтгүй бол Weve site руу захиалга явуулахгүй.
      if (_previewLottery.trim().isEmpty) {
        _showBanner(
          'Сугалаа / ДДТД POS-оос ирээгүй тул захиалгыг Weve site руу илгээхгүй.\n\n'
          'POS (7080) болон сүлжээг шалгаад дахин оролдоно уу.',
          warning: true,
        );
        return;
      }

      // POS баримт амжилттай (сугалаа/ДДТД-тэй) болсон үед л Weve site руу захиалга илгээнэ.
      final okWarehouse = await _ensureWarehouseOrder(applyServerLottery: false);
      if (!okWarehouse) {
        _showBanner(
          'Захиалгыг Weve site руу илгээж чадсангүй.\n\n'
          'Шалгах:\n'
          '• Интернет / Wi‑Fi\n'
          '• Warehouse backend холболт\n'
          '• Нэвтэрсэн токен хүчинтэй эсэх',
        );
        return;
      }
    }

    if (_customerType == 'Хувь хүн') {
      if (!widget.directPosDelivery) {
        if (!await _ensureWarehouseOrder(applyServerLottery: true)) return;
      }
    }
    if (!mounted) return;

    // Хувь хүн: сугалаа ирээгүй бол огт хэвлэхгүй; захиалга серверт үлдсэн тул eBarimt дамжуулга хийнэ.
    if (_customerType == 'Хувь хүн' && _previewLottery.trim().isEmpty) {
      _showBanner(
        'Сугалааны дугаар eBarimt/POS-оос ирээгүй тул баримт хэвлэхгүй.\n\n'
        'Захиалга серверт бүртгэгдсэн. Сүлжээ, POS болон баримт бүртгэлийг шалгаад дахин «Хэвлэх» дарж болно.',
        warning: true,
      );
      final oid0 = _orderId;
      if (oid0 == null) {
        _showBanner(
          'Захиалгын дугаар олдсонгүй. Серверт илгээгдсэн эсэхийг шалгана уу.',
        );
        return;
      }
      await widget.onEbarimtSubmit(widget.paymentMethod, info, oid0);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text(
            'Сугалаагүй тул хэвлэхгүй. Захиалга серверт бүртгэгдлээ.',
          ),
          backgroundColor: Colors.orange.shade800,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 88),
          duration: const Duration(seconds: 5),
        ),
      );
      Navigator.pop(context);
      context.go('/sales-dashboard');
      return;
    }

    final printed = await btPrinter.printSalesReceipt(
      items: widget.savedItems,
      shopName: widget.savedShopName,
      paymentMethod: widget.paymentMethod,
      notes: widget.savedNotes,
      salesperson: widget.salespersonName,
      customerType: _customerType,
      organizationRegister:
          _customerType == 'Байгуулга' ? _baiguulgaInfo!.registerNumber : null,
      organizationName:
          _customerType == 'Байгуулга' ? _baiguulgaInfo?.companyName : null,
      merchantTin: widget.shopRegistrationFromServer,
      serverShopRegistration: widget.shopRegistrationFromServer,
      qrDataFromServer: _posQrData,
      lotteryNumberOverride:
          _customerType == 'Хувь хүн' ? _previewLottery : null,
      themeContext: context,
    );
    if (!mounted) return;
    if (!printed) {
      final detail = btPrinter.lastPrintError?.trim();
      final isLotteryBlock = detail != null &&
          (detail.contains('Сугалааны') || detail.contains('сугалаа'));
      _showBanner(
        isLotteryBlock
            ? '$detail\n\nЗахиалга серверт бүртгэгдсэн бол «Хэвлэх»-ийг дахин дарж болно.'
            : (_customerType == 'Хувь хүн'
                    ? 'Хэвлэхэд алдаа гарлаа.\n\n'
                        '• Bluetooth принтер Тохиргооноос холбосон эсэх\n'
                        '• Принтер асаалттай, цаас байгаа эсэх (ихэнх принтер цаасгүй бол хэвлэхгүй)\n'
                        '• Android: Bluetooth зөвшөөрөл (Ойролцоох төхөөрөмж)\n'
                        '• Термаль принтер QR тушаал дэмжихгүй бол автоматаар текстээр дахин оролдоно\n\n'
                        'Захиалга серверт аль хэдийн бүртгэгдсэн бол дахин «Хэвлэх» дарж болно.'
                    : 'Хэвлэхэд алдаа гарлаа. Сервер руу захиалга хараахан илгээгдээгүй байж магадгүй.\n\n'
                        'Принтер болон Bluetooth зөвшөөрлийг шалгана уу.') +
                (detail != null && detail.isNotEmpty && !isLotteryBlock
                    ? '\n\nТехник: $detail'
                    : ''),
        warning: isLotteryBlock,
      );
      return;
    }

    if (_customerType == 'Байгуулга') {
      if (!widget.directPosDelivery) {
        if (!await _ensureWarehouseOrder(applyServerLottery: false)) return;
      }
    }

    if (!widget.directPosDelivery) {
      final oid = _orderId;
      if (oid == null) {
        _showBanner(
          'Захиалгын дугаар (orderId) олдсонгүй. Баримт хэвлэгдсэн ч серверт бүртгэл бүрэн биш байж магадгүй. Дахин оролдоно уу эсвэл дэмжлэгт хандана уу.',
        );
        return;
      }

      await widget.onEbarimtSubmit(widget.paymentMethod, info, oid);
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Баримт хэвлэгдлээ, захиалга серверт бүртгэгдлээ'),
        backgroundColor: Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 88),
        duration: const Duration(seconds: 4),
      ),
    );
    Navigator.pop(context);
    context.go('/sales-dashboard');
  }

  void _cancelDialog() {
    Navigator.pop(context);
  }

  String _hintText() {
    if (_warehouseCommitted) {
      return 'Захиалга серверт бүртгэгдлээ.';
    }
    return 'Баримттай: хувь хүн бол серверээс сугалаа авч хэвлэнэ; байгуулга бол регистр оруулж эхлээд хэвлэнэ.';
  }

  @override
  Widget build(BuildContext context) {
    // AlertDialog + дэд Theme зарим Android дээр агуулга харагдахгүй «цагаан хайрцаг»
    // болгодог тул Dialog + тодорхой өнгө, тогтмол өндөр ашиглана.
    const ink = Color(0xFF111827);
    const muted = Color(0xFF64748B);
    const primary = Color(0xFF0D9488);
    final screenH = MediaQuery.sizeOf(context).height;

    Widget segmentWrap(Widget child) {
      return Theme(
        data: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.light(
            primary: primary,
            onPrimary: Colors.white,
            surface: const Color(0xFFE7E5E4),
            onSurface: ink,
            secondaryContainer: Colors.white,
            onSecondaryContainer: ink,
          ),
        ),
        child: child,
      );
    }

    final scrollChildren = <Widget>[
      if (_bannerMessage != null) ...[
        Material(
          color: _bannerIsWarning ? Colors.orange.shade50 : Colors.red.shade50,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 4, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _bannerIsWarning
                      ? Icons.warning_amber_rounded
                      : Icons.error_outline_rounded,
                  color: _bannerIsWarning
                      ? Colors.orange.shade900
                      : Colors.red.shade900,
                  size: 22,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: SelectableText(
                    _bannerMessage!,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.4,
                      color: _bannerIsWarning
                          ? Colors.orange.shade900
                          : Colors.red.shade900,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(Icons.close, size: 20, color: ink),
                  onPressed: _clearBanner,
                  tooltip: 'Хаах',
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      Text(
        '${widget.paymentMethod} төлбөр сонгогдлоо.',
        style: const TextStyle(fontSize: 14, color: ink),
      ),
      const SizedBox(height: 12),
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          const Text(
            'Нийт дүн:',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w600, color: ink),
          ),
          Text(
            '${_total.toStringAsFixed(0)} \u20AE',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.bold, color: ink),
          ),
        ],
      ),
      const SizedBox(height: 8),
      Text(
        _hintText(),
        style: const TextStyle(fontSize: 12, color: muted),
      ),
      const SizedBox(height: 16),
      const Text(
        'Харилцагч',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
      ),
      const SizedBox(height: 8),
      segmentWrap(
        SegmentedButton<String>(
          segments: const [
            ButtonSegment(
              value: 'Хувь хүн',
              label: Text('Хувь хүн'),
              icon: Icon(Icons.person, size: 18),
            ),
            ButtonSegment(
              value: 'Байгуулга',
              label: Text('Байгуулга'),
              icon: Icon(Icons.business, size: 18),
            ),
          ],
          selected: {_customerType},
          onSelectionChanged: (Set<String> selected) {
            setState(() {
              _bannerMessage = null;
              _customerType = selected.first;
              if (_customerType == 'Хувь хүн') _baiguulgaInfo = null;
            });
          },
        ),
      ),
      if (_customerType == 'Байгуулга') ...[
        const SizedBox(height: 16),
        Builder(
          builder: (ctx) {
            final shopProv = Provider.of<ShopProvider>(ctx, listen: false);
            final keys = shopProv.shops
                .map((s) => s.registrationNumber)
                .whereType<String>()
                .where((r) => r.trim().isNotEmpty)
                .map(normalizeOrgRegistration)
                .where((k) => k.isNotEmpty)
                .toSet();
            return TinDugaarInput(
              serverShopRegistration: widget.shopRegistrationFromServer,
              selectedShopName: widget.savedShopName,
              serverKnownRegistrationKeys: keys.isEmpty ? null : keys,
              onChanged: (info) => setState(() => _baiguulgaInfo = info),
            );
          },
        ),
        if ((_baiguulgaInfo?.companyName ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDFA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF0D9488).withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.business_rounded,
                  color: Color(0xFF0D9488),
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Байгууллагын нэр',
                        style: TextStyle(
                          fontSize: 12,
                          color: muted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _baiguulgaInfo!.companyName!.trim(),
                        style: const TextStyle(
                          fontSize: 14,
                          height: 1.25,
                          fontWeight: FontWeight.w800,
                          color: ink,
                        ),
                      ),
                      if ((_baiguulgaInfo?.tinNumber ?? '').trim().isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'TIN: ${_baiguulgaInfo!.tinNumber!.trim()}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
      const SizedBox(height: 16),
      const Text(
        'Баримтын загвар:',
        style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: ink),
      ),
      const SizedBox(height: 8),
      SalesReceiptPreview(
        items: widget.savedItems,
        shopName: widget.savedShopName,
        paymentMethod: widget.paymentMethod,
        notes: widget.savedNotes,
        salesperson: widget.salespersonName,
        customerType: _customerType,
        organizationRegister: _baiguulgaInfo?.registerNumber,
        serverShopRegistration: widget.shopRegistrationFromServer,
        merchantTin: widget.shopRegistrationFromServer,
        lotteryFromServer: _lotteryFromServer,
        lotteryPendingFromServer:
            _customerType == 'Хувь хүн' && !_warehouseCommitted,
        lotteryNumber: _previewLottery,
        previewTime: _previewTime,
      ),
    ];

    final actions = <Widget>[
      SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _committingWarehouse ? null : _doPrint,
          icon: _committingWarehouse
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.print, size: 20),
          label: Text(
            _committingWarehouse ? 'Илгээж байна...' : 'Хэвлэх',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: primary,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
      TextButton(
        onPressed: _committingWarehouse ? null : _cancelDialog,
        child: const Text('Цуцлах', style: TextStyle(color: muted)),
      ),
    ];

    return ExcludeSemantics(
      child: Dialog(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          width: double.maxFinite,
          height: (screenH * 0.88).clamp(280.0, screenH * 0.94),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 6),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.check_circle,
                          color: Colors.green, size: 30),
                    ),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Борлуулалт',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: ink,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: scrollChildren,
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: actions,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
