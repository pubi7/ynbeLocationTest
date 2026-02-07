# Барааны Мэдээлэл Авах Алдааны Шалгалт

## Өөрчлөлтүүд

### 1. Илүү Дэлгэрэнгүй Лог Нэмсэн

**`lib/services/warehouse_web_bridge.dart`:**
- `fetchAllProducts()` методод алхам бүрийн лог нэмсэн
- `_getJson()` методод алдааны мэдээлэл нэмсэн
- `_unwrapData()` методод response боловсруулалтын лог нэмсэн

**`lib/providers/warehouse_provider.dart`:**
- `refreshProducts()` методод алдааны дэлгэрэнгүй мэдээлэл нэмсэн

### 2. Алдааны Боловсруулалт Сайжруулсан

- DioException-ийн status code болон response data-г логлодог болсон
- Хэрэглэгчид илүү ойлгомжтой алдааны мессеж харуулна

## Шалгах Зүйлс

### 1. Backend Сервер Ажиллаж Байгаа Эсэх

```bash
# PowerShell дээр:
netstat -ano | findstr :3000
```

Хэрэв сервер ажиллахгүй байвал:
```bash
cd c:\Users\purev\Downloads\ynbeLocationTest
node server.js
```

### 2. App Backend-т Холбогдсон Эсэх

Settings дээр очиж:
- API URL зөв эсэхийг шалгах (жишээ: `http://192.168.1.6:3000`)
- "Connect & Sync" товчийг дарах
- Холболт амжилттай болсон эсэхийг шалгах

### 3. Debug Console Шалгах

Flutter app-ийг debug mode-оор ажиллуулаад console-оос дараах логуудыг хайх:

```
[WarehouseProvider] Fetching products...
[WebBridge] → GET /api/products
[WebBridge] Response status: 200
[WebBridge] Unwrapping response: keys=...
[WebBridge] Found X products in page 1
[WarehouseProvider] ✅ Fetched X products
```

Хэрэв алдаа гарвал:
```
[WebBridge] ❌ Error fetching products: ...
[WarehouseProvider] ❌ Error fetching products: ...
```

### 4. Нийтлэг Алдаанууд

#### Алдаа: "Not connected, skipping product refresh"
**Шийдэл:** Settings дээр очиж "Connect & Sync" товчийг дарах

#### Алдаа: 401 Unauthorized
**Шийдэл:** Token дууссан байж магадгүй. Дахин нэвтрэх эсвэл "Connect & Sync" дарах

#### Алдаа: 429 Too Many Requests
**Шийдэл:** Хэсэг хугацааны дараа дахин оролдох

#### Алдаа: Connection timeout
**Шийдэл:** 
- Backend сервер ажиллаж байгаа эсэхийг шалгах
- API URL зөв эсэхийг шалгах (localhost биш, IP хаяг ашиглах)
- Firewall эсвэл network асуудал байгаа эсэхийг шалгах

#### Алдаа: "No products found" эсвэл хоосон жагсаалт
**Шийдэл:**
- Backend-ийн `MOCK_PRODUCTS` массив хоосон биш эсэхийг шалгах
- `server.js` файлыг дахин эхлүүлэх

## Дэлгэрэнгүй Логууд

Одоо дараах мэдээлэл логлодог:
- API хүсэлт илгээх үед
- Response ирэх үед
- Products олдсон тоо
- Алдаа гарвал status code, response data
- Price extraction үйл явц

Эдгээр логууд нь асуудлыг илрүүлэхэд тусална.

## Дараагийн Алхам

1. App-ийг debug mode-оор ажиллуулах
2. Settings дээр очиж "Connect & Sync" дарах
3. Debug console-оос логуудыг шалгах
4. Хэрэв алдаа гарвал дээрх алдааны төрлүүдийг шалгах
