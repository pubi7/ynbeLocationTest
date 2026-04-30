# Viewport Meta Tag Accessibility Fix

## Асуудал

Flutter Web-ийн viewport meta tag нь `maximum-scale=1.0` болон `user-scalable=no` агуулж байгаа нь accessibility асуудал үүсгэдэг:

```html
<!-- ❌ Буруу (Flutter-ийн автоматаар нэмсэн) -->
<meta flt-viewport="" name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
```

### Яагаад энэ асуудал вэ?

1. **Accessibility зөрчил**: WCAG 2.1 стандартад зөрчилтэй
2. **Zoom disable**: Хэрэглэгчид дэлгэцийг zoom хийх боломжгүй болгоно
3. **Lighthouse/WebHint анхааруулга**: Chrome DevTools, Lighthouse, WebHint анхааруулга өгдөг

## Шийдэл

`web/index.html` файлд зөв viewport meta tag нэмсэн:

```html
<!-- ✅ Зөв (Accessibility compliant) -->
<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

## Хийгдсэн өөрчлөлт

`web/index.html` файлд viewport meta tag нэмсэн:

```html
<!-- Viewport meta tag - Accessibility compliant (no maximum-scale or user-scalable) -->
<meta name="viewport" content="width=device-width, initial-scale=1.0">
```

## Тест хийх

1. **Flutter Web build хийх**:
   ```bash
   flutter build web
   ```

2. **Chrome DevTools нээх**:
   - F12 дарж DevTools нээх
   - Console tab-д орох
   - Viewport meta tag алдаа байгаа эсэхийг шалгах

3. **Lighthouse тест хийх**:
   - Chrome DevTools → Lighthouse tab
   - Accessibility тест хийх
   - Viewport meta tag алдаа байгаа эсэхийг шалгах

## Хэрэв Flutter-ийн автоматаар нэмсэн viewport meta tag харагдвал

Хэрэв Flutter нь өөрийн viewport meta tag-ийг нэмж байгаа бол (flt-viewport attribute-тай), дараах аргаар засах:

### Арга 1: Flutter-ийн viewport meta tag-ийг override хийх

`web/index.html` файлд viewport meta tag-ийг `<head>` tag-ийн эхэнд нэмэх:

```html
<head>
  <!-- Viewport meta tag - эхэнд нэмэх -->
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  
  <!-- Бусад meta tags -->
  ...
</head>
```

### Арга 2: JavaScript ашиглан засах

`web/index.html` файлд script нэмэх:

```html
<script>
  // Flutter-ийн viewport meta tag-ийг засах
  window.addEventListener('DOMContentLoaded', function() {
    const viewport = document.querySelector('meta[name="viewport"][flt-viewport]');
    if (viewport) {
      viewport.setAttribute('content', 'width=device-width, initial-scale=1.0');
    }
  });
</script>
```

## Дүгнэлт

✅ **Viewport meta tag-ийг accessibility compliant болгосон**

- `maximum-scale` устгасан
- `user-scalable=no` устгасан
- Chrome DevTools, Lighthouse, WebHint анхааруулга арилна
- WCAG 2.1 стандартад нийцнэ

## Нэмэлт мэдээлэл

- [WCAG 2.1 Success Criterion 1.4.4](https://www.w3.org/WAI/WCAG21/Understanding/resize-text.html)
- [Chrome DevTools Viewport Meta Tag](https://developer.chrome.com/docs/devtools/device-mode/)
- [WebHint Viewport Meta Tag](https://webhint.io/docs/user-guide/hints/hint-meta-viewport/)



