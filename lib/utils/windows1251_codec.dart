import 'dart:convert';
import 'dart:typed_data';

/// WHATWG index-windows-1251: byte 0x80+i -> Unicode (i = 0..127).
const _cp1251Unicode = <int>[
  0x0402,
  0x0403,
  0x201A,
  0x0453,
  0x201E,
  0x2026,
  0x2020,
  0x2021,
  0x20AC,
  0x2030,
  0x0409,
  0x2039,
  0x040A,
  0x040C,
  0x040B,
  0x040F,
  0x0452,
  0x2018,
  0x2019,
  0x201C,
  0x201D,
  0x2022,
  0x2013,
  0x2014,
  0x0098,
  0x2122,
  0x0459,
  0x203A,
  0x045A,
  0x045C,
  0x045B,
  0x045F,
  0x00A0,
  0x040E,
  0x045E,
  0x0408,
  0x00A4,
  0x0490,
  0x00A6,
  0x00A7,
  0x0401,
  0x00A9,
  0x0404,
  0x00AB,
  0x00AC,
  0x00AD,
  0x00AE,
  0x0407,
  0x00B0,
  0x00B1,
  0x0406,
  0x0456,
  0x0491,
  0x00B5,
  0x00B6,
  0x00B7,
  0x0451,
  0x2116,
  0x0454,
  0x00BB,
  0x0458,
  0x0405,
  0x0455,
  0x0457,
  0x0410,
  0x0411,
  0x0412,
  0x0413,
  0x0414,
  0x0415,
  0x0416,
  0x0417,
  0x0418,
  0x0419,
  0x041A,
  0x041B,
  0x041C,
  0x041D,
  0x041E,
  0x041F,
  0x0420,
  0x0421,
  0x0422,
  0x0423,
  0x0424,
  0x0425,
  0x0426,
  0x0427,
  0x0428,
  0x0429,
  0x042A,
  0x042B,
  0x042C,
  0x042D,
  0x042E,
  0x042F,
  0x0430,
  0x0431,
  0x0432,
  0x0433,
  0x0434,
  0x0435,
  0x0436,
  0x0437,
  0x0438,
  0x0439,
  0x043A,
  0x043B,
  0x043C,
  0x043D,
  0x043E,
  0x043F,
  0x0440,
  0x0441,
  0x0442,
  0x0443,
  0x0444,
  0x0445,
  0x0446,
  0x0447,
  0x0448,
  0x0449,
  0x044A,
  0x044B,
  0x044C,
  0x044D,
  0x044E,
  0x044F,
];

final Map<int, int> _unicodeToCp1251 = () {
  final m = <int, int>{};
  for (var i = 0; i < 128; i++) {
    m[_cp1251Unicode[i]] = 0x80 + i;
  }
  return m;
}();

/// U+04E8/U+04E9/U+04AE/U+04AF (Mongolian Cyrillic) are not in CP1251; mapped to O/o, U/u.
String normalizeMongolianForCp1251(String s) {
  return s
      .replaceAll('\u04E8', '\u041E')
      .replaceAll('\u04E9', '\u043E')
      .replaceAll('\u04AE', '\u0423')
      .replaceAll('\u04AF', '\u0443');
}

final class _Windows1251Encoder extends Converter<String, List<int>> {
  const _Windows1251Encoder();

  @override
  Uint8List convert(String input) {
    final normalized = normalizeMongolianForCp1251(input);
    final out = BytesBuilder(copy: false);
    for (final r in normalized.runes) {
      if (r < 0x80) {
        out.addByte(r);
      } else {
        final b = _unicodeToCp1251[r];
        if (b != null) {
          out.addByte(b);
        } else {
          out.addByte(0x3F);
        }
      }
    }
    return out.takeBytes();
  }
}

final class _Windows1251Decoder extends Converter<List<int>, String> {
  const _Windows1251Decoder();

  @override
  String convert(List<int> input) =>
      throw UnsupportedError('windows-1251 decode is not supported');
}

/// Термаль принтерт зориулсан Windows-1251 (кирилл нэг байт/тэмдэг).
///
/// [Generator(codec: windows1251)] болон `latin1`-тай ижил хэрэглээ.
final class Windows1251Codec extends Encoding {
  const Windows1251Codec();

  @override
  String get name => 'windows-1251';

  @override
  Uint8List encode(String input) => encoder.convert(input) as Uint8List;

  @override
  String decode(List<int> encoded, {bool allowMalformed = false}) =>
      decoder.convert(encoded);

  @override
  Converter<String, List<int>> get encoder => const _Windows1251Encoder();

  @override
  Converter<List<int>, String> get decoder => const _Windows1251Decoder();
}

const windows1251 = Windows1251Codec();
