# Идэвхгүй Барааны Дэмжлэг

## ✅ Хийсэн Өөрчлөлтүүд

### 1. Product Model Дээр `isActive` Талбар Нэмсэн

**`lib/models/product_model.dart`:**
- `isActive` талбар нэмсэн (bool?, optional)
- Default утга: `true` (хэрэв backend-аас ирэхгүй бол)

### 2. Backend Response-аас `isActive` Талбарыг Extract Хийх

**`lib/services/warehouse_web_bridge.dart`:**
- `_extractProductMaps()` функц дээр `isActive` талбарыг extract хийнэ
- `isActive` эсвэл `active` талбарыг шалгана

### 3. `fetchAllProducts()` Методод `includeInactive` Параметр Нэмсэн

**Өмнө:**
```dart
Future<List<Product>> fetchAllProducts({int pageSize = 200})
```

**Одоо:**
```dart
Future<List<Product>> fetchAllProducts({
  int pageSize = 200,
  bool includeInactive = true, // Default: include inactive products
})
```

### 4. Идэвхгүй Барааг Шүүх Логик

**`fetchAllProducts()` дээр:**
- `includeInactive = true` бол бүх бараа (идэвхтэй + идэвхгүй)
- `includeInactive = false` бол зөвхөн идэвхтэй бараа

### 5. `getProductsForSale()` Методод Идэвхгүй Барааг Шүүх

**`getProductsForSale()` дээр:**
- Default: `includeInactive = false` (зөвхөн идэвхтэй бараа худалдаанд)
- Идэвхгүй барааг автоматаар шүүнэ

### 6. Backend API Дээр `includeInactive` Параметр Дэмжлэг

**`server.js`:**
- `includeInactive` query parameter дэмжинэ
- Weve API руу `isActive: true` параметр илгээх эсэхийг шалгана

## 🔄 Ажиллах Механизм

### 1. Бүх Бараа Татах (Идэвхгүй Орно):

```dart
final products = await warehouseProvider.refreshProducts();
// Бүх бараа (идэвхтэй + идэвхгүй)
```

### 2. Зөвхөн Идэвхтэй Бараа Татах:

```dart
final products = await _bridge.fetchAllProducts(includeInactive: false);
// Зөвхөн идэвхтэй бараа
```

### 3. Худалдаанд Зориулсан Бараа:

```dart
final products = await _bridge.getProductsForSale();
// Зөвхөн идэвхтэй, үнэтэй, бараатай бараа
```

## 📊 Логууд

### Идэвхгүй Бараатай:

```
[WebBridge] 🚀 Starting product fetch (pageSize: 200, includeInactive: true)
[WebBridge] ✅ Successfully fetched 10 total products from 1 pages
[WebBridge] 📊 Product summary: 10 total, 8 with prices, 8 active, 2 inactive
```

### Идэвхгүй Барааг Шүүсэн:

```
[WebBridge] 🚀 Starting product fetch (pageSize: 200, includeInactive: false)
[WebBridge] ✅ Successfully fetched 8 total products from 1 pages
[WebBridge] 📊 Product summary: 8 total, 8 with prices, 8 active, 0 inactive
[WebBridge] ⚠️ Filtered out 2 inactive products
```

## 🎯 Ашиглах

### Settings Screen Дээр:

Одоогийн байдлаар бүх бараа татагдана (идэвхтэй + идэвхгүй). Хэрэв зөвхөн идэвхтэй бараа харагдахыг хүсвэл:

**`lib/providers/warehouse_provider.dart` дээр:**
```dart
_products = await _bridge.fetchAllProducts(includeInactive: false);
```

### Sales Entry Screen Дээр:

`getProductsForSale()` нь автоматаар идэвхгүй барааг шүүнэ, тиймээс зөвхөн идэвхтэй бараа харагдана.

## ⚠️ Чухал

1. **Default утга:** `includeInactive = true` (backward compatibility-ийн тулд)
2. **Худалдаанд:** `getProductsForSale()` нь автоматаар идэвхгүй барааг шүүнэ
3. **Backend:** Weve API-аас идэвхгүй бараа ирэх эсэх нь backend-ийн тохиргооноос хамаарна

## 📝 Дараагийн Алхам

1. ✅ Product model дээр `isActive` талбар нэмсэн
2. ✅ Backend response-аас `isActive` extract хийнэ
3. ✅ `fetchAllProducts()` дээр `includeInactive` параметр нэмсэн
4. ✅ `getProductsForSale()` дээр идэвхгүй барааг шүүнэ
5. ⏳ Backend серверийг дахин эхлүүлэх (шинэчилсэн `server.js` ашиглах)

Одоо идэвхгүй барааны дэмжлэг нэмэгдсэн. Хэрэв backend-аас `isActive: false` гэсэн бараа ирвэл тэдгээрийг шүүж болно.
