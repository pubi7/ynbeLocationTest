# Backend Service Ажиллуулах Заавар

## 🚀 Хурдан эхлэл

### 1. Terminal/Command Prompt нээх

Windows дээр:
- `Win + R` → `cmd` эсвэл `powershell` → Enter
- Эсвэл VS Code дээр `Ctrl + ~` (terminal нээх)

### 2. Project folder руу орох

```bash
cd "c:\Users\purev\Downloads\aguulgav3-main-20251117T084851Z-1-001\aguulgav3-main"
```

### 3. Dependencies шалгах

```bash
# node_modules байгаа эсэхийг шалгах
dir node_modules

# Хэрэв байхгүй бол суулгах:
npm install
```

### 4. Backend Service Ажиллуулах

```bash
# Production mode
npm start

# Эсвэл шууд:
node server.js
```

### 5. Амжилттай эхэлсэн эсэхийг шалгах

Сервер ажиллаж эхэлсэн бол terminal дээр:
```
Server running on http://localhost:3000
```

## ✅ Тест хийх

### Browser дээр:
```
http://localhost:3000/api/opendatalab/organization/611201
```

### PowerShell/Command Prompt дээр:
```powershell
# PowerShell
Invoke-WebRequest -Uri "http://localhost:3000/api/opendatalab/organization/611201"

# Command Prompt
curl http://localhost:3000/api/opendatalab/organization/611201
```

## 🔧 Алдаа засах

### Port 3000 аль хэдийн ашиглагдаж байна

**Шийдэл 1:** Өөр process-ийг хаах
```powershell
# Port 3000 ашиглаж байгаа process олох
netstat -ano | findstr :3000

# Process ID (PID) олоод kill хийх
taskkill /PID <PID> /F
```

**Шийдэл 2:** Өөр port ашиглах
- `server.js` файлд: `const PORT = process.env.PORT || 3001;`
- `lib/config/api_config.dart` файлд: `backendServerUrl = 'http://192.168.0.111:3001'`

### Node.js суулгаагүй байна

1. https://nodejs.org/ руу орох
2. LTS хувилбар суулгах
3. Terminal нээж шалгах:
   ```bash
   node --version
   npm --version
   ```

### Dependencies суулгах алдаа

```bash
# node_modules устгах
rmdir /s node_modules

# package-lock.json устгах
del package-lock.json

# Дахин суулгах
npm install
```

## 📝 Flutter Config Тохируулах

Backend service ажиллаж эхэлсний дараа Flutter config тохируулах:

`lib/config/api_config.dart` файлд:

```dart
// Windows IP хаяг олох: ipconfig командыг ажиллуулах
static const String backendServerUrl = 'http://192.168.0.111:3000';
```

**IP хаяг олох:**
```bash
ipconfig
# IPv4 Address-ийг олох (жишээ: 192.168.0.111)
```

## 🎯 Ажиллуулах командууд

### Windows PowerShell:
```powershell
cd "c:\Users\purev\Downloads\aguulgav3-main-20251117T084851Z-1-001\aguulgav3-main"
npm start
```

### Windows Command Prompt:
```cmd
cd c:\Users\purev\Downloads\aguulgav3-main-20251117T084851Z-1-001\aguulgav3-main
npm start
```

### VS Code Terminal:
```bash
npm start
```

## ⚠️ Чухал

1. **Backend service ажиллаж байх ёстой** - Flutter app ажиллахын тулд
2. **Port 3000 чөлөөтэй байх ёстой** - Өөр process ашиглаж байвал хаах
3. **Интернэт холболт байх ёстой** - Opendatalab.mn API-г дуудахад
4. **Flutter config зөв байх ёстой** - Backend server URL зөв байх

## 🔄 Service зогсоох

Terminal дээр `Ctrl + C` дарж зогсооно.



