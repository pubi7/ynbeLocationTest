# Бараа Ачаалагдаж Байгаа Эсэхийг Хэрхэн Шалгах

## 🔍 Шалгах Арга

### 1. Settings Screen Дээр Шалгах

**Settings screen дээр:**

1. **Settings** screen руу орох
2. **"Warehouse Web Sync"** хэсгийг харах
3. Дараах мэдээлэл харагдах ёстой:

```
✅ Connected (read-only)
API: http://192.168.1.6:3000/api/
Products: 6 | Shops: 2
```

**Энд:**
- `Products: 6` - Барааны тоо (6 гэсэн тоо харагдах ёстой)
- `Shops: 2` - Дэлгүүрийн тоо

**Хэрэв бараа ачаалагдаагүй бол:**
```
Products: 0 | Shops: 0
```

### 2. Debug Console Дээр Шалгах

**Flutter app-ийг debug mode-оор ажиллуулаад:**

#### Амжилттай Ачаалагдсан:

```
[WarehouseProvider] Fetching products...
[WebBridge] → GET /api/products
[WebBridge] Response status: 200
[WebBridge] Received response: ...
[WebBridge] Found 6 products in page 1
[WebBridge] ✅ Successfully fetched 6 total products
[WarehouseProvider] ✅ Fetched 6 products
[WarehouseProvider] First product: Талх - Price: 2500.0
```

#### Алдаатай:

```
[WarehouseProvider] ❌ Error fetching products: ...
[WebBridge] ❌ Error fetching products: ...
```

### 3. Sales Entry Screen Дээр Шалгах

**Барааны жагсаалт харагдах эсэхийг шалгах:**

1. **Sales Entry Screen** (Record Sale) руу орох
2. Дэлгүүр сонгох
3. **"Бараа хайх"** талбарт бичих (жишээ: "Талх")
4. Барааны жагсаалт харагдах ёстой

**Хэрэв бараа харагдахгүй бол:**
- "Бараа алга" гэсэн мессеж харагдана
- Эсвэл хоосон жагсаалт

### 4. Backend Сервер Console Дээр Шалгах

**Backend сервер ажиллаж байгаа terminal дээр:**

#### Амжилттай:

```
Fetching products... { page: '1', limit: '200' }
```

#### Mock бараа ашиглаж байвал:

```
Using mock products (Weve API not configured or failed)
```

#### Weve API ашиглаж байвал:

```
Attempting to fetch products from Weve API: https://api.weve.mn/api/products
✅ Successfully fetched 6 products from Weve
```

### 5. API Endpoint Шууд Тест Хийх

**PowerShell дээр:**

```powershell
# Token-тэй тест
$headers = @{
    "Authorization" = "Bearer mock-jwt-token-12345"
    "Content-Type" = "application/json"
}
$response = Invoke-WebRequest -Uri "http://192.168.1.6:3000/api/products?page=1&limit=10" -Headers $headers -UseBasicParsing
$json = $response.Content | ConvertFrom-Json
Write-Host "Status: $($json.status)"
Write-Host "Products count: $($json.data.products.Count)"
```

**Хүлээгдэж буй үр дүн:**
```
Status: success
Products count: 6
```

### 6. App Дээр Visual Indicator Шалгах

**Settings Screen дээр:**

- ✅ **Connected** гэсэн товч харагдах ёстой
- ✅ **Products: X** гэсэн тоо харагдах ёстой (X > 0)
- ✅ **Shops: Y** гэсэн тоо харагдах ёстой (Y > 0)

**Sales Entry Screen дээр:**

- ✅ Дэлгүүр сонгох хэсэгт дэлгүүрүүд харагдах ёстой
- ✅ Бараа хайх талбарт бичихэд барааны жагсаалт харагдах ёстой

## 📊 Бараа Ачаалагдсан Эсэхийг Шалгах Checklist

### ✅ Амжилттай Ачаалагдсан:

- [ ] Settings screen дээр `Products: X` (X > 0) харагдана
- [ ] Debug console дээр `✅ Fetched X products` лог харагдана
- [ ] Sales Entry Screen дээр бараа хайхэд жагсаалт харагдана
- [ ] Backend console дээр `Fetching products...` лог харагдана

### ❌ Ачаалагдаагүй:

- [ ] Settings screen дээр `Products: 0` харагдана
- [ ] Debug console дээр алдааны лог харагдана
- [ ] Sales Entry Screen дээр "Бараа алга" гэсэн мессеж харагдана
- [ ] Backend console дээр алдааны лог харагдана

## 🐛 Алдаа Шалгах

### Алдаа: "Not connected, skipping product refresh"
**Шийдэл:** Settings дээр "Connect & Sync" товчийг дарах

### Алдаа: "Products: 0"
**Шийдэл:** 
1. Settings дээр "Sync now" товчийг дарах
2. Debug console-оос алдааны мэдээллийг шалгах

### Алдаа: 401 Unauthorized
**Шийдэл:** Settings дээр дахин "Connect & Sync" дарах

### Алдаа: Connection timeout
**Шийдэл:** Backend сервер ажиллаж байгаа эсэхийг шалгах

## 🎯 Хамгийн Хурдан Шалгах Арга

1. **Settings Screen** руу орох
2. **"Warehouse Web Sync"** хэсгийг харах
3. **"Products: X"** гэсэн тоог шалгах
   - Хэрэв X > 0 бол бараа ачаалагдсан ✅
   - Хэрэв X = 0 бол бараа ачаалагдаагүй ❌

## 📝 Дэлгэрэнгүй Лог Шалгах

**Debug mode-оор ажиллуулаад:**

1. Flutter app-ийг debug mode-оор ажиллуулах
2. Settings дээр "Sync now" дарах
3. Debug console-оос дараах логуудыг хайх:

```
[WarehouseProvider] Fetching products...
[WebBridge] → GET /api/products
[WebBridge] Response status: 200
[WebBridge] Found 6 products in page 1
[WarehouseProvider] ✅ Fetched 6 products
```

Хэрэв эдгээр логууд харагдахгүй бол бараа ачаалагдаагүй байна.
