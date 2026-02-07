# Утас дээр Backend API холбогдох заавар

## Асуудал
Утас дээр `localhost:3000` ажиллахгүй байна. Учир нь утас дээр `localhost` нь утас өөрөө, компьютер биш.

## Шийдэл

### 1. Компьютерийн IP хаяг олох

Windows PowerShell дээр:
```powershell
ipconfig | findstr /i "IPv4"
```

Таны компьютерийн IP хаяг: **192.168.1.6**

### 2. Backend сервер ажиллуулах

Backend сервер нь компьютер дээр ажиллах ёстой:

```powershell
cd c:\Users\purev\Downloads\ynbeLocationTest
node server.js
```

Сервер ажиллаж эхэлсэн бол:
```
Server running on http://localhost:3000
```

### 3. App дээр тохируулах

**Арга 1: App Settings дээр (Хамгийн амар)**

1. App-ийг нээх
2. Settings (Тохиргоо) руу орох
3. "Server URL" талбарт оруулах: `http://192.168.1.6:3000`
4. "Save Server URL" дарах

**Арга 2: Code дээр (Default утга)**

`lib/config/api_config.dart` файлд:
```dart
return 'http://192.168.1.6:3000';
```

✅ **Одоогоор энэ нь аль хэдийн тохируулагдсан байна!**

### 4. Шалгах

1. Компьютер болон утас нь **ижил WiFi сүлжээнд** холбогдсон байх ёстой
2. Backend сервер ажиллаж байгаа эсэхийг шалгах:
   - Компьютер дээр browser нээх: `http://localhost:3000`
   - Эсвэл: `http://192.168.1.6:3000`
3. App дээр холбогдохыг оролдох

## Чухал зүйлс

### ✅ Зөв
- ✅ `http://192.168.1.6:3000` - Physical утас дээр
- ✅ `http://10.0.2.2:3000` - Android Emulator дээр
- ✅ `http://localhost:3000` - iOS Simulator дээр

### ❌ Буруу
- ❌ `http://localhost:3000` - Physical утас дээр (ажиллахгүй!)
- ❌ `http://127.0.0.1:3000` - Physical утас дээр (ажиллахгүй!)

## Алдаа засах

### "Connection refused" эсвэл "Unable to connect"
1. Backend сервер ажиллаж байгаа эсэхийг шалгах
2. Компьютер болон утас ижил WiFi дээр байгаа эсэхийг шалгах
3. Firewall нь port 3000-ийг блоклож байгаа эсэхийг шалгах

### Firewall засах (Windows)
```powershell
# Port 3000 нээх
netsh advfirewall firewall add rule name="Node.js Server" dir=in action=allow protocol=TCP localport=3000
```

### IP хаяг өөрчлөгдсөн бол
Компьютерийн IP хаяг өөрчлөгдсөн бол (WiFi солигдсон, router restart хийсэн):
1. Дахин `ipconfig` ажиллуулах
2. Шинэ IP хаягийг app settings дээр оруулах

## Одоогийн тохиргоо

- **Default API URL**: `http://192.168.1.6:3000`
- **Компьютерийн IP**: `192.168.1.6`
- **Port**: `3000`

Хэрэв IP хаяг өөрчлөгдсөн бол дээрх алхмуудыг дагана уу!
