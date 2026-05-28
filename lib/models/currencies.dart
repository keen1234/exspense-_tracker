class CurrencyInfo {
  final String symbol;
  final String name;
  final String flag;
  final List<int> denominations;

  const CurrencyInfo({
    required this.symbol,
    required this.name,
    required this.flag,
    required this.denominations,
  });
}

const Map<String, CurrencyInfo> currencies = {
  'PHP': CurrencyInfo(symbol: '₱', name: 'Philippine Peso', flag: '🇵🇭', denominations: [1, 5, 10, 20, 50, 100, 500, 1000]),
  'USD': CurrencyInfo(symbol: '\$', name: 'US Dollar', flag: '🇺🇸', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'EUR': CurrencyInfo(symbol: '€', name: 'Euro', flag: '🇪🇺', denominations: [1, 2, 5, 10, 20, 50, 100, 200, 500]),
  'GBP': CurrencyInfo(symbol: '£', name: 'British Pound', flag: '🇬🇧', denominations: [1, 2, 5, 10, 20, 50]),
  'JPY': CurrencyInfo(symbol: '¥', name: 'Japanese Yen', flag: '🇯🇵', denominations: [1, 5, 10, 50, 100, 500, 1000, 5000, 10000]),
  'KRW': CurrencyInfo(symbol: '₩', name: 'South Korean Won', flag: '🇰🇷', denominations: [10, 50, 100, 500, 1000, 5000, 10000, 50000]),
  'CNY': CurrencyInfo(symbol: '¥', name: 'Chinese Yuan', flag: '🇨🇳', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'INR': CurrencyInfo(symbol: '₹', name: 'Indian Rupee', flag: '🇮🇳', denominations: [1, 2, 5, 10, 20, 50, 100, 200, 500, 2000]),
  'AUD': CurrencyInfo(symbol: 'A\$', name: 'Australian Dollar', flag: '🇦🇺', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'CAD': CurrencyInfo(symbol: 'C\$', name: 'Canadian Dollar', flag: '🇨🇦', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'CHF': CurrencyInfo(symbol: 'Fr', name: 'Swiss Franc', flag: '🇨🇭', denominations: [1, 2, 5, 10, 20, 50, 100, 200]),
  'SGD': CurrencyInfo(symbol: 'S\$', name: 'Singapore Dollar', flag: '🇸🇬', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'HKD': CurrencyInfo(symbol: 'HK\$', name: 'Hong Kong Dollar', flag: '🇭🇰', denominations: [1, 2, 5, 10, 20, 50, 100, 500]),
  'THB': CurrencyInfo(symbol: '฿', name: 'Thai Baht', flag: '🇹🇭', denominations: [1, 2, 5, 10, 20, 50, 100, 500, 1000]),
  'IDR': CurrencyInfo(symbol: 'Rp', name: 'Indonesian Rupiah', flag: '🇮🇩', denominations: [500, 1000, 2000, 5000, 10000, 20000, 50000, 100000]),
  'MYR': CurrencyInfo(symbol: 'RM', name: 'Malaysian Ringgit', flag: '🇲🇾', denominations: [1, 5, 10, 20, 50, 100]),
  'VND': CurrencyInfo(symbol: '₫', name: 'Vietnamese Dong', flag: '🇻🇳', denominations: [200, 500, 1000, 2000, 5000, 10000, 20000, 50000, 100000, 200000, 500000]),
  'NZD': CurrencyInfo(symbol: 'NZ\$', name: 'New Zealand Dollar', flag: '🇳🇿', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'BRL': CurrencyInfo(symbol: 'R\$', name: 'Brazilian Real', flag: '🇧🇷', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'MXN': CurrencyInfo(symbol: '\$', name: 'Mexican Peso', flag: '🇲🇽', denominations: [1, 2, 5, 10, 20, 50, 100]),
  'RUB': CurrencyInfo(symbol: '₽', name: 'Russian Ruble', flag: '🇷🇺', denominations: [1, 2, 5, 10, 50, 100, 200, 500, 1000, 2000, 5000]),
  'ZAR': CurrencyInfo(symbol: 'R', name: 'South African Rand', flag: '🇿🇦', denominations: [1, 2, 5, 10, 20, 50, 100, 200]),
  'AED': CurrencyInfo(symbol: 'د.إ', name: 'UAE Dirham', flag: '🇦🇪', denominations: [1, 5, 10, 25, 50, 100, 200, 500, 1000]),
  'SAR': CurrencyInfo(symbol: '﷼', name: 'Saudi Riyal', flag: '🇸🇦', denominations: [1, 5, 10, 50, 100, 500]),
  'TRY': CurrencyInfo(symbol: '₺', name: 'Turkish Lira', flag: '🇹🇷', denominations: [1, 5, 10, 25, 50, 100, 200]),
};
