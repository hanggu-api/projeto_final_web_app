import '../lib/core/utils/test_data_generator.dart';

void main() {
  print('=== GERADOR DE DADOS DE TESTE (101 SERVICE) ===\n');
  
  for (int i = 0; i < 5; i++) {
    final profile = TestDataGenerator.generateDriverProfile();
    print('Motorista #${i + 1}:');
    print('  Nome: ${profile['full_name']}');
    print('  CPF: ${profile['cpf']}');
    print('  Email: ${profile['email']}');
    print('  Tel: ${profile['phone']}');
    print('  Data Nasc: ${profile['birth_date']}');
    print('');
  }
  
  print('Dica: Use estes dados para os campos do formulário de registro.');
}
