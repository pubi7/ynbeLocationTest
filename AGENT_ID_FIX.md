# Agent ID Авахгүй Байгаа Асуудал Засах

## Асуудал
Agent ID хадгалагдаагүй байна, LocationProvider дээр "Agent ID байхгүй" гэсэн мэдээлэл гарч байна.

## Шалтгаан
Login хийсний дараа agent ID-г backend response-оос олж, LocationProvider-д хадгалах логик байгаагүй байсан.

## Засварласан зүйлс

### 1. Backend сервер дээр agent-login endpoint нэмсэн
- ✅ `POST /api/auth/agent-login` endpoint нэмсэн
- ✅ Agent мэдээлэл буцаадаг (id, username, name, email)
- ✅ Mock agent ID үүсгэдэг

### 2. Profile endpoint сайжруулсан
- ✅ `GET /api/auth/profile` endpoint agentId буцаадаг
- ✅ User ID-г agent ID болгон ашиглаж болно

### 3. Agent ID хадгалах логик нэмсэн
- ✅ `WarehouseWebBridge.login()` - agent-login response-оос agent ID олж хадгална
- ✅ `MobileUserLoginProvider._loadUserProfile()` - profile response-оос agent ID олж хадгална
- ✅ `WarehouseProvider.connect()` - profile response-оос agent ID олж хадгална
- ✅ Бүх тохиолдолд SharedPreferences дээр `agent_id` key-д хадгална

## Одоо хийх зүйл

### 1. Backend сервер дахин ажиллуулах
```powershell
# Одоо ажиллаж байгаа Node process-уудыг зогсоох
Get-Process -Name node | Stop-Process -Force

# Сервер дахин ажиллуулах
cd c:\Users\purev\Downloads\ynbeLocationTest
node server.js
```

### 2. App-ийг дахин build хийх
```powershell
flutter run
```

### 3. Login хийх
1. App дээр login хийх:
   - Email: `admin@admin.com` эсвэл ямар ч username
   - Password: `password`
2. Login амжилттай болсны дараа agent ID хадгалагдана

### 4. Шалгах
Console log дээр дараах мэдээлэл харагдах ёстой:
- `[WebBridge] ✅ Agent ID хадгалагдлаа: 1` (agent-login ашигласан бол)
- `[WarehouseProvider] ✅ Agent ID хадгалагдлаа: 1` (normal login ашигласан бол)
- `✅ Agent ID ачаалагдлаа: 1` (LocationProvider дээр)

## Backend API Endpoints

### Agent Login
```
POST http://192.168.1.6:3000/api/auth/agent-login
Body: { "username": "testuser", "password": "password" }
Response: {
  "status": "success",
  "data": {
    "token": "mock-jwt-token-12345",
    "agent": {
      "id": 1234,
      "username": "testuser",
      "name": "testuser",
      "email": "testuser@example.com"
    }
  }
}
```

### Profile
```
GET http://192.168.1.6:3000/api/auth/profile
Headers: { "Authorization": "Bearer mock-jwt-token-12345" }
Response: {
  "status": "success",
  "data": {
    "user": {
      "id": 1,
      "agentId": 1,
      "name": "Admin User",
      "email": "admin@admin.com"
    }
  }
}
```

## Agent ID Ашиглах

Agent ID нь LocationProvider дээр хадгалагдаж, location tracking үед backend руу илгээхэд ашиглагдана:

```
POST http://192.168.1.6:3000/api/agents/{agentId}/location
```

## Хэрэв Agent ID хэвээр байхгүй бол

1. **Backend сервер ажиллаж байгаа эсэхийг шалгах:**
   ```powershell
   netstat -ano | findstr :3000
   ```

2. **Login дахин хийх:**
   - App дээр logout хийх
   - Дахин login хийх
   - Console log шалгах

3. **SharedPreferences шалгах:**
   - App-ийг бүрэн restart хийх
   - LocationProvider `_loadAgentId()` method дуудагдах ёстой

4. **Debug log шалгах:**
   - `[WebBridge] ✅ Agent ID хадгалагдлаа` гэсэн мэдээлэл харагдах ёстой
   - Хэрэв харагдахгүй бол login response дээр agent ID байхгүй байж магадгүй

Хэрэв бүх зүйл зөв тохируулагдсан бол Agent ID хадгалагдаж, location tracking ажиллах ёстой! 🎉
