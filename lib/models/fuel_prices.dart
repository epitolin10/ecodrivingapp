class FuelPrices {
  final double? gazole;
  final double? sp95;
  final double? sp98;
  final DateTime fetchedAt;

  const FuelPrices({
    this.gazole,
    this.sp95,
    this.sp98,
    required this.fetchedAt,
  });
}
