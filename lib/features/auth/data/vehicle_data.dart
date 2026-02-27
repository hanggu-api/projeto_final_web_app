/// Dados de veículos populares no Brasil para autocomplete
class VehicleData {
  // ========== CARROS ==========
  static const Map<String, List<String>> carBrands = {
    'Chevrolet': [
      'Onix', 'Onix Plus', 'Tracker', 'Spin', 'Cruze', 'S10', 'Montana',
      'Joy', 'Equinox', 'Trailblazer', 'Prisma', 'Cobalt', 'Celta', 'Corsa',
      'Agile', 'Classic', 'Astra',
    ],
    'Volkswagen': [
      'Gol', 'Polo', 'Virtus', 'T-Cross', 'Nivus', 'Saveiro', 'Voyage',
      'Fox', 'Up!', 'Golf', 'Jetta', 'Tiguan', 'Amarok', 'Taos',
    ],
    'Fiat': [
      'Uno', 'Mobi', 'Argo', 'Cronos', 'Strada', 'Toro', 'Pulse',
      'Fastback', 'Palio', 'Siena', 'Grand Siena', 'Bravo', 'Punto',
      'Doblò', 'Fiorino', 'Ducato',
    ],
    'Ford': [
      'Ka', 'Ka+', 'EcoSport', 'Ranger', 'Territory', 'Bronco Sport',
      'Maverick', 'Fiesta', 'Focus', 'Fusion',
    ],
    'Hyundai': [
      'HB20', 'HB20S', 'Creta', 'Tucson', 'ix35', 'Santa Fe',
      'HB20X', 'Azera', 'Elantra', 'Veloster',
    ],
    'Toyota': [
      'Corolla', 'Corolla Cross', 'Yaris', 'Hilux', 'SW4', 'RAV4',
      'Etios', 'Camry', 'Prius',
    ],
    'Honda': [
      'Civic', 'City', 'HR-V', 'CR-V', 'Fit', 'WR-V', 'ZR-V',
      'Accord',
    ],
    'Renault': [
      'Kwid', 'Sandero', 'Logan', 'Duster', 'Captur', 'Oroch',
      'Stepway', 'Clio', 'Fluence',
    ],
    'Nissan': [
      'Kicks', 'Versa', 'Sentra', 'March', 'Frontier', 'X-Trail',
    ],
    'Jeep': [
      'Renegade', 'Compass', 'Commander', 'Gladiator', 'Wrangler',
    ],
    'Citroën': [
      'C3', 'C4 Cactus', 'Aircross', 'C3 Aircross', 'Berlingo',
    ],
    'Peugeot': [
      '208', '2008', '3008', '308', '408',
    ],
    'Kia': [
      'Sportage', 'Cerato', 'Seltos', 'Stonic', 'Carnival',
    ],
    'Mitsubishi': [
      'L200', 'Outlander', 'Eclipse Cross', 'ASX', 'Pajero',
    ],
    'Caoa Chery': [
      'Tiggo 2', 'Tiggo 3X', 'Tiggo 5X', 'Tiggo 7', 'Tiggo 8', 'Arrizo 6',
    ],
    'RAM': [
      'Rampage', '1500', '2500', '3500',
    ],
    'BYD': [
      'Dolphin', 'Yuan Plus', 'Song Plus', 'Han', 'Tan', 'Seal',
    ],
    'GWM': [
      'Haval H6', 'Ora 03',
    ],
  };

  // ========== MOTOS ==========
  static const Map<String, List<String>> motoBrands = {
    'Honda': [
      'CG 160', 'Fan 160', 'Biz 125', 'Pop 110i', 'Bros 160',
      'CB 300F', 'CB 500F', 'CB 500X', 'CB 650R', 'CBR 650R',
      'PCX 160', 'Elite 125', 'ADV 150', 'XRE 190', 'XRE 300',
      'Sahara 300', 'Hornet',
    ],
    'Yamaha': [
      'Factor 150', 'Fazer 150', 'Fazer 250', 'YBR 150',
      'XTZ 150 Crosser', 'XTZ 250 Ténéré', 'Lander 250',
      'MT-03', 'MT-07', 'MT-09', 'R3', 'NMAX 160', 'NEO 125',
      'Fluo 125',
    ],
    'Suzuki': [
      'Intruder 125', 'Haojue DK 150', 'V-Strom 650',
      'GSX-S750', 'Burgman 125',
    ],
    'BMW': [
      'G 310 R', 'G 310 GS', 'F 850 GS', 'R 1250 GS',
      'S 1000 RR',
    ],
    'Kawasaki': [
      'Ninja 400', 'Z400', 'Z650', 'Z900', 'Versys 650',
      'Versys 1000',
    ],
    'Dafra': [
      'Apache 200', 'NH 190', 'Zig 50',
    ],
    'Shineray': [
      'Jet 125', 'Worker 150', 'Phoenix 50',
    ],
  };

  // ========== CORES ==========
  static const List<Map<String, dynamic>> colors = [
    {'name': 'Preto', 'hex': 0xFF000000},
    {'name': 'Branco', 'hex': 0xFFFFFFFF},
    {'name': 'Prata', 'hex': 0xFFC0C0C0},
    {'name': 'Cinza', 'hex': 0xFF808080},
    {'name': 'Vermelho', 'hex': 0xFFE53935},
    {'name': 'Azul', 'hex': 0xFF1E88E5},
    {'name': 'Azul Escuro', 'hex': 0xFF1A237E},
    {'name': 'Verde', 'hex': 0xFF43A047},
    {'name': 'Amarelo', 'hex': 0xFFFDD835},
    {'name': 'Dourado', 'hex': 0xFFFFD700},
    {'name': 'Bege', 'hex': 0xFFF5F5DC},
    {'name': 'Marrom', 'hex': 0xFF795548},
    {'name': 'Vinho', 'hex': 0xFF880E4F},
    {'name': 'Laranja', 'hex': 0xFFFF6D00},
    {'name': 'Rosa', 'hex': 0xFFE91E63},
  ];

  // ========== ANOS ==========
  static List<int> get years {
    final currentYear = DateTime.now().year;
    return List.generate(30, (i) => currentYear + 1 - i); // 2027 até 1998
  }

  /// Retorna marcas baseado no tipo de veículo
  static Map<String, List<String>> getBrands(bool isMoto) {
    return isMoto ? motoBrands : carBrands;
  }

  /// Retorna modelos da marca
  static List<String> getModels(String brand, bool isMoto) {
    final brands = isMoto ? motoBrands : carBrands;
    return brands[brand] ?? [];
  }
}
