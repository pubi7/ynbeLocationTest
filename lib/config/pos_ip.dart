/// Локал **eBarimt / POS** сервисийн хаягийн сануулга (энэ төсөлд).
///
/// **Ялгах:**
/// - **Vite вэб** (`posReceiptApi.ts`): браузер шууд `VITE_POSAPI_URL` → ихэвчлэн `http://localhost:7080`
///   (`POST /rest/receipt` гэх мэт).
/// - **Энэ Flutter апп**: POS-ийн **7080** руу шууд дуудахгүй. Баримт/сугалаа нь
///   `WarehouseWebBridge` → `POST /api/ebarimt/register/:orderId` гэж **warehouse backend** руу явна.
/// - **Warehouse backend** дээр `EBARIMT_API_URL` (жишээ `http://<IP>:7080`) нь серверээс POS руу ярина.
///
/// Хэрэгтэй бол compile-time override:
/// `--dart-define=POS_SERVICE_DOC_URL=http://192.168.x.x:7080` (зөвхөн UI/лог/док-д ашиглана).
library pos_ip;

class PosIpConfig {
  PosIpConfig._();

  /// Жишээ: локал eBarimt POS (вэб `.env` дээрх `VITE_POSAPI_URL`-тай ижил зүйл).
  /// Flutter апп энэ URL-аар шууд хүсэлт илгээхгүй.
  static const String docDefaultPosLocalBaseUrl = String.fromEnvironment(
    'POS_SERVICE_DOC_URL',
    defaultValue: 'http://localhost:7080',
  );
}
