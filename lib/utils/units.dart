/// Quantity in the unit the rate is per. Rates are per kg (or litre), so
/// grams and ml are divided by 1000 before multiplying by the rate;
/// kg, L and pcs stay as they are.
double qtyForRate(double qty, String? unit) {
  final u = (unit ?? '').trim().toLowerCase();
  if (u == 'g' || u == 'gm' || u == 'gms' || u == 'gram' || u == 'grams' || u == 'ml') return qty / 1000.0;
  if (u == 'ton' || u == 'tons') return qty * 1000.0;
  return qty;
}
