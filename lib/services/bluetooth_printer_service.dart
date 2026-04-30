import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:image/image.dart' as im;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/order_model.dart';
import '../models/sales_item_model.dart';
import '../utils/cp866_codec.dart';
import '../utils/receipt_vat.dart';
import '../utils/sales_receipt_raster.dart';

/// Bluetooth thermal POS printer service.
///
/// Uses ESC/POS commands to print directly to 58mm/80mm thermal printers
/// connected via Bluetooth. No backend or system print dialog needed.
class BluetoothPrinterService {
  static final BluetoothPrinterService _instance =
      BluetoothPrinterService._internal();
  factory BluetoothPrinterService() => _instance;
  BluetoothPrinterService._internal();

  String? _connectedMac;
  String? _connectedName;
  String? _lastConnectError;
  String? _lastPrintError;

  static const _prefsKeyMac = 'bt_printer_mac';
  static const _prefsKeyName = 'bt_printer_name';

  Future<void> _saveLastPrinter({required String mac, String? name}) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKeyMac, mac);
      if (name != null && name.trim().isNotEmpty) {
        await prefs.setString(_prefsKeyName, name.trim());
      }
    } catch (_) {}
  }

  Future<({String mac, String? name})?> _loadLastPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final mac = prefs.getString(_prefsKeyMac)?.trim();
      if (mac == null || mac.isEmpty) return null;
      final name = prefs.getString(_prefsKeyName)?.trim();
      return (mac: mac, name: (name == null || name.isEmpty) ? null : name);
    } catch (_) {
      return null;
    }
  }

  /// User explicitly wants to forget saved printer.
  Future<void> forgetSavedPrinter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_prefsKeyMac);
      await prefs.remove(_prefsKeyName);
    } catch (_) {}
  }

  /// Best-effort auto-reconnect to last saved printer.
  Future<bool> autoReconnectIfPossible() async {
    if (_connectedMac != null && await checkConnection()) return true;
    final saved = await _loadLastPrinter();
    if (saved == null) return false;
    return connect(saved.mac, name: saved.name);
  }

  /// Сүүлийн холболтын алдааны тайлбар (амжилтгүй болсон үед).
  String? get lastConnectError => _lastConnectError;

  /// Сүүлийн хэвлэлтийн алдаа (writeBytes / холболт).
  String? get lastPrintError => _lastPrintError;

  /// Currently connected printer name
  String? get connectedPrinterName => _connectedName;

  /// Whether a printer is currently connected
  bool get isConnected => _connectedMac != null;

  // ─── Connection ──────────────────────────────────────────────

  /// Android 12+ (API 31+) requires runtime Bluetooth permissions before the
  /// native plugin will run [connect], [pairedBluetooths], etc.
  Future<bool> ensureBluetoothPermissions() async {
    if (kIsWeb) return false;
    if (defaultTargetPlatform != TargetPlatform.android) return true;

    final connect = await Permission.bluetoothConnect.request();
    if (!connect.isGranted) {
      debugPrint('Bluetooth: BLUETOOTH_CONNECT not granted');
      return false;
    }
    final scan = await Permission.bluetoothScan.request();
    if (!scan.isGranted) {
      debugPrint('Bluetooth: BLUETOOTH_SCAN not granted');
      return false;
    }
    return true;
  }

  /// Check if Bluetooth is available and enabled
  Future<bool> isBluetoothAvailable() async {
    try {
      return await PrintBluetoothThermal.bluetoothEnabled;
    } catch (e) {
      debugPrint('🔵 BT check error: $e');
      return false;
    }
  }

  /// Scan for paired Bluetooth devices
  Future<List<BluetoothInfo>> getPairedDevices() async {
    if (!await ensureBluetoothPermissions()) return [];
    try {
      final List<BluetoothInfo> devices =
          await PrintBluetoothThermal.pairedBluetooths;
      debugPrint('🔵 Found ${devices.length} paired BT devices');
      for (final d in devices) {
        debugPrint('   • ${d.name} (${d.macAdress})');
      }
      return devices;
    } catch (e) {
      debugPrint('🔵 BT scan error: $e');
      return [];
    }
  }

  /// Connect to a specific Bluetooth printer by MAC address
  Future<bool> connect(String macAddress, {String? name}) async {
    if (!await ensureBluetoothPermissions()) {
      _lastConnectError = 'Bluetooth зөвшөөрөл хэрэгтэй.';
      return false;
    }

    _lastConnectError = null;
    const attempts = 3;
    const delayBetween = Duration(milliseconds: 600);

    for (var i = 0; i < attempts; i++) {
      try {
        if (i > 0 || _connectedMac != null) {
          await disconnect();
          await Future.delayed(delayBetween);
        }

        final connected = await PrintBluetoothThermal.connect(
          macPrinterAddress: macAddress,
        );
        if (connected) {
          _connectedMac = macAddress;
          _connectedName = name;
          _lastConnectError = null;
          await _saveLastPrinter(mac: macAddress, name: name);
          debugPrint('[BT] printer connected: $name ($macAddress)');
          return true;
        }
        _lastConnectError =
            'Принтер хариу өгөөгүй (connect=false). Төхөөрөмж асаалттай эсэх, өөр утас холбогдсон эсэхийг шалгана уу.';
        debugPrint(
          '[BT] connect failed (attempt ${i + 1}/$attempts): $macAddress',
        );
      } catch (e) {
        _lastConnectError = e.toString();
        debugPrint('[BT] connect error: $e');
      }
    }

    if (_lastConnectError == null || _lastConnectError!.isEmpty) {
      _lastConnectError =
          'Холболт амжилтгүй. Принтерыг дахин асааж, хослолтыг шалгана уу.';
    }
    return false;
  }

  /// Disconnect from the current printer
  Future<void> disconnect() async {
    try {
      await PrintBluetoothThermal.disconnect;
      _connectedMac = null;
      _connectedName = null;
      debugPrint('🔵 BT принтер салгагдлаа');
    } catch (e) {
      debugPrint('🔵 BT disconnect error: $e');
    }
  }

  /// Check connection status
  Future<bool> checkConnection() async {
    try {
      return await PrintBluetoothThermal.connectionStatus;
    } catch (e) {
      return false;
    }
  }

  Future<bool> _writeBytesOnce(List<int> bytes) async {
    try {
      final ok = await PrintBluetoothThermal.writeBytes(bytes);
      debugPrint('[BT] writeBytes -> $ok (${bytes.length} bytes)');
      return ok;
    } catch (e) {
      _lastPrintError = e.toString();
      debugPrint('[BT] writeBytes error: $e');
      return false;
    }
  }

  /// Native талд socket байгаа эсэхийг баталгаажуулж, шаардлагатай бол дахин холбоно.
  Future<bool> _ensureNativeConnection() async {
    if (_connectedMac == null) {
      // app restart-аас хойш хадгалсан принтер байвал автоматаар холбоно.
      final auto = await autoReconnectIfPossible();
      if (!auto) return false;
    }
    if (await checkConnection()) return true;
    debugPrint('[BT] connectionStatus=false, reconnecting before print...');
    final ok = await connect(_connectedMac!, name: _connectedName);
    if (ok) await Future.delayed(const Duration(milliseconds: 250));
    return await checkConnection();
  }

  /// Эхний write амжилтгүй бол салгаад дахин холбож дахин оролдоно.
  Future<bool> _writeWithReconnect(List<int> bytes) async {
    if (!await _ensureNativeConnection()) {
      _lastPrintError ??=
          'Принтертай Bluetooth холболт алга. Тохиргооноос дахин холбоно уу.';
      return false;
    }
    var ok = await _writeBytesOnce(bytes);
    if (ok) return true;
    debugPrint('[BT] write failed, hard reconnect + retry');
    final savedMac = _connectedMac;
    final savedName = _connectedName;
    await disconnect();
    await Future.delayed(const Duration(milliseconds: 400));
    if (savedMac == null) return false;
    final re = await connect(savedMac, name: savedName);
    if (!re) {
      _lastPrintError ??= 'Дахин холбогдож чадсангүй.';
      return false;
    }
    await Future.delayed(const Duration(milliseconds: 350));
    ok = await _writeBytesOnce(bytes);
    if (!ok) {
      _lastPrintError ??=
          'Хэвлэх амжилтгүй. Принтер ESC/POS термаль, цаас, холболтыг шалгана уу.';
    }
    return ok;
  }

  // ─── ESC/POS Command Builders ────────────────────────────────

  /// ESC/POS: Initialize printer
  List<int> _cmdInit() => [0x1B, 0x40];

  /// ESC/POS: Set text alignment (0=left, 1=center, 2=right)
  List<int> _cmdAlign(int align) => [0x1B, 0x61, align];

  /// ESC/POS: Bold on/off
  List<int> _cmdBold(bool on) => [0x1B, 0x45, on ? 1 : 0];

  /// ESC/POS: Double height & width
  List<int> _cmdDoubleSize(bool on) => [0x1D, 0x21, on ? 0x11 : 0x00];

  /// ESC/POS: Feed n lines
  List<int> _cmdFeedLines(int n) => [0x1B, 0x64, n];

  /// ESC/POS: Cut paper (partial)
  List<int> _cmdCut() => [0x1D, 0x56, 0x01];

  /// ESC/POS: Print horizontal line (dashes)
  List<int> _cmdLine(int width) {
    final line = List.filled(width, 0x2D); // '-' character
    return [...line, 0x0A]; // newline
  }

  /// Encode text to bytes (ASCII + CP866 кирилл). [printOrderReceipt] дотор `ESC t` CP866 илгээсний дараа дуудна.
  List<int> _textBytes(String text) {
    return [...cp866.encode(text), 0x0A];
  }

  /// Build a formatted line: left-aligned text + right-aligned text
  List<int> _twoColumnLine(String left, String right, int width) {
    final spaces = width - left.length - right.length;
    final line = spaces > 0 ? '$left${' ' * spaces}$right' : '$left $right';
    return _textBytes(line);
  }

  // ─── Receipt Printing ─────────────────────────────────────────

  /// esc_pos_utils_plus: [Generator.row] — [PosColumn.width]-ийн нийлбэр яг **12** байх ёстой.
  List<int> _row12(Generator g, List<PosColumn> cols) {
    final sum = cols.fold<int>(0, (s, c) => s + c.width);
    if (sum != 12) {
      debugPrint(
        '[BT] ESC/POS row: widths sum=$sum (need 12): ${cols.map((c) => c.width).toList()}',
      );
      throw StateError(
        'Баримтын мөр: баганын өргөний нийлбэр 12 байх ёстой (одоо $sum).',
      );
    }
    return g.row(cols);
  }

  /// Суглааны дугаар үүсгэх (Хувь хүний хувьд) — урьдчилсан харагдах болон хэвлэлтэд ижил формат
  static String generateLotteryNumber() {
    final now = DateTime.now();
    final dateStr = DateFormat('yyyyMMdd').format(now);
    final timeStr = DateFormat('HHmm').format(now);
    final rnd = Random().nextInt(9999).toString().padLeft(4, '0');
    return 'SUG-$dateStr-$timeStr-$rnd';
  }

  /// Print a sales receipt (from SalesItem list)
  /// - Хувь хүн: суглааны дугаар + QR код хэвлэнэ
  /// - Байгуулга: байгуулгийн регистр хэвлэнэ (organizationRegister заавал)
  ///
  /// [useRasterReceipt]: Монгол текстийг widget → PNG → [Generator.image] (код хуудас шаардлагагүй).
  /// [themeContext]: Аппын Theme/MediaQuery өвлүүлэхэд (скриншот илүү тогтвортой).
  Future<bool> printSalesReceipt({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    String? notes,
    String? salesperson,
    String? customerType, // Байгуулга | Хувь хүн
    String? organizationRegister, // Байгуулга сонгосон үед
    String? organizationName, // Байгуулга нэр (TIN-аас)
    /// Худалдагч талын ТТД (заавал биш — [serverShopRegistration] fallback).
    String? merchantTin,

    /// Дэлгүүрийн регистр (сервер) — ТТД placeholder.
    String? serverShopRegistration,

    /// POS `qrData` байвал QR-д илүү зөв.
    String? qrDataFromServer,

    /// Урьдчилсан харагдахтай ижил QR (хувь хүн) — заавал биш
    String? lotteryNumberOverride,
    /// ДДТДХ (Bill ID) — байгуулга дээр хэвлэхэд.
    String? ebarimtBillId,
    BuildContext? themeContext,
    bool useRasterReceipt = true,
  }) async {
    final themeCtx = themeContext;
    _lastPrintError = null;
    if (items.isEmpty) return false;

    final isIndividual = customerType != 'Байгуулга';
    if (isIndividual) {
      final lot = lotteryNumberOverride?.trim() ?? '';
      if (lot.isEmpty) {
        _lastPrintError =
            'Сугалааны дугаар ирээгүй тул хувь хүний баримт хэвлэхгүй.';
        return false;
      }
    }

    if (!await ensureBluetoothPermissions()) {
      _lastPrintError = 'Bluetooth зөвшөөрөл хэрэгтэй.';
      return false;
    }
    if (_connectedMac == null) {
      _lastPrintError =
          'Принтер сонгогдоогүй. Тохиргоо → Bluetooth принтер-ээр холбоно уу.';
      return false;
    }

    final totalAmount =
        items.fold(0.0, (sum, item) => sum + item.receiptLineGross);
    final now = DateTime.now();

    late List<int> bytes;
    final trimmed = lotteryNumberOverride?.trim();
    final hasLottery = trimmed != null && trimmed.isNotEmpty;
    // Хувь хүн: зөвхөн eBarimt/POS-оос ирсэн сугалаа байвал QR хэвлэнэ; хоосон бол санамсаргүй дугаар үүсгэхгүй.
    final lottery = hasLottery ? trimmed : '';
    final printQrIndividual = isIndividual && hasLottery;

    try {
      // themeCtx: зөвхөн скриншотын Theme/MediaQuery-д; дуудагч `mounted` шалгасан байна.
      // ignore: use_build_context_synchronously
      bytes = await _buildSalesReceiptPayload(
        items: items,
        shopName: shopName,
        paymentMethod: paymentMethod,
        totalAmount: totalAmount,
        now: now,
        notes: notes,
        salesperson: salesperson,
        isIndividual: isIndividual,
        organizationRegister: organizationRegister,
        organizationName: organizationName,
        merchantTin: merchantTin,
        ebarimtBillId: ebarimtBillId,
        serverShopRegistration: serverShopRegistration,
        qrDataFromServer: qrDataFromServer,
        lotteryNumber: lottery,
        printQr: printQrIndividual,
        themeContext: themeCtx,
        preferRaster: useRasterReceipt,
      );
    } catch (e, st) {
      debugPrint('[BT] receipt build failed: $e\n$st');
      _lastPrintError = e.toString();
      return false;
    }

    var ok = await _writeWithReconnect(bytes);
    if (!ok && isIndividual) {
      debugPrint(
        '[BT] retrying individual receipt without QR (printer may not support QR)',
      );
      _lastPrintError = null;
      try {
        // ignore: use_build_context_synchronously
        final fallback = await _buildSalesReceiptPayload(
          items: items,
          shopName: shopName,
          paymentMethod: paymentMethod,
          totalAmount: totalAmount,
          now: now,
          notes: notes,
          salesperson: salesperson,
          isIndividual: isIndividual,
          organizationRegister: organizationRegister,
          organizationName: organizationName,
          merchantTin: merchantTin,
          ebarimtBillId: ebarimtBillId,
          serverShopRegistration: serverShopRegistration,
          qrDataFromServer: qrDataFromServer,
          lotteryNumber: lottery,
          printQr: false,
          themeContext: themeCtx,
          preferRaster: useRasterReceipt,
        );
        ok = await _writeWithReconnect(fallback);
      } catch (e, st) {
        debugPrint('[BT] receipt build (no QR) failed: $e\n$st');
        _lastPrintError = e.toString();
        return false;
      }
    }
    if (ok) debugPrint('\u{1F5A8}\u{FE0F} Баримт хэвлэгдлээ');
    return ok;
  }

  /// Эхлээд растер (Монгол зураг), болохгүй бол ESC/POS текст.
  Future<List<int>> _buildSalesReceiptPayload({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    required double totalAmount,
    required DateTime now,
    String? notes,
    String? salesperson,
    required bool isIndividual,
    String? organizationRegister,
    String? organizationName,
    String? merchantTin,
    String? ebarimtBillId,
    String? serverShopRegistration,
    String? qrDataFromServer,
    required String lotteryNumber,
    required bool printQr,
    BuildContext? themeContext,
    bool preferRaster = true,
  }) async {
    if (preferRaster && !kIsWeb) {
      final raster = await _tryBuildSalesReceiptRasterBytes(
        items: items,
        shopName: shopName,
        paymentMethod: paymentMethod,
        totalAmount: totalAmount,
        now: now,
        notes: notes,
        salesperson: salesperson,
        isIndividual: isIndividual,
        organizationRegister: organizationRegister,
        organizationName: organizationName,
        merchantTin: merchantTin,
        ebarimtBillId: ebarimtBillId,
        serverShopRegistration: serverShopRegistration,
        qrDataFromServer: qrDataFromServer,
        lotteryNumber: lotteryNumber,
        printQr: printQr,
        themeContext: themeContext,
      );
      if (raster != null) return raster;
    }
    if (isIndividual) {
      return _buildSalesReceiptBytesWithQR(
        items: items,
        shopName: shopName,
        paymentMethod: paymentMethod,
        totalAmount: totalAmount,
        now: now,
        notes: notes,
        salesperson: salesperson,
        lotteryNumber: lotteryNumber,
        printQr: printQr,
      );
    }
    return _buildSalesReceiptBytesWithOrgRegister(
      items: items,
      shopName: shopName,
      paymentMethod: paymentMethod,
      totalAmount: totalAmount,
      now: now,
      notes: notes,
      salesperson: salesperson,
      organizationRegister: organizationRegister ?? '',
      organizationName: organizationName,
      merchantTin: merchantTin,
      ebarimtBillId: ebarimtBillId,
    );
  }

  Future<List<int>?> _tryBuildSalesReceiptRasterBytes({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    required double totalAmount,
    required DateTime now,
    String? notes,
    String? salesperson,
    required bool isIndividual,
    String? organizationRegister,
    String? organizationName,
    String? merchantTin,
    String? ebarimtBillId,
    String? serverShopRegistration,
    String? qrDataFromServer,
    required String lotteryNumber,
    required bool printQr,
    BuildContext? themeContext,
  }) async {
    try {
      // Raster layout doesn't support billId field today; merchantTin is supported.
      final png = await SalesReceiptRaster.capturePng(
        items: items,
        shopName: shopName,
        paymentMethod: paymentMethod,
        totalAmount: totalAmount,
        now: now,
        notes: notes,
        salesperson: salesperson,
        isOrganization: !isIndividual,
        organizationName: organizationName,
        organizationRegister: organizationRegister,
        merchantTin: merchantTin,
        serverShopRegistration: serverShopRegistration,
        lotteryNumber: isIndividual ? lotteryNumber : null,
        qrDataFromServer: qrDataFromServer,
        includeQr: printQr && isIndividual,
        themeContext: themeContext,
      );
      final decoded = im.decodeImage(png);
      if (decoded == null) {
        debugPrint('[BT] raster: decodeImage returned null');
        return null;
      }
      var toPrint = decoded;
      if (decoded.width != kThermalReceiptWidthPx) {
        toPrint = im.copyResize(
          decoded,
          width: kThermalReceiptWidthPx,
          interpolation: im.Interpolation.linear,
        );
      }
      final profile = await CapabilityProfile.load();
      final generator = Generator(PaperSize.mm58, profile, codec: cp866);
      var out = <int>[];
      out += generator.reset();
      out += generator.image(toPrint, align: PosAlign.center);
      out += generator.feed(4);
      out += generator.cut();
      return out;
    } catch (e, st) {
      debugPrint('[BT] raster receipt build failed: $e\n$st');
      return null;
    }
  }

  Future<List<int>> _buildSalesReceiptBytesWithQR({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    required double totalAmount,
    required DateTime now,
    String? notes,
    String? salesperson,
    required String lotteryNumber,
    bool printQr = true,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile, codec: cp866);
    const line = '--------------------------------';

    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.setGlobalCodeTable('CP866');
    bytes += generator.text('БАРИМТ',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ));
    bytes += generator.text(line);
    bytes += generator.text('Дэлгүүр: $shopName');
    bytes += generator.text(line);
    bytes += generator.text('БАРАА', styles: PosStyles(bold: true));

    for (final item in items) {
      bytes += generator.text(item.productName);
      bytes += _row12(generator, [
        PosColumn(
          text:
              '${item.paidQuantity} x ${item.receiptUnitGross.toStringAsFixed(0)}',
          width: 6,
        ),
        PosColumn(
          text: '${item.receiptLineGross.toStringAsFixed(0)} T',
          width: 6,
          styles: PosStyles(align: PosAlign.right),
        ),
      ]);
      if (item.freeQuantity > 0) {
        bytes += _row12(generator, [
          PosColumn(
            text:
                '${item.freeQuantity} x 0 (1+1 \u04af\u043d\u044d\u0433\u04af\u0439)',
            width: 6,
          ),
          PosColumn(
            text: '0 T',
            width: 6,
            styles: PosStyles(align: PosAlign.right),
          ),
        ]);
      }
    }

    bytes += generator.text(line);
    bytes += _row12(generator, [
      PosColumn(text: 'НИЙТ:', width: 6, styles: PosStyles(bold: true)),
      PosColumn(
        text: '${totalAmount.toStringAsFixed(0)} T',
        width: 6,
        styles: PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    final vatBr = ReceiptVatFromGross.fromGrossTotal(totalAmount);
    bytes += _row12(generator, [
      PosColumn(text: '\u041d\u04e8\u0410\u0422 10%:', width: 6),
      PosColumn(
        text: '${vatBr.vatAmount.toStringAsFixed(0)} T',
        width: 6,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += _row12(generator, [
      PosColumn(text: '\u0426\u044d\u0432\u044d\u0440:', width: 6),
      PosColumn(
        text: '${vatBr.netAmount.toStringAsFixed(0)} T',
        width: 6,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.text(
        '(\u043d\u0438\u0439\u0442=\u041d\u04e8\u0410\u0422 \u043e\u0440\u0441\u043e\u043d)');
    bytes += generator.text(line);
    bytes += generator.text('Төлбөр: $paymentMethod');
    bytes += generator.text('Төрөл: Хувь хүн');
    if (salesperson != null) bytes += generator.text('Худалдагч: $salesperson');
    if (notes != null && notes.isNotEmpty)
      bytes += generator.text('Тэмдэглэл: $notes');
    bytes += generator.text('Огноо: ${now.toString().split('.')[0]}');
    bytes += generator.text('');
    bytes += generator.text('Суглааны дугаар: $lotteryNumber',
        styles: PosStyles(bold: true));
    if (printQr) {
      bytes += generator.qrcode(
        lotteryNumber,
        size: QRSize.size3,
        cor: QRCorrection.L,
      );
    } else {
      bytes += generator.text(
        lotteryNumber,
        styles: PosStyles(align: PosAlign.center, bold: true),
      );
      bytes += generator.text(
        '(QR дэмжихгүй принтер — дугаар текстээр)',
        styles: PosStyles(align: PosAlign.center),
      );
    }
    bytes += generator.text('');
    bytes +=
        generator.text('Баярлалаа!', styles: PosStyles(align: PosAlign.center));
    bytes += generator.feed(4);
    bytes += generator.cut();

    return bytes;
  }

  Future<List<int>> _buildSalesReceiptBytesWithOrgRegister({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    required double totalAmount,
    required DateTime now,
    String? notes,
    String? salesperson,
    required String organizationRegister,
    String? organizationName,
    String? merchantTin,
    String? ebarimtBillId,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile, codec: cp866);
    const line = '--------------------------------';

    List<int> bytes = [];
    bytes += generator.reset();
    bytes += generator.setGlobalCodeTable('CP866');
    bytes += generator.text('БАРИМТ',
        styles: PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ));
    bytes += generator.text(line);
    bytes += generator.text('Дэлгүүр: $shopName');
    bytes += generator.text(line);
    bytes += generator.text('БАРАА', styles: PosStyles(bold: true));

    for (final item in items) {
      bytes += generator.text(item.productName);
      bytes += _row12(generator, [
        PosColumn(
          text:
              '${item.paidQuantity} x ${item.receiptUnitGross.toStringAsFixed(0)}',
          width: 6,
        ),
        PosColumn(
          text: '${item.receiptLineGross.toStringAsFixed(0)} T',
          width: 6,
          styles: PosStyles(align: PosAlign.right),
        ),
      ]);
      if (item.freeQuantity > 0) {
        bytes += _row12(generator, [
          PosColumn(
            text:
                '${item.freeQuantity} x 0 (1+1 \u04af\u043d\u044d\u0433\u04af\u0439)',
            width: 6,
          ),
          PosColumn(
            text: '0 T',
            width: 6,
            styles: PosStyles(align: PosAlign.right),
          ),
        ]);
      }
    }

    bytes += generator.text(line);
    bytes += _row12(generator, [
      PosColumn(text: 'НИЙТ:', width: 6, styles: PosStyles(bold: true)),
      PosColumn(
        text: '${totalAmount.toStringAsFixed(0)} T',
        width: 6,
        styles: PosStyles(bold: true, align: PosAlign.right),
      ),
    ]);
    final vatBrOrg = ReceiptVatFromGross.fromGrossTotal(totalAmount);
    bytes += _row12(generator, [
      PosColumn(text: '\u041d\u04e8\u0410\u0422 10%:', width: 6),
      PosColumn(
        text: '${vatBrOrg.vatAmount.toStringAsFixed(0)} T',
        width: 6,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += _row12(generator, [
      PosColumn(text: '\u0426\u044d\u0432\u044d\u0440:', width: 6),
      PosColumn(
        text: '${vatBrOrg.netAmount.toStringAsFixed(0)} T',
        width: 6,
        styles: PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.text(
        '(\u043d\u0438\u0439\u0442=\u041d\u04e8\u0410\u0422 \u043e\u0440\u0441\u043e\u043d)');
    bytes += generator.text(line);
    bytes += generator.text('Төлбөр: $paymentMethod');
    bytes += generator.text('Төрөл: Байгуулга');
    final mt = (merchantTin ?? '').trim();
    if (mt.isNotEmpty) {
      bytes += generator.text('ТТД: $mt', styles: PosStyles(bold: true));
    }
    final bid = (ebarimtBillId ?? '').trim();
    if (bid.isNotEmpty) {
      bytes += generator.text('ДДТДХ: $bid', styles: PosStyles(bold: true));
    }
    if (organizationName != null && organizationName.trim().isNotEmpty) {
      bytes += generator.text(
        'Байгууллага: ${organizationName.trim()}',
        styles: PosStyles(bold: true),
      );
    }
    bytes += generator.text('Регистр: $organizationRegister',
        styles: PosStyles(bold: true));
    if (salesperson != null) bytes += generator.text('Худалдагч: $salesperson');
    if (notes != null && notes.isNotEmpty)
      bytes += generator.text('Тэмдэглэл: $notes');
    bytes += generator.text('Огноо: ${now.toString().split('.')[0]}');
    bytes += generator.text('');
    bytes +=
        generator.text('Баярлалаа!', styles: PosStyles(align: PosAlign.center));
    bytes += generator.feed(4);
    bytes += generator.cut();

    return bytes;
  }

  /// Print an order receipt (from Order model)
  Future<bool> printOrderReceipt(Order order) async {
    _lastPrintError = null;
    if (!await ensureBluetoothPermissions()) {
      _lastPrintError = 'Bluetooth зөвшөөрөл хэрэгтэй.';
      return false;
    }
    if (_connectedMac == null) {
      _lastPrintError =
          'Принтер сонгогдоогүй. Тохиргооноос Bluetooth принтер холбоно уу.';
      return false;
    }

    final profile = await CapabilityProfile.load();
    final cp866Id = profile.getCodePageId('CP866');

    const w = 32;

    final orderVat = ReceiptVatFromGross.fromGrossTotal(order.totalAmount);

    final bytes = <int>[
      ..._cmdInit(),
      0x1B, 0x74, cp866Id,
      // Header
      ..._cmdAlign(1),
      ..._cmdBold(true),
      ..._cmdDoubleSize(true),
      ..._textBytes('ЗАХИАЛГА'),
      ..._cmdDoubleSize(false),
      ..._cmdBold(false),
      ..._cmdAlign(0),
      ..._cmdLine(w),
      ..._textBytes('Огноо: ${order.orderDate.toString().split('.')[0]}'),
      ..._textBytes('Дэлгүүр: ${order.customerName}'),
      if (order.customerPhone.trim().isNotEmpty)
        ..._textBytes('Утас: ${order.customerPhone}'),
      if (order.customerAddress.trim().isNotEmpty)
        ..._textBytes('Хаяг: ${order.customerAddress}'),
      ..._cmdLine(w),
      ..._cmdBold(true),
      ..._textBytes('БҮТЭЭГДЭХҮҮН'),
      ..._cmdBold(false),
    ];

    for (final item in order.items) {
      bytes.addAll(_textBytes(item.productName));
      bytes.addAll(_twoColumnLine(
        '${item.quantity} x ${item.unitPrice.toStringAsFixed(0)}',
        '${item.totalPrice.toStringAsFixed(0)} T',
        w,
      ));
    }

    bytes.addAll([
      ..._cmdLine(w),
      ..._cmdBold(true),
      ..._twoColumnLine(
          'НИЙТ:', '${order.totalAmount.toStringAsFixed(0)} T', w),
      ..._cmdBold(false),
      ..._twoColumnLine(
        '\u041d\u04e8\u0410\u0422 10%:',
        '${orderVat.vatAmount.toStringAsFixed(0)} T',
        w,
      ),
      ..._twoColumnLine(
        '\u0426\u044d\u0432\u044d\u0440:',
        '${orderVat.netAmount.toStringAsFixed(0)} T',
        w,
      ),
      ..._textBytes(
        '(\u043d\u0438\u0439\u0442=\u041d\u04e8\u0410\u0422 \u043e\u0440\u0441\u043e\u043d)',
      ),
      if (order.notes != null && order.notes!.trim().isNotEmpty) ...[
        ..._cmdLine(w),
        ..._textBytes('Тэмдэглэл: ${order.notes!.trim()}'),
      ],
      ..._cmdLine(w),
      ..._textBytes('Худалдагч: ${order.salespersonName}'),
      ..._cmdAlign(1),
      ..._textBytes('Баярлалаа!'),
      ..._cmdAlign(0),
      ..._cmdFeedLines(4),
      ..._cmdCut(),
    ]);

    final ok = await _writeWithReconnect(bytes);
    if (ok) debugPrint('\u{1F5A8}\u{FE0F} Захиалгын баримт хэвлэгдлээ');
    return ok;
  }
}
