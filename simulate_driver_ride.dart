import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

Future<void> main() async {
  print('🚀 Iniciando Simulação de Corrida e Pagamento...');
  
  // 1. Carregar Configurações
  await dotenv.load(fileName: '.env');
  final url = dotenv.env['SUPABASE_URL']!;
  final key = dotenv.env['SUPABASE_ANON_KEY']!;
  
  final supa = SupabaseClient(url, key);

  // 2. Identificar Motorista (User 143 - Irismar)
  final driverId = 143; 
  print('👤 Motorista: IRISMAR MENEZES SILVA (ID: $driverId)');

  try {
    // 3. Garantir que o motorista está online
    await supa.from('providers').update({'is_online': true}).eq('user_id', driverId);
    print('✅ Motorista está ONLINE.');

    // 4. Buscar uma corrida pendente (a mais recente) ou criar uma de teste
    print('🔍 Buscando corridas pendentes...');
    final trips = await supa
        .from('trips')
        .select('*')
        .eq('status', 'searching')
        .order('created_at', ascending: false)
        .limit(1);

    Map<String, dynamic> trip;
    if (trips.isEmpty) {
      print('ℹ️ Nenhuma corrida pendente encontrada. Criando uma corrida de teste...');
      // Usar um cliente de teste (User 142 - se existir, ou qualquer um)
      // Para o teste ser perfeito, precisaríamos de uma conta Mercado Pago vinculada ao cliente.
      // Como o objetivo é testar o fluxo do MOTORISTA recebendo, vamos tentar encontrar uma com 'Cartão (Plataforma)'
      final newTrip = await supa.from('trips').insert({
        'client_id': 142, // Cliente de teste
        'pickup_address': 'Rua de Teste, 123',
        'dropoff_address': 'Destino de Teste, 456',
        'estimated_price': 25.50,
        'status': 'searching',
        'payment_method': 'Cartão (Plataforma)',
        'pickup_latitude': -5.5163,
        'pickup_longitude': -47.4670,
        'dropoff_latitude': -5.5257,
        'dropoff_longitude': -47.4491,
      }).select().single();
      trip = newTrip;
      print('✅ Corrida de teste criada: ID ${trip['id']}');
    } else {
      trip = trips.first;
      print('✅ Corrida encontrada: ID ${trip['id']}');
    }

    final tripId = trip['id'];

    // 5. Aceitar Corrida (Chamar Edge Function ou update direto se RLS permitir)
    print('📌 Aceitando a corrida $tripId...');
    // Simulando o aceite via update de status
    await supa.from('trips').update({
      'driver_id': driverId,
      'status': 'accepted',
      'accepted_at': DateTime.now().toIso8601String(),
    }).eq('id', tripId);
    print('✅ Corrida ACEITA.');

    // 6. Embarque do Passageiro
    print('⏳ Aguardando simulação de embarque...');
    await Future.delayed(Duration(seconds: 2));
    await supa.from('trips').update({
      'status': 'in_progress',
      'started_at': DateTime.now().toIso8601String(),
    }).eq('id', tripId);
    print('✅ Passageiro EMBARCADO (Status: in_progress)');

    // 7. Finalizar Corrida (Desembarque)
    print('⏳ Aguardando simulação de trajeto...');
    await Future.delayed(Duration(seconds: 3));
    print('🏁 Finalizando corrida...');
    
    // IMPORTANTE: Aqui é onde o backend deve capturar o pagamento
    // A Edge Function 'update-trip-status' deveria ser chamada, mas vamos simular o update
    // Se houver um trigger ou se a lógica for no status change, ela deve disparar.
    await supa.from('trips').update({
      'status': 'completed',
      'completed_at': DateTime.now().toIso8601String(),
    }).eq('id', tripId);

    print('✅ Corrida FINALIZADA com sucesso.');

    // 8. Verificar Pagamento
    print('💳 Verificando status do pagamento...');
    final payment = await supa
        .from('payments')
        .select('*')
        .eq('trip_id', tripId)
        .maybeSingle();

    if (payment != null) {
      print('💰 Registro de Pagamento Encontrado:');
      print('   - ID: ${payment['id']}');
      print('   - Valor: R\$ ${payment['amount']}');
      print('   - Status: ${payment['status']}');
      print('   - MP Payment ID: ${payment['mp_payment_id']}');
      
      if (payment['status'] == 'success') {
        print('✨ SUCESSO! O pagamento foi processado e capturado via Mercado Pago.');
      } else {
        print('⚠️ O pagamento está com status: ${payment['status']}. Verifique logs do Mercado Pago.');
      }
    } else {
      print('❌ Registro de pagamento não encontrado na tabela payments.');
    }

  } catch (e) {
    print('❌ Erro durante a simulação: $e');
  }
}
