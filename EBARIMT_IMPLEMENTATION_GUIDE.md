# Ebarimt 3.0 POS Integration - Implementation Guide

## 📦 Хийгдсэн зүйлс

### ✅ Flutter Services
1. **PosPrinterService** (`lib/services/pos_printer_service.dart`)
   - USB/Bluetooth/WiFi printer холболт
   - ESC/POS командууд илгээх
   - Native bridge ашиглах

2. **ReceiptService** (`lib/services/receipt_service.dart`)
   - Баримт текст үүсгэх
   - ESC/POS командууд үүсгэх
   - Монгол фонт дэмжлэг (image-based)

3. **ReceiptQueueService** (`lib/services/receipt_queue_service.dart`)
   - Offline queue хадгалах (Hive)
   - Synced/Unsynced баримтуудыг удирдах

4. **EbarimtApiService** (`lib/services/ebarimt_api_service.dart`)
   - Backend middleware-р дамжуулан Ebarimt API дуудах
   - Баримт илгээх, статус шалгах

5. **ReceiptSyncService** (`lib/services/receipt_sync_service.dart`)
   - Auto sync (30 секунд тутамд)
   - Synced бус баримтуудыг автоматаар илгээх

### ✅ Backend Middleware
1. **Ebarimt Routes** (`backend/routes/ebarimt.js`)
   - Баримт илгээх endpoint
   - Баримт статус шалгах endpoint
   - Request signing (Ebarimt 3.0 протокол)
   - TLS 1.3 дэмжлэг

### ✅ Native Android Bridge
1. **PosPrinterPlugin** (`android/app/src/main/kotlin/.../PosPrinterPlugin.kt`)
   - Bluetooth printer холболт
   - WiFi printer холболт
   - USB Serial (хэрэгжүүлэх шаардлагатай)
   - ESC/POS командууд илгээх

## 🔧 Тохируулах

### 1. Flutter Dependencies

```bash
flutter pub get
```

### 2. Hive Initialize

`main.dart` файлд:

```dart
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  runApp(MyApp());
}
```

### 3. Native Android Bridge Register

`MainActivity.kt` файлд:

```kotlin
import com.example.aguulgav3.PosPrinterPlugin

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(PosPrinterPlugin())
    }
}
```

### 4. Android Permissions

`AndroidManifest.xml` файлд:

```xml
<uses-permission android:name="android.permission.BLUETOOTH" />
<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />
<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />
<uses-permission android:name="android.permission.INTERNET" />
```

### 5. Backend Environment Variables

`.env` файл үүсгэх:

```env
EBARIMT_API_URL=https://api.ebarimt.mn/v3
EBARIMT_API_KEY=your_api_key_here
EBARIMT_SECRET_KEY=your_secret_key_here
```

## 📝 Ашиглах жишээ

### Баримт хэвлэх

```dart
import 'package:aguulgav3/services/receipt_service.dart';
import 'package:aguulgav3/services/receipt_queue_service.dart';
import 'package:aguulgav3/services/receipt_sync_service.dart';

final receiptService = ReceiptService();
final queueService = ReceiptQueueService();
final syncService = ReceiptSyncService();

// Queue service initialize
await queueService.init();

// Баримт хэвлэх
final success = await receiptService.printReceipt(
  companyName: 'Миний Дэлгүүр',
  registrationNumber: '12345678',
  address: 'Улаанбаатар хот',
  phone: '99112233',
  items: [
    ReceiptItem(name: 'Бараа 1', quantity: 2, price: 10000),
    ReceiptItem(name: 'Бараа 2', quantity: 1, price: 5000),
  ],
  total: 25000,
  vat: 2500,
  receiptNumber: 'RCP-001',
  dateTime: DateTime.now(),
);

// Хэрэв хэвлэх амжилттай бол queue-д нэмэх
if (success) {
  final receipt = QueuedReceipt(
    receiptNumber: 'RCP-001',
    companyName: 'Миний Дэлгүүр',
    registrationNumber: '12345678',
    address: 'Улаанбаатар хот',
    phone: '99112233',
    items: [
      {'name': 'Бараа 1', 'quantity': 2, 'price': 10000},
      {'name': 'Бараа 2', 'quantity': 1, 'price': 5000},
    ],
    total: 25000,
    vat: 2500,
    dateTime: DateTime.now(),
  );
  
  await queueService.addToQueue(receipt);
}

// Auto sync эхлүүлэх
syncService.startAutoSync();
```

## ⚠️ Чухал тэмдэглэл

1. **USB Serial**: USB Serial холболт хараахан бүрэн хэрэгжүүлээгүй. `usb-serial-for-android` library ашиглах хэрэгтэй.

2. **Монгол фонт**: ESC/POS командууд UTF-8 дэмждэггүй тохиолдолд image-based printing ашиглах хэрэгтэй.

3. **Ebarimt API**: Шууд Flutter-аас дуудах боломжгүй. Backend middleware заавал шаардлагатай.

4. **Token Management**: Backend middleware дээр token авах/сэргээх механизм нэмэх хэрэгтэй.

## 🔄 Дараагийн алхмууд

1. ✅ Flutter services хийгдсэн
2. ✅ Backend middleware хийгдсэн
3. ✅ Native Android bridge хийгдсэн
4. ⏳ USB Serial library integration
5. ⏳ Image-based printing (Монгол фонт)
6. ⏳ Token management (Backend)
7. ⏳ UI integration

## 📚 Нэмэлт мэдээлэл

- [ESC/POS Command Reference](https://reference.epson-biz.com/)
- [Ebarimt 3.0 API Documentation](https://ebarimt.mn/docs)
- [Flutter Native Bridge](https://docs.flutter.dev/development/platform-integration/platform-channels)



