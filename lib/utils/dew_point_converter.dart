class DewPointConverter {
  // Lookup table: Dew Point (°C) -> Corrected Sonntag (ppmv)
  // Source: User provided table
  static final Map<int, int> _table = {
    -1: 5515,
    -2: 5125,
    -3: 4760,
    -4: 4417,
    -5: 4097,
    -6: 3798,
    -7: 3518,
    -8: 3257,
    -9: 3013,
    -10: 2786,
    -11: 2574,
    -12: 2376,
    -13: 2192,
    -14: 2021,
    -15: 1862,
    -16: 1714,
    -17: 1577,
    -18: 1450,
    -19: 1332,
    -20: 1222,
    -21: 1121,
    -22: 1028,
    -23: 941,
    -24: 861,
    -25: 787,
    -26: 719,
    -27: 656,
    -28: 599,
    -29: 545,
    -30: 497,
    -31: 452,
    -32: 410,
    -33: 373,
    -34: 338,
    -35: 306,
    -36: 277,
    -37: 251,
    -38: 227,
    -39: 205,
    -40: 185,
    -41: 166,
    -42: 150,
    -43: 135,
    -44: 121,
    -45: 108,
    -46: 97,
    -47: 87,
    -48: 78,
    -49: 69,
    -50: 62,
    -51: 56,
    -52: 49,
    -53: 44,
    -54: 39,
    -55: 34,
    -56: 30,
    -57: 27,
    -58: 24,
    -59: 21,
    -60: 18,
    -61: 16,
    -62: 14,
    -63: 12,
    -64: 11,
    -65: 10,
    -66: 8,
    -67: 7,
    // -68: 7, // User image ambiguous, but let's interpolate between 67(7) and 69(6) if needed.
    // Actually blindly trusting 7, 7, 6, 5 sequence is safer.
    -68: 7,
    -69: 6,
    -70: 5,
  };

  static String getPpmString(double dewPoint) {
    // If warmer than -1, table doesn't cover. Extrapolate or clamp?
    // Table starts at -1. Let's return '> 5515' or similar if > -1?
    // Or just clamp to nearest.
    if (dewPoint > -1.0) {
      // For now, use the value for -1 or calculate?
      // Given specific request for table compliance, let's clamp.
      return '> 5515 ppm';
    }

    if (dewPoint < -70.0) {
      return '< 5 ppm';
    }

    final int t1 = dewPoint.floor(); // e.g. -43.1 -> -44
    final int t2 = dewPoint.ceil(); // e.g. -43.1 -> -43

    if (t1 == t2) {
      // Exact integer match
      return '${_table[t1] ?? "--"} ppm';
    }

    final int? p1 = _table[t1];
    final int? p2 = _table[t2];

    if (p1 == null || p2 == null) {
      return '-- ppm'; // Should not happen within range
    }

    // Linear Interpolation
    // p = p1 + (dewPoint - t1) * (p2 - p1) / (t2 - t1)
    // t2 - t1 is always 1 for consecutive integers.
    // So p = p1 + (dewPoint - t1) * (p2 - p1)
    final double fraction = dewPoint - t1;
    final double ppm = p1.toDouble() + fraction * (p2 - p1);

    return '${ppm.round()} ppm';
  }
}
