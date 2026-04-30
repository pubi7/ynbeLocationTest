// Mongolian VAT 10% on receipt: grossTotal is VAT-inclusive (barimt "НИЙТ").
// VAT = grossTotal / 11, net = grossTotal - VAT (VAT rounded to whole tugrik).

final class ReceiptVatFromGross {
  ReceiptVatFromGross._(this.grossTotal, this.vatAmount, this.netAmount);

  /// Gross total (same as receipt "НИЙТ").
  final double grossTotal;

  /// VAT amount (10/110 of gross).
  final double vatAmount;

  /// Net amount excluding VAT.
  final double netAmount;

  factory ReceiptVatFromGross.fromGrossTotal(double grossTotal) {
    if (grossTotal <= 0) {
      return ReceiptVatFromGross._(grossTotal, 0, 0);
    }
    final vat = (grossTotal / 11.0).roundToDouble();
    return ReceiptVatFromGross._(grossTotal, vat, grossTotal - vat);
  }
}
