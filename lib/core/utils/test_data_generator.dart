import 'dart:math';

class TestDataGenerator {
  static final Random _random = Random();

  /// Lista de CPFs fictícios válidos fornecidos pelo usuário
  static const List<String> fictionaryCpfs = [
    '11144477735',
    '22233344405',
    '33355566605',
    '44466688809',
    '55577799909',
    '66688811136',
    '77799922240',
    '88811133396',
    '99922244470',
    '12345678909',
  ];

  static const List<String> _firstNames = [
    'João', 'Maria', 'José', 'Ana', 'Pedro', 'Paula', 'Lucas', 'Juliana',
    'Gabriel', 'Larissa', 'Marcos', 'Fernanda', 'Ricardo', 'Beatriz', 'André',
    'Camila', 'Felipe', 'Letícia', 'Bruno', 'Renata', 'Gustavo', 'Amanda',
    'Diego', 'Tatiana', 'Rafael', 'Vanessa', 'Leonardo', 'Priscila', 'Thiago', 'Sonia'
  ];

  static const List<String> _lastNames = [
    'Silva', 'Santos', 'Oliveira', 'Souza', 'Rodrigues', 'Ferreira', 'Alves',
    'Pereira', 'Lima', 'Gomes', 'Costa', 'Ribeiro', 'Martins', 'Carvalho',
    'Teixeira', 'Barbosa', 'Melo', 'Castro', 'Cardoso', 'Fernandes', 'Vieira',
    'Nascimento', 'Moreira', 'Aguiar', 'Batista', 'Cavalcanti', 'Dias', 'Freitas'
  ];

  /// Retorna um CPF aleatório da lista de fictícios ou gera um novo (algoritmo)
  static String generateCpf({bool formatted = false}) {
    // 50% de chance de pegar um da lista do usuário
    if (_random.nextBool()) {
      final cpf = fictionaryCpfs[_random.nextInt(fictionaryCpfs.length)];
      return formatted ? _formatCpf(cpf) : cpf;
    }

    // Gerar via algoritmo
    List<int> digits = List.generate(9, (_) => _random.nextInt(10));
    
    // Primeiro dígito verificador
    int d1 = 0;
    for (int i = 0; i < 9; i++) {
      d1 += digits[i] * (10 - i);
    }
    d1 = 11 - (d1 % 11);
    if (d1 >= 10) d1 = 0;
    digits.add(d1);

    // Segundo dígito verificador
    int d2 = 0;
    for (int i = 0; i < 10; i++) {
      d2 += digits[i] * (11 - i);
    }
    d2 = 11 - (d2 % 11);
    if (d2 >= 10) d2 = 0;
    digits.add(d2);

    final raw = digits.join();
    return formatted ? _formatCpf(raw) : raw;
  }

  static String _formatCpf(String cpf) {
    if (cpf.length != 11) return cpf;
    return '${cpf.substring(0, 3)}.${cpf.substring(3, 6)}.${cpf.substring(6, 9)}-${cpf.substring(9)}';
  }

  static String generateName() {
    final firstName = _firstNames[_random.nextInt(_firstNames.length)];
    final lastName1 = _lastNames[_random.nextInt(_lastNames.length)];
    final lastName2 = _lastNames[_random.nextInt(_lastNames.length)];
    return '$firstName $lastName1 $lastName2';
  }

  static String generateEmail([String? name]) {
    final base = name?.toLowerCase().replaceAll(' ', '.') ?? 'user.${_random.nextInt(10000)}';
    final domains = ['gmail.com', 'outlook.com', 'hotmail.com', 'yahoo.com', 'empresa.com.br'];
    return '$base@${domains[_random.nextInt(domains.length)]}';
  }

  static String generatePhone() {
    final ddd = [11, 21, 31, 41, 51, 61, 71, 81, 91][_random.nextInt(9)];
    final number = 900000000 + _random.nextInt(100000000);
    return '($ddd) $number';
  }

  static Map<String, dynamic> generateDriverProfile() {
    final name = generateName();
    return {
      'full_name': name,
      'email': generateEmail(name),
      'cpf': generateCpf(formatted: true),
      'phone': generatePhone(),
      'birth_date': '19${_random.nextInt(20) + 70}-0${_random.nextInt(9) + 1}-1${_random.nextInt(9) + 1}',
    };
  }
}
