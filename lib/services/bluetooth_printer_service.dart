import 'package:flutter/foundation.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../models/order_model.dart';
import '../models/sales_item_model.dart';

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

  /// Currently connected printer name
  String? get connectedPrinterName => _connectedName;

  /// Whether a printer is currently connected
  bool get isConnected => _connectedMac != null;

  // ─── Connection ──────────────────────────────────────────────

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
    try {
      // Disconnect existing connection first
      if (_connectedMac != null) {
        await disconnect();
      }

      final connected =
          await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
      if (connected) {
        _connectedMac = macAddress;
        _connectedName = name;
        debugPrint('🖨️ BT принтер холбогдлоо: $name ($macAddress)');
      } else {
        debugPrint('❌ BT принтер холбогдож чадсангүй: $macAddress');
      }
      return connected;
    } catch (e) {
      debugPrint('🔵 BT connect error: $e');
      return false;
    }
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

  /// Encode text to bytes (ASCII + simple Cyrillic fallback)
  List<int> _textBytes(String text) {
    // Try to use codepage for Cyrillic. Most thermal printers only
    // support ASCII well. We transliterate Mongolian Cyrillic to
    // approximate Latin characters when the printer can't handle it.
    final bytes = <int>[];
    for (final char in text.runes) {
      if (char < 128) {
        bytes.add(char);
      } else {
        // For Cyrillic, send as UTF-8 (some modern printers support it)
        final utf8Bytes = String.fromCharCode(char).codeUnits;
        bytes.addAll(utf8Bytes);
      }
    }
    bytes.add(0x0A); // newline
    return bytes;
  }

  /// Build a formatted line: left-aligned text + right-aligned text
  List<int> _twoColumnLine(String left, String right, int width) {
    final spaces = width - left.length - right.length;
    final line = spaces > 0
        ? '$left${' ' * spaces}$right'
        : '$left $right';
    return _textBytes(line);
  }

  // ─── Receipt Printing ─────────────────────────────────────────

  /// Print a sales receipt (from SalesItem list)
  Future<bool> printSalesReceipt({
    required List<SalesItem> items,
    required String shopName,
    required String paymentMethod,
    String? notes,
    String? salesperson,
  }) async {
    if (items.isEmpty) return false;

    final connected = await checkConnection();
    if (!connected) {
      debugPrint('❌ Принтер холбогдоогүй байна');
      return false;
    }

    final totalAmount = items.fold(0.0, (sum, item) => sum + item.total);
    final now = DateTime.now();
    const w = 32; // 58mm ≈ 32 chars, 80mm ≈ 48 chars

    final bytes = <int>[
      ..._cmdInit(),
      // Header
      ..._cmdAlign(1), // center
      ..._cmdBold(true),
      ..._cmdDoubleSize(true),
      ..._textBytes('БАРИМТ'),
      ..._cmdDoubleSize(false),
      ..._cmdBold(false),
      ..._cmdAlign(0), // left
      ..._cmdLine(w),
      ..._textBytes('Дэлгүүр: $shopName'),
      ..._cmdLine(w),
      // Items
      ..._cmdBold(true),
      ..._textBytes('БАРАА'),
      ..._cmdBold(false),
    ];

    for (final item in items) {
      bytes.addAll(_textBytes(item.productName));
      bytes.addAll(_twoColumnLine(
        '${item.quantity} x ${item.price.toStringAsFixed(0)}',
        '${item.total.toStringAsFixed(0)} T',
        w,
      ));
    }

    bytes.addAll([
      ..._cmdLine(w),
      ..._cmdBold(true),
      ..._twoColumnLine('НИЙТ:', '${totalAmount.toStringAsFixed(0)} T', w),
      ..._cmdBold(false),
      ..._cmdLine(w),
      ..._textBytes('Төлбөр: $paymentMethod'),
      if (salesperson != null) ..._textBytes('Худалдагч: $salesperson'),
      if (notes != null && notes.isNotEmpty) ..._textBytes('Тэмдэглэл: $notes'),
      ..._textBytes('Огноо: ${now.toString().split('.')[0]}'),
      ..._cmdAlign(1),
      ..._textBytes('Баярлалаа!'),
      ..._cmdAlign(0),
      ..._cmdFeedLines(4),
      ..._cmdCut(),
    ]);

    try {
      final result = await PrintBluetoothThermal.writeBytes(bytes);
      debugPrint('🖨️ Баримт хэвлэгдлээ: $result');
      return result;
    } catch (e) {
      debugPrint('❌ Хэвлэх алдаа: $e');
      return false;
    }
  }

  /// Print an order receipt (from Order model)
  Future<bool> printOrderReceipt(Order order) async {
    final connected = await checkConnection();
    if (!connected) {
      debugPrint('❌ Принтер холбогдоогүй байна');
      return false;
    }

    const w = 32;

    final bytes = <int>[
      ..._cmdInit(),
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

    try {
      final result = await PrintBluetoothThermal.writeBytes(bytes);
      debugPrint('🖨️ Захиалгын баримт хэвлэгдлээ: $result');
      return result;
    } catch (e) {
      debugPrint('❌ Хэвлэх алдаа: $e');
      return false;
    }
  }
}
