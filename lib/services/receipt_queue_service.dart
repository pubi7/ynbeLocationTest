import 'package:hive/hive.dart';
import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';

/// Receipt Queue Service - Offline queue хадгалах
///
/// Интернэт холболт байхгүй үед баримтуудыг queue-д хадгална
/// Интернэт гармагц автоматаар Ebarimt сервер рүү илгээнэ
@HiveType(typeId: 0)
class QueuedReceipt extends HiveObject {
  @HiveField(0)
  final String receiptNumber;

  @HiveField(1)
  final String companyName;

  @HiveField(2)
  final String registrationNumber;

  @HiveField(3)
  final String address;

  @HiveField(4)
  final String phone;

  @HiveField(5)
  final List<Map<String, dynamic>> items;

  @HiveField(6)
  final double total;

  @HiveField(7)
  final double vat;

  @HiveField(8)
  final DateTime dateTime;

  @HiveField(9)
  final DateTime createdAt;

  @HiveField(10)
  bool isSynced;

  @HiveField(11)
  String? errorMessage;

  QueuedReceipt({
    required this.receiptNumber,
    required this.companyName,
    required this.registrationNumber,
    required this.address,
    required this.phone,
    required this.items,
    required this.total,
    required this.vat,
    required this.dateTime,
    DateTime? createdAt,
    this.isSynced = false,
    this.errorMessage,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'receiptNumber': receiptNumber,
      'companyName': companyName,
      'registrationNumber': registrationNumber,
      'address': address,
      'phone': phone,
      'items': items,
      'total': total,
      'vat': vat,
      'dateTime': dateTime.toIso8601String(),
    };
  }
}

/// Receipt Queue Service
class ReceiptQueueService {
  static const String _boxName = 'receipt_queue';
  Box<QueuedReceipt>? _box;
  static bool _hiveInitialized = false;

  /// Initialize Hive box
  Future<void> init() async {
    if (!_hiveInitialized) {
      await Hive.initFlutter();
      _hiveInitialized = true;
    }
    if (!Hive.isAdapterRegistered(0)) {
      Hive.registerAdapter(QueuedReceiptAdapter());
    }
    _box = await Hive.openBox<QueuedReceipt>(_boxName);
  }

  /// Баримт queue-д нэмэх
  Future<void> addToQueue(QueuedReceipt receipt) async {
    try {
      await _box?.put(receipt.receiptNumber, receipt);
      debugPrint('✅ Баримт queue-д нэмэгдлээ: ${receipt.receiptNumber}');
    } catch (e) {
      debugPrint('❌ Queue-д нэмэх алдаа: $e');
    }
  }

  /// Queue-д байгаа баримтуудыг авах
  List<QueuedReceipt> getQueuedReceipts() {
    return _box?.values.toList() ?? [];
  }

  /// Synced бус баримтуудыг авах
  List<QueuedReceipt> getUnsyncedReceipts() {
    return _box?.values.where((r) => !r.isSynced).toList() ?? [];
  }

  /// Баримт synced гэж тэмдэглэх
  Future<void> markAsSynced(String receiptNumber) async {
    try {
      final receipt = _box?.get(receiptNumber);
      if (receipt != null) {
        receipt.isSynced = true;
        receipt.errorMessage = null;
        await receipt.save();
        debugPrint('✅ Баримт synced гэж тэмдэглэгдлээ: $receiptNumber');
      }
    } catch (e) {
      debugPrint('❌ Synced тэмдэглэх алдаа: $e');
    }
  }

  /// Баримт алдаатай гэж тэмдэглэх
  Future<void> markAsError(String receiptNumber, String errorMessage) async {
    try {
      final receipt = _box?.get(receiptNumber);
      if (receipt != null) {
        receipt.errorMessage = errorMessage;
        await receipt.save();
        debugPrint(
            '❌ Баримт алдаатай гэж тэмдэглэгдлээ: $receiptNumber - $errorMessage');
      }
    } catch (e) {
      debugPrint('❌ Алдаа тэмдэглэх алдаа: $e');
    }
  }

  /// Queue-аас баримт устгах
  Future<void> removeFromQueue(String receiptNumber) async {
    try {
      await _box?.delete(receiptNumber);
      debugPrint('✅ Баримт queue-аас устгагдлаа: $receiptNumber');
    } catch (e) {
      debugPrint('❌ Queue-аас устгах алдаа: $e');
    }
  }

  /// Queue-ийг цэвэрлэх (synced баримтуудыг устгах)
  Future<void> clearSyncedReceipts() async {
    try {
      final syncedReceipts =
          _box?.values.where((r) => r.isSynced).toList() ?? [];
      for (final receipt in syncedReceipts) {
        await receipt.delete();
      }
      debugPrint('✅ Synced баримтууд устгагдлаа: ${syncedReceipts.length}');
    } catch (e) {
      debugPrint('❌ Queue цэвэрлэх алдаа: $e');
    }
  }
}

/// Hive Adapter for QueuedReceipt
class QueuedReceiptAdapter extends TypeAdapter<QueuedReceipt> {
  @override
  final int typeId = 0;

  @override
  QueuedReceipt read(BinaryReader reader) {
    return QueuedReceipt(
      receiptNumber: reader.readString(),
      companyName: reader.readString(),
      registrationNumber: reader.readString(),
      address: reader.readString(),
      phone: reader.readString(),
      items: List<Map<String, dynamic>>.from(reader.read()),
      total: reader.readDouble(),
      vat: reader.readDouble(),
      dateTime: DateTime.parse(reader.readString()),
      createdAt: DateTime.parse(reader.readString()),
      isSynced: reader.readBool(),
      errorMessage: reader.readString(),
    );
  }

  @override
  void write(BinaryWriter writer, QueuedReceipt obj) {
    writer.writeString(obj.receiptNumber);
    writer.writeString(obj.companyName);
    writer.writeString(obj.registrationNumber);
    writer.writeString(obj.address);
    writer.writeString(obj.phone);
    writer.write(obj.items);
    writer.writeDouble(obj.total);
    writer.writeDouble(obj.vat);
    writer.writeString(obj.dateTime.toIso8601String());
    writer.writeString(obj.createdAt.toIso8601String());
    writer.writeBool(obj.isSynced);
    writer.writeString(obj.errorMessage ?? '');
  }
}
