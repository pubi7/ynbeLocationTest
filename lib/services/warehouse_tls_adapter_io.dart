import 'dart:io';

import 'package:dio/dio.dart';
import 'package:dio/io.dart';

/// Зөвхөн VM (Android/iOS/desktop). IP + HTTPS эсвэл self-signed үед түр ашиглана.
///
/// **Аюултай:** MITM-д өртөмтгий; зөвхөн `WAREHOUSE_TLS_INSECURE=true` + дотоод тест.
void configureWarehouseDioTls(Dio dio, bool insecure) {
  if (!insecure) return;
  dio.httpClientAdapter = IOHttpClientAdapter(
    createHttpClient: () {
      final client = HttpClient();
      client.badCertificateCallback =
          (X509Certificate cert, String host, int port) => true;
      return client;
    },
  );
}
