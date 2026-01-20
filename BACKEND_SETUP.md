# Backend Scraper API Тохируулах Заавар

## 1. Node.js суулгах

Node.js суулгаагүй бол: https://nodejs.org/

## 2. Dependencies суулгах

```bash
npm install
```

## 3. Backend сервер ажиллуулах

```bash
node server.js
```

Сервер ажиллаж эхэлсэн бол:
```
Scraper API running on port 3000
```

## 4. Flutter Config тохируулах

`lib/config/api_config.dart` файлд:

### Flutter Web ашиглаж байгаа бол:

⚠️ **ЧУХАЛ:** Flutter Web дээр `localhost` асуудал гарч болзошгүй!

**Шийдэл:**
1. Computer-ийн IP хаяг олох:
   - Windows: `ipconfig` командыг ажиллуулах
   - Mac/Linux: `ifconfig` командыг ажиллуулах
   - IPv4 Address-ийг олох (жишээ: `192.168.1.100`)

2. Config файлд IP хаяг ашиглах:
   ```dart
   static const String backendServerUrl = 'http://192.168.1.100:3000';
   ```

### Flutter Mobile (Android Emulator) ашиглаж байгаа бол:

```dart
static const String backendServerUrl = 'http://10.0.2.2:3000';
```

### Flutter Mobile (iOS Simulator) ашиглаж байгаа бол:

```dart
static const String backendServerUrl = 'http://localhost:3000';
```

### Production дээр:

```dart
static const String backendServerUrl = 'https://your-server.com';
```

## 5. Тест хийх

Backend сервер ажиллаж байгаа эсэхийг шалгах:

```bash
curl http://localhost:3000/search/6111203
```

Эсвэл browser дээр нээх:
```
http://localhost:3000/search/6111203
```

## Алдаа засах

### ERR_CONNECTION_REFUSED
- Backend сервер ажиллахгүй байна
- `node server.js` командыг ажиллуулах хэрэгтэй

### CORS алдаа
- `server.js` файлд `cors` middleware байгаа эсэхийг шалгах
- `app.use(cors());` байх ёстой

### Port аль хэдийн ашиглагдаж байна
- Өөр port ашиглах: `app.listen(3001, ...)`
- Flutter config-д мөн өөрчлөх хэрэгтэй

