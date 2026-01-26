# Weve Site Integration - Status Report
## Weve сайтын интеграци - Статус тайлан

### 📋 Одоогийн байдал (Current Status)

✅ **Бүх файлууд бэлэн байна** (All files are ready)

---

## 📁 Файлуудын бүтэц (File Structure)

```
src/
├── config/
│   └── index.ts              ✅ Weve API тохиргоо
├── services/
│   ├── weve.service.ts        ✅ Weve API харилцаа
│   ├── weve-auth.service.ts  ✅ Weve нэвтрэлт
│   └── weve-sync.service.ts  ✅ Бараа/захиалга синк
├── controllers/
│   └── weve-auth.controller.ts ✅ REST API контроллер
├── routes/
│   └── weve-auth.routes.ts   ✅ API route-ууд
├── utils/
│   └── logger.ts             ✅ Logging utility
├── db/
│   └── prisma.ts             ✅ Database stub
└── .env.example              ✅ Тохиргооны жишээ
```

---

## 🔧 Тохиргоо (Configuration)

### Config файл (`src/config/index.ts`)
- **API URL**: `https://api.weve.mn/api` (default)
- **API Key**: Environment variable-аас унших
- **Timeout**: 30000ms (30 секунд)
- **Mock Mode**: Default: `true` (бодит API ашиглахгүй)

### Environment Variables (.env файлд оруулах)
```env
WEVE_API_URL=https://api.weve.mn/api
WEVE_API_KEY=your_weve_api_key_here
WEVE_API_TIMEOUT=30000
WEVE_MOCK_MODE=false  # Бодит API ашиглах бол false
```

---

## 🚀 Функцүүд (Features)

### 1. **Weve Authentication Service** (`weve-auth.service.ts`)
- ✅ Weve сайтад нэвтрэх (`login`)
- ✅ Гарах (`logout`)
- ✅ Session шалгах (`getSession`)
- ✅ Token сэргээх (`refreshToken`)
- ✅ Credential шалгах (`validateCredentials`)

### 2. **Weve Service** (`weve.service.ts`)
- ✅ Бараа татах (`fetchProducts`)
  - Page, limit, categoryId, isActive параметрүүд
- ✅ Захиалга илгээх (`pushOrder`)
  - Order number, customer info, items, amounts

### 3. **Weve Sync Service** (`weve-sync.service.ts`)
- ✅ Бараа автоматаар синк хийх (`syncProductsFromWeve`)
- ✅ Захиалга автоматаар илгээх (`autoPushOrderToWeve`)
- ✅ Гараар синк хийх (`triggerManualSync`)
- ✅ Ангилалаар синк хийх (`syncProductsByCategory`)

---

## 📱 Flutter App Integration

### Sales Entry Screen (`sales_entry_screen.dart`)
- ✅ `_pushOrderToWeve()` функц ажиллаж байна
- ✅ Warehouse backend руу захиалга илгээж байна
- ✅ Хэрэглэгчид "🌐 Захиалга Weve сайт дээр харагдаж байна" мэдэгдэл харагдаж байна

### Захиалга илгээх процесс:
1. Flutter app → Warehouse backend (`createOrder`)
2. Warehouse backend → Weve API (`pushOrder`)
3. Weve сайт дээр захиалга харагдана

---

## ⚠️ Анхаарах зүйлс (Important Notes)

### 1. **Mock Mode**
- Одоогоор `WEVE_MOCK_MODE=true` (default)
- Бодит Weve API ашиглах бол `.env` файлд `WEVE_MOCK_MODE=false` оруулах

### 2. **Prisma Database**
- Одоогоор stub файл байна
- Бодит Prisma client суулгах хэрэгтэй:
  ```bash
  npm install @prisma/client
  npx prisma init
  npx prisma generate
  ```

### 3. **Environment Variables**
- `.env` файл үүсгэх хэрэгтэй (`.env.example`-аас хуулж)
- Weve API-ийн бодит URL, API key оруулах

---

## 🔄 Ажиллуулах (How to Use)

### 1. Environment тохиргоо
```bash
# .env файл үүсгэх
cp src/.env.example src/.env

# Бодит тохиргоо оруулах
# WEVE_API_URL=https://api.weve.mn/api
# WEVE_API_KEY=your_real_api_key
# WEVE_MOCK_MODE=false
```

### 2. Dependencies суулгах
```bash
npm install axios
# Prisma хэрэгтэй бол:
npm install @prisma/client
```

### 3. Backend сервер ажиллуулах
```bash
# TypeScript compile хийх
npm run build

# Server ажиллуулах
npm start
```

---

## 📊 API Endpoints

### Authentication
- `POST /api/weve/auth/login` - Weve-д нэвтрэх
- `POST /api/weve/auth/logout` - Гарах
- `GET /api/weve/auth/session` - Session статус
- `POST /api/weve/auth/refresh` - Token сэргээх
- `POST /api/weve/auth/validate` - Credential шалгах

### Sync
- `POST /api/weve/sync/trigger` - Гараар синк хийх
- `GET /api/weve/sync/status` - Синк статус
- `POST /api/weve/sync/category/:categoryId` - Ангилалаар синк

---

## ✅ Дараагийн алхам (Next Steps)

1. ✅ **Config файл** - Бэлэн
2. ✅ **Services** - Бэлэн
3. ✅ **Controllers & Routes** - Бэлэн
4. ⏳ **Environment тохиргоо** - `.env` файл үүсгэх
5. ⏳ **Prisma database** - Бодит Prisma client суулгах
6. ⏳ **Testing** - Weve API-тай холбогдож турших

---

## 🐛 Мэдэгдэх асуудлууд (Known Issues)

- Prisma stub файл байгаа тул бодит database operation хийхгүй
- Mock mode default байгаа тул бодит API дуудагдахгүй
- Environment variables тохируулаагүй бол default утгууд ашиглана

---

**Огноо**: 2025-01-17  
**Статус**: ✅ Бэлэн (Ready)
