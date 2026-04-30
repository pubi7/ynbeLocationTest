# =====================================================
# Компьютерийг сервер болгож, утаснаас холбогдох скрипт
# =====================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Утаснаас холбогдох сервер ажиллуулах" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# 1. IP хаяг харуулах
Write-Host "1. Компьютерийн IP хаяг:" -ForegroundColor Yellow
$ip = $null
foreach ($line in (ipconfig | Select-String "IPv4")) {
    if ($line -match "(\d+\.\d+\.\d+\.\d+)") {
        $candidate = $matches[1]
        if ($candidate -notlike "127.*") {
            $ip = $candidate
            break
        }
    }
}
if ($ip) {
    Write-Host "   --> $ip" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Утаснаас холбогдоход Login дэлгэц дээр энэ хаягийг оруулна:" -ForegroundColor White
    Write-Host "   http://${ip}:3000" -ForegroundColor Cyan
} else {
    Write-Host "   IP олдсонгүй. ipconfig ажиллуулж шалгана уу." -ForegroundColor Red
}
Write-Host ""

# 2. Firewall нээх (нэг удаа)
Write-Host "2. Firewall шалгах (port 3000)..." -ForegroundColor Yellow
$rule = netsh advfirewall firewall show rule name="Warehouse Backend 3000" 2>$null
if (-not $rule) {
    netsh advfirewall firewall add rule name="Warehouse Backend 3000" dir=in action=allow protocol=TCP localport=3000
    Write-Host "   Firewall дүрэм нэмэгдлээ." -ForegroundColor Green
} else {
    Write-Host "   Firewall аль хэдийн нээгдсэн." -ForegroundColor Green
}
Write-Host ""

# 3. Backend асаах
Write-Host "3. Backend сервер асааж байна..." -ForegroundColor Yellow
Write-Host "   (PostgreSQL + warehouse-service-main port 3000)" -ForegroundColor Gray
Write-Host ""
Write-Host "ЧУХАЛ: Компьютер болон утас ижил WiFi сүлжээнд холбогдсон байх ёстой!" -ForegroundColor Magenta
Write-Host ""
Write-Host "Ctrl+C дарж зогсооно." -ForegroundColor Gray
Write-Host ""

$backendPath = "c:\Users\purev\Downloads\warehouse-service-main\warehouse-service-main"
Set-Location $backendPath
npm run dev
