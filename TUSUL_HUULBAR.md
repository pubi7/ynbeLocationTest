# Төсөл — хуваалцах / татаж авах товч тайлбар

Энэ файлыг шууд илгээж, хүлээн авагч `.md` файлыг татаж авч уншиж болно. Бүтэн төслийг авахын тулд доорх **Төслийг авах** хэсгийг ашиглана.

---

## 1. Юу дээр бичигдсэн бэ

| Зүйл | Утга |
|------|------|
| Хэл | **Dart** |
| Framework | **Flutter** (SDK: `>=3.0.0 <4.0.0`) |
| State | `provider` |
| Навигаци | `go_router` |
| API | `dio`, `http` |
| Хадгалалт | `shared_preferences`, `sqflite`, `hive` |

---

## 2. Газрын зураг, байршил (`flutter_map`)

| Package | Зориулалт |
|---------|-----------|
| `flutter_map` | Газрын зураг (tile map) |
| `latlong2` | Координат (`LatLng`) |
| `geolocator` | GPS / байршил |
| `geocoding` | Хаяг ↔ координат |

---

## 3. Монгол хэл, баримт, принтер

| Package / файл | Зориулалт |
|------------------|-----------|
| `printing`, `pdf` | Баримт PDF, системийн хэвлэх цонх |
| `barcode`, `qr_flutter` | QR / баркод |
| `lib/services/pos_receipt_service.dart` | Захиалгын баримт PDF (кириллд `PdfGoogleFonts.notoSansRegular()` гэх мэт) |
| `print_bluetooth_thermal`, `esc_pos_utils_plus` | Bluetooth thermal принтер |
| `permission_handler` | Bluetooth / location зөвшөөрөл |
| `lib/services/bluetooth_printer_service.dart` | Принтер хайх, холбох, ESC/POS илгээх |

---

## 4. Бүх гол `dependencies` (pubspec.yaml-аас)

`provider`, `go_router`, `geolocator`, `geocoding`, `flutter_map`, `latlong2`, `http`, `dio`, `shared_preferences`, `sqflite`, `hive`, `hive_flutter`, `intl`, `table_calendar`, `printing`, `pdf`, `barcode`, `qr_flutter`, `barcode_widget`, `path_provider`, `url_launcher`, `print_bluetooth_thermal`, `esc_pos_utils_plus`, `permission_handler`, `screenshot`, `image`, `form_field_validator`, `material_design_icons_flutter`, `cupertino_icons`.

---

## 5. Төслийг авах (хүлээн авагчийн талд)

**Сонголт A — Git байвал**

```bash
git clone <репозиторийн-URL>
cd <хавтасын-нэр>
flutter pub get
flutter run
```

**Сонголт B — Zip илгээж байгаа бол**

1. Zip-ийг задлана.
2. Терминалд төслийн хавтас руу орно.
3. `flutter pub get` дараа `flutter run` (эсвэл IDE-аас Run).

**Шаардлага:** суусан Flutter SDK, Android Studio / Xcode (платформоос хамаарна).

---

## 6. Энэ файлыг хэрхэн дамжуулах вэ

- Имэйл, Messenger, Telegram гэх мэтээр **`TUSUL_HUULBAR.md`** файлыг шууд хавсрааж илгээнэ.
- Хүлээн авагч татаж авч, текст засагч эсвэл VS Code / Cursor дээр нээнэ.

Бүтэн кодтой хамт авахыг хүсвэл төслийн бүтэн хавтасыг zip хийж эсвэл Git remote өгөх нь зөв.

---

*Сүүлд шинэчилсэн: төслийн `pubspec.yaml` болон одоогийн бүтэцтэй нийцүүлсэн.*
