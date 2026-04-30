import 'package:flutter/material.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import '../services/bluetooth_printer_service.dart';

/// Dialog for selecting and connecting to a Bluetooth thermal printer.
class BluetoothPrinterDialog extends StatefulWidget {
  const BluetoothPrinterDialog({super.key});

  /// Show the dialog and return true if a printer was connected successfully.
  static Future<bool?> show(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (_) => const BluetoothPrinterDialog(),
    );
  }

  @override
  State<BluetoothPrinterDialog> createState() => _BluetoothPrinterDialogState();
}

class _BluetoothPrinterDialogState extends State<BluetoothPrinterDialog> {
  final _printer = BluetoothPrinterService();
  List<BluetoothInfo> _devices = [];
  bool _scanning = false;
  bool _connecting = false;
  String? _connectingMac;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scanDevices();
  }

  Future<void> _scanDevices() async {
    setState(() {
      _scanning = true;
      _error = null;
    });

    final permitted = await _printer.ensureBluetoothPermissions();
    if (!permitted) {
      if (mounted) {
        setState(() {
          _scanning = false;
          _error =
              'Bluetooth зөвшөөрөл хэрэгтэй.\n\nТохиргоо → Програм → Aguulga Business → Зөвшөөрөл → «Ойролцоох төхөөрөмж» (эсвэл Bluetooth)-ийг зөвшөөрнө үү.';
        });
      }
      return;
    }

    final btAvailable = await _printer.isBluetoothAvailable();
    if (!btAvailable) {
      setState(() {
        _scanning = false;
        _error =
            'Bluetooth асаагүй байна.\nТохиргооноос Bluetooth-г асаана уу.';
      });
      return;
    }

    final devices = await _printer.getPairedDevices();
    if (mounted) {
      setState(() {
        _devices = devices;
        _scanning = false;
        if (devices.isEmpty) {
          _error =
              'Хослуулсан Bluetooth төхөөрөмж олдсонгүй.\n\nУтасны Bluetooth тохиргооноос принтерээ хослуулна уу.';
        }
      });
    }
  }

  Future<void> _connectToDevice(BluetoothInfo device) async {
    setState(() {
      _connecting = true;
      _connectingMac = device.macAdress;
      _error = null;
    });

    final success = await _printer.connect(
      device.macAdress,
      name: device.name,
    );

    if (mounted) {
      setState(() {
        _connecting = false;
        _connectingMac = null;
      });

      if (success) {
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('🖨️ ${device.name} холбогдлоо!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        final detail = _printer.lastConnectError?.trim();
        setState(() {
          _error = '«${device.name}» руу холбогдож чадсангүй.\n\n'
              '${detail != null && detail.isNotEmpty ? 'Техник: $detail\n\n' : ''}'
              'Шалгах зүйлс:\n'
              '• Принтер асаалттай, цаас байгаа эсэх\n'
              '• Утас, принтер хоёр ойрхон (1–2 м)\n'
              '• Зөвхөн термаль/Receipt принтер сонгоно (чихэвч, ТВ ихэвчлэн хэвлэхгүй)\n'
              '• Өөр утас/програм түүнтэй Bluetooth-оор холбогдсон бол тэр холболтыг салгана\n'
              '• Bluetooth тохиргооноос хослолтыг устгаад дахин хослуулж, энэ цонхноос «Дахин хайх» дарна уу\n'
              '• Дахин дарж 2–3 удаа туршаад үзнэ үү';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.print, color: Colors.blue, size: 28),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Bluetooth Принтер',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          if (_printer.isConnected)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'Холбоотой',
                style: TextStyle(
                    fontSize: 11,
                    color: Colors.green,
                    fontWeight: FontWeight.w600),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Connected printer info
            if (_printer.isConnected) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.check_circle,
                        color: Colors.green, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _printer.connectedPrinterName ?? 'Принтер',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    TextButton(
                      onPressed: () async {
                        await _printer.disconnect();
                        await _printer.forgetSavedPrinter();
                        setState(() {});
                      },
                      child: const Text('Салгах',
                          style: TextStyle(color: Colors.red)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Error message
            if (_error != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.warning_amber,
                        color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: TextStyle(
                            fontSize: 13, color: Colors.orange.shade900),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // Scanning indicator
            if (_scanning) ...[
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Column(
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 12),
                    Text('Төхөөрөмж хайж байна...'),
                  ],
                ),
              ),
            ] else ...[
              // Device list
              if (_devices.isNotEmpty) ...[
                const Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Хослуулсан төхөөрөмжүүд:',
                    style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey,
                        fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 250),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _devices.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (ctx, i) {
                      final device = _devices[i];
                      final isConnecting =
                          _connecting && _connectingMac == device.macAdress;
                      final isCurrentlyConnected = _printer.isConnected &&
                          _printer.connectedPrinterName == device.name;

                      return ListTile(
                        dense: true,
                        leading: Icon(
                          isCurrentlyConnected ? Icons.print : Icons.bluetooth,
                          color:
                              isCurrentlyConnected ? Colors.green : Colors.blue,
                        ),
                        title: Text(
                          device.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          device.macAdress,
                          style: const TextStyle(fontSize: 11),
                        ),
                        trailing: isConnecting
                            ? const SizedBox(
                                width: 24,
                                height: 24,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : isCurrentlyConnected
                                ? const Icon(Icons.check_circle,
                                    color: Colors.green, size: 20)
                                : const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: isConnecting
                            ? null
                            : () => _connectToDevice(device),
                      );
                    },
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: _scanning ? null : _scanDevices,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Дахин хайх'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Хаах'),
        ),
      ],
    );
  }
}
