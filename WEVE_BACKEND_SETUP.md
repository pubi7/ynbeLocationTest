# Weve Backend-аас Бараа Татахаар Тохируулах

## 🔍 Асуудал

Одоогийн `server.js` нь зөвхөн **mock бараа** буцаадаг, Weve API-тай холбогддоггүй.

## ✅ Шийдэл

`server.js` файлыг шинэчилсэн бөгөөд одоо Weve API-аас бараа татаж болно.

## ⚙️ Тохиргоо

### 1. Environment Variables Тохируулах

`server.js` ажиллуулахдаа environment variables тохируулах:

```bash
# Weve API URL (заавал)
WEVE_API_URL=https://api.weve.mn/api

# Weve API Key (сонголттой, хэрэв шаардлагатай бол)
WEVE_API_KEY=your-api-key-here

# Mock mode-ийг унтраах (Weve API ашиглах)
WEVE_MOCK_MODE=false
```

### 2. Windows PowerShell дээр:

```powershell
$env:WEVE_API_URL="https://api.weve.mn/api"
$env:WEVE_MOCK_MODE="false"
node server.js
```

### 3. .env файл үүсгэх (зөвлөмж):

`server.js` файлын хавтас дээр `.env` файл үүсгэх:

```env
WEVE_API_URL=https://api.weve.mn/api
WEVE_API_KEY=your-api-key-if-needed
WEVE_MOCK_MODE=false
PORT=3000
```

`.env` файл ашиглахын тулд `dotenv` package суулгах:

```bash
npm install dotenv
```

Дараа нь `server.js` файлын эхэнд нэмэх:

```javascript
require('dotenv').config();
```

## 🔄 Ажиллах Механизм

1. **Weve API ашиглах:** `WEVE_MOCK_MODE=false` тохируулсан бол Weve API-аас бараа татана
2. **Mock бараа ашиглах:** `WEVE_MOCK_MODE=true` эсвэл тохируулаагүй бол mock бараа буцаана
3. **Fallback:** Weve API-аас татахад алдаа гарвал автоматаар mock бараа руу буцна

## 📊 API Endpoint

### GET /api/products

**Query Parameters:**
- `page` (optional): Хуудасны дугаар (default: 1)
- `limit` (optional): Хуудас бүрт хэдэн бараа (default: 200)

**Response:**
```json
{
  "status": "success",
  "data": {
    "products": [...],
    "pagination": {
      "page": 1,
      "limit": 200,
      "total": 100,
      "totalPages": 1
    }
  }
}
```

## 🔐 Authentication

Weve API нь authentication шаарддаг бол:

1. **API Key ашиглах:**
   ```bash
   WEVE_API_KEY=your-api-key
   ```

2. **Bearer Token ашиглах:**
   - Flutter app нь token-тэй хүсэлт илгээхэд backend нь Weve API руу дамжуулна
   - `Authorization` header нь автоматаар дамжина

## 🧪 Тест Хийх

### 1. Mock Mode (Одоогийн байдал):

```bash
node server.js
```

Mock бараа буцаана.

### 2. Weve API Mode:

```bash
WEVE_API_URL=https://api.weve.mn/api WEVE_MOCK_MODE=false node server.js
```

Weve API-аас бараа татана.

### 3. Curl ашиглан тест хийх:

```bash
# Mock mode
curl http://localhost:3000/api/products

# Weve API mode (token шаардлагатай бол)
curl -H "Authorization: Bearer your-token" http://localhost:3000/api/products
```

## ⚠️ Чухал Зүйлс

1. **Weve API URL:** `https://api.weve.mn/api` гэсэн URL зөв эсэхийг шалгах
2. **Authentication:** Weve API нь token эсвэл API key шаарддаг эсэхийг шалгах
3. **Network:** Backend сервер Weve API-д хандаж чадах эсэхийг шалгах
4. **Rate Limiting:** Weve API нь rate limiting байгаа эсэхийг анхаарах

## 🐛 Алдаа Шалгах

### Алдаа: "Failed to fetch products from Weve API"
**Шалтгаан:**
- Weve API URL буруу байна
- Network холболт байхгүй байна
- Authentication алдаатай байна

**Шийдэл:**
1. Weve API URL зөв эсэхийг шалгах
2. Network холболт шалгах
3. Authentication token/API key зөв эсэхийг шалгах
4. Server console дээрх алдааны мэдээллийг шалгах

### Алдаа: "Using mock products"
**Шалтгаан:**
- `WEVE_MOCK_MODE=false` тохируулаагүй байна
- Weve API-аас татахад алдаа гарсан

**Шийдэл:**
- Environment variable зөв тохируулсан эсэхийг шалгах
- Server console дээрх алдааны мэдээллийг шалгах

## 📝 Дараагийн Алхам

1. ✅ `server.js` файлыг шинэчилсэн
2. ⏳ Weve API URL болон authentication тохируулах
3. ⏳ Backend серверийг дахин эхлүүлэх
4. ⏳ Flutter app-аас бараа татаж тест хийх
