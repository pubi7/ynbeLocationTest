# CORS Асуудлыг Шийдэх Заавар

## Асуудал

Flutter апп-аас шууд `opendatalab.mn` API-г дуудахад CORS алдаа гарч байна:

```
Access to XMLHttpRequest at 'https://opendatalab.mn/api/organization/...' 
from origin 'http://localhost:...' has been blocked by CORS policy: 
No 'Access-Control-Allow-Origin' header is present on the requested resource.
```

## Шийдэл: Backend Proxy Server

✅ **Зөв шийдэл**: Backend proxy server ашиглах

```
Flutter App → Backend Server → Opendatalab.mn API
```

### Яагаад backend заавал хэрэгтэй вэ?

1. **CORS-г backend дээрээ тойрно** - Backend server нь CORS header-уудыг нэмж өгдөг
2. **Opendatalab.mn хариултаа block хийхгүй** - Backend server-ээс хандаж байгаа тул
3. **Хүссэн хэмжээгээр request хийж чадна** - Rate limiting, caching гэх мэт
4. **Mobile дээр шууд request хийх асуудал бүрэн шийдэгдэнэ**

## Хэрэгжүүлсэн өөрчлөлтүүд

### 1. Backend Proxy Endpoint (`backend/routes/opendatalab.js`)

```javascript
// Proxy endpoint for Opendatalab API (CORS workaround)
// Шууд JSON буцаана (wrapper байхгүй) - Flutter service-тэй илүү сайн ажиллана
router.get("/organization/:reg", async (req, res) => {
  const reg = req.params.reg;
  
  try {
    const url = `https://opendatalab.mn/api/organization/${reg}`;
    const response = await axios.get(url, {
      headers: {
        'User-Agent': 'Mozilla/5.0...',
        'Accept': 'application/json',
      },
      timeout: 10000,
    });

    // HTML буцааж байгаа эсэхийг шалгах (error page эсвэл redirect)
    const responseText = typeof response.data === 'string' ? response.data : JSON.stringify(response.data);
    if (responseText.trim().startsWith('<!DOCTYPE') || 
        responseText.trim().startsWith('<!doctype') || 
        responseText.trim().startsWith('<html')) {
      return res.status(500).json({
        error: true,
        message: "Opendatalab API returned HTML instead of JSON.",
      });
    }

    // CORS header нэмэх
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
    res.setHeader("Access-Control-Allow-Headers", "Content-Type");

    // Шууд JSON буцаах (wrapper байхгүй)
    res.json(response.data);
  } catch (err) {
    res.status(500).json({
      error: true,
      message: "Opendatalab API error: " + err.message,
    });
  }
});
```

### 2. Flutter Service (`lib/services/opendatalab_service.dart`)

```dart
class OpendatalabService {
  /// Backend proxy URL (CORS асуудлыг тойрно)
  String get _backendProxyUrl {
    return '${ApiConfig.backendServerUrl}/api/opendatalab/organization';
  }

  Future<Map<String, dynamic>?> searchOrganization(String regNumber) async {
    try {
      final url = Uri.parse("$_backendProxyUrl/$regNumber");
      final response = await http.get(url);

      // HTML буцааж байгаа эсэхийг шалгах
      final responseBody = response.body;
      if (responseBody.trim().startsWith('<!DOCTYPE') ||
          responseBody.trim().startsWith('<!doctype') ||
          responseBody.trim().startsWith('<html')) {
        return {
          "error": true,
          "message": "Backend сервер HTML буцааж байна. Сервер ажиллаж байгаа эсэхийг шалгана уу.",
        };
      }

      if (response.statusCode == 200) {
        final responseData = json.decode(responseBody);
        // Backend нь шууд JSON буцаана (wrapper байхгүй)
        return responseData as Map<String, dynamic>?;
      }
      // ...
    } catch (e) {
      // FormatException (JSON parse алдаа) бол тусгайлан заах
      if (e.toString().contains('FormatException') ||
          e.toString().contains('Unexpected token')) {
        return {
          "error": true,
          "message": "Backend серверээс буруу формат ирлээ (HTML эсвэл буруу JSON).",
        };
      }
      // ...
    }
  }
}
```

## Ашиглах заавар

### 1. Backend сервер ажиллуулах

```bash
cd aguulgav3-main
npm install
node server.js
```

Сервер ажиллаж эхэлсэн бол:
```
Server running on http://localhost:3000
```

### 2. Flutter Config тохируулах

`lib/config/api_config.dart` файлд backend серверийн URL оруулах:

```dart
class ApiConfig {
  // Flutter Web ашиглаж байгаа бол:
  static const String backendServerUrl = 'http://192.168.0.111:3000';
  
  // Flutter Mobile (Android Emulator):
  // static const String backendServerUrl = 'http://10.0.2.2:3000';
  
  // Flutter Mobile (iOS Simulator):
  // static const String backendServerUrl = 'http://localhost:3000';
  
  // Production:
  // static const String backendServerUrl = 'https://your-server.com';
}
```

### 3. Тест хийх

Backend proxy ажиллаж байгаа эсэхийг шалгах:

```bash
curl http://localhost:3000/api/opendatalab/organization/6111203
```

Эсвэл browser дээр:
```
http://localhost:3000/api/opendatalab/organization/6111203
```

## Алдаа засах

### ERR_CONNECTION_REFUSED
- Backend сервер ажиллахгүй байна
- `node server.js` командыг ажиллуулах хэрэгтэй

### CORS алдаа
- Backend сервер дээр `cors` middleware байгаа эсэхийг шалгах
- `server.js` файлд `app.use(cors());` байх ёстой

### Backend серверт холбогдож чадсангүй
- `api_config.dart` файлд зөв URL оруулсан эсэхийг шалгах
- Flutter Web ашиглаж байгаа бол `localhost` биш IP хаяг ашиглах

## Хийгдсэн сайжруулалтууд

### ✅ Шууд JSON буцаах
- Backend нь wrapper байхгүй, шууд JSON буцаана
- Flutter service шууд ашиглана

### ✅ HTML Response шалгах
- Backend болон Flutter service дээр HTML response-ийг шалгана
- HTML ирвэл тодорхой error message буцаана

### ✅ Error Handling сайжруулах
- FormatException (Unexpected token '<') алдааг тусгайлан заах
- Backend сервер down байгаа эсэхийг тодорхойлох

## Дүгнэлт

✅ **Одоо CORS асуудал бүрэн шийдэгдсэн!**

- Flutter Web → ✅ Ажиллана
- Flutter Mobile → ✅ Ажиллана  
- Browser → ✅ Ажиллана
- Postman → ✅ Ажиллана
- HTML response → ✅ Тодорхой error message
- JSON parse алдаа → ✅ Тусгайлан заах

❌ **Шууд Opendatalab API-г Flutter-аас дуудах боломжгүй** (CORS policy)

✅ **Backend proxy ашиглах нь цорын ганц зөв шийдэл**

