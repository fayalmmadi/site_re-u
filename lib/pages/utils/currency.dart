// lib/utils/currency.dart
import 'package:intl/intl.dart';

/// Retourne le code devise (ISO 4217) à partir d’un pays (nom ou code ISO-2).
/// Ex: "Comores" ou "KM"  -> "KMF"
///     "France"  ou "FR"  -> "EUR"
String countryToCurrency(String? country) {
  if (country == null) return 'EUR';
  final c = country.trim().toUpperCase();

  // codes ISO2 les plus utiles
  const byIso2 = {
    'FR': 'EUR', // France
    'KM': 'KMF', // Comores
    'YT': 'EUR', // Mayotte
    'MG': 'MGA', // Madagascar
    'RE': 'EUR', // La Réunion
    'MU': 'MUR', // Maurice
    'KE': 'KES', // Kenya
    'TZ': 'TZS', // Tanzanie
    'ZA': 'ZAR', // Afrique du Sud
    'US': 'USD',
    'GB': 'GBP',
    'DE': 'EUR',
    'IT': 'EUR',
    'ES': 'EUR',
    'PT': 'EUR',
    'BE': 'EUR',
    'CH': 'CHF',
    'CA': 'CAD',
    'AU': 'AUD',
    'AE': 'AED',
    'MA': 'MAD',
    'TN': 'TND',
    'DZ': 'DZD',
    'SN': 'XOF',
    'CI': 'XOF',
    'BJ': 'XOF',
    'BF': 'XOF',
    'NE': 'XOF',
    'TG': 'XOF',
    'ML': 'XOF',
    'GW': 'XOF',
    'CM': 'XAF',
    'GA': 'XAF',
    'CG': 'XAF',
    'TD': 'XAF',
    'GQ': 'XAF',
    'CF': 'XAF',
  };

  // noms de pays (quelques alias utiles)
  const byName = {
    'COMORES': 'KMF',
    'UNION DES COMORES': 'KMF',
    'FRANCE': 'EUR',
    'MAYOTTE': 'EUR',
    'MADAGASCAR': 'MGA',
    'LA RÉUNION': 'EUR',
    'LA REUNION': 'EUR',
    'MAURICE': 'MUR',
    'KENYA': 'KES',
    'TANZANIE': 'TZS',
    'AFRIQUE DU SUD': 'ZAR',
    'MAROC': 'MAD',
    'TUNISIE': 'TND',
    'ALGÉRIE': 'DZD',
    'ALGERIE': 'DZD',
    'SÉNÉGAL': 'XOF',
    'SENEGAL': 'XOF',
    'CÔTE D\'IVOIRE': 'XOF',
    'COTE D\'IVOIRE': 'XOF',
  };

  if (c.length == 2 && byIso2.containsKey(c)) return byIso2[c]!;
  if (byName.containsKey(c)) return byName[c]!;

  return 'EUR'; // défaut
}

/// Formatte un montant pour une devise donnée avec fallback robuste.
/// Ex: fmtMoney('KMF', 5000) -> "5 000 KMF"
String fmtMoney(String code, num amount, {int? digits}) {
  final dec = digits ?? ((amount % 1 == 0) ? 0 : 2);
  try {
    final f = NumberFormat.simpleCurrency(name: code, decimalDigits: dec);
    final s = f.format(amount);
    if (s.trim().isEmpty) return '$amount $code';
    return s;
  } catch (_) {
    // fallback simple si Intl ne connaît pas la devise
    final n = NumberFormat.decimalPattern();
    n.minimumFractionDigits = dec;
    n.maximumFractionDigits = dec;
    return '${n.format(amount)} $code';
  }
}
