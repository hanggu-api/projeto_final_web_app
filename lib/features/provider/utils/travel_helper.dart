class TravelHelper {
  /// Calcula o custo estimado de combustível para carro
  /// Baseado em uma média de 12km/l
  static double calculateCarCost(double distanceKm, double fuelPrice) {
    if (distanceKm <= 0 || fuelPrice <= 0) return 0.0;
    return (distanceKm / 12.0) * fuelPrice;
  }

  /// Calcula o custo estimado de combustível para moto
  /// Baseado em uma média de 35km/l
  static double calculateMotoCost(double distanceKm, double fuelPrice) {
    if (distanceKm <= 0 || fuelPrice <= 0) return 0.0;
    return (distanceKm / 35.0) * fuelPrice;
  }

  /// Formata a distância para exibição (ex: 5.23 km)
  static String formatDistance(double km) {
    return km.toStringAsFixed(2);
  }

  /// Formata a duração para exibição (ex: 15 min)
  static String formatDuration(double min) {
    return min.toStringAsFixed(0);
  }

  /// Formata valor monetário (ex: 25.50)
  static String formatCost(double cost) {
    return cost.toStringAsFixed(2);
  }
}
