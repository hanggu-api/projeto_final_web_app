import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/central_service.dart';
import '../../core/utils/payment_audit_logger.dart';
import '../payment/models/pix_payment_contract.dart';

class PaymentScreen extends StatefulWidget {
  final dynamic extraData;

  const PaymentScreen({super.key, this.extraData});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedMethod = 'pix';
  final CentralService _paymentService = CentralService();

  late String _serviceId;
  late double _amount;
  late String _paymentType; // 'deposit' or 'remaining'
  double _totalAmount = 0.0;
  double _depositAmount = 0.0;
  bool _isFixed = false;
  String _entityType = 'service_mobile'; // service_mobile | service_fixed
  String? _argumentError;

  String? _providerName;

  bool get _isFixedRemainingBlocked {
    return _entityType == 'service_fixed' && _paymentType == 'remaining';
  }

  bool get _isDirectProviderMethod {
    switch (_selectedMethod.trim().toLowerCase()) {
      case 'pix_direct':
      case 'pix direto':
      case 'cash':
      case 'dinheiro':
      case 'dinheiro/direto':
      case 'card_machine':
        return true;
      default:
        return false;
    }
  }

  String _normalizeInitialMethod(Object? raw) {
    final normalized = (raw ?? '').toString().trim().toLowerCase();
    if (normalized.isEmpty) return 'pix';
    if (normalized == 'pix' || normalized == 'pix_platform') return 'pix';
    if (normalized == 'pix_direct' || normalized == 'pix direto') {
      return 'pix_direct';
    }
    if (normalized == 'cash' ||
        normalized == 'dinheiro' ||
        normalized == 'dinheiro/direto') {
      return 'cash';
    }
    if (normalized.startsWith('card_machine')) return 'card_machine';
    return 'pix';
  }

  @override
  void initState() {
    super.initState();
    _parseArguments();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      // Em testes/fluxos legados pode não existir sessão Supabase ativa.
      if (!ApiService().isLoggedIn) return;
      final profile = await ApiService().getProfile();
      if (profile['success'] == true && profile['user'] != null) {
        // Dados carregados com sucesso
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
    }
  }

  void _parseArguments() {
    final data = widget.extraData;
    if (data is Map) {
      _serviceId = data['serviceId']?.toString() ?? '';
      _paymentType = data['type']?.toString() ?? '';
      _amount = double.tryParse(data['amount']?.toString() ?? '') ?? 0.0;
      _totalAmount = data.containsKey('total')
          ? (double.tryParse(data['total']?.toString() ?? '') ?? _amount)
          : _amount;

      if (data['initialMethod'] != null) {
        _selectedMethod = _normalizeInitialMethod(data['initialMethod']);
      }

      if (data.containsKey('isFixed')) {
        _isFixed = data['isFixed'] == true || data['isFixed'] == 'true';
      }
      final rawEntityType = (data['entityType'] ?? '').toString().trim();
      if (rawEntityType == 'service_fixed' ||
          rawEntityType == 'service_mobile') {
        _entityType = rawEntityType;
      } else {
        _entityType = _isFixed ? 'service_fixed' : 'service_mobile';
      }
      _selectedMethod = _normalizeInitialMethod(
        data['initialMethod'] ?? _selectedMethod,
      );
      _providerName = data['providerName']?.toString();
    } else {
      _serviceId = data?.toString() ?? '';
      _paymentType = '';
      _amount = 0.0;
      _totalAmount = _amount;
      _entityType = 'service_mobile';
    }
    _isFixed = _entityType == 'service_fixed' || _isFixed;
    _depositAmount = _amount;
    _validateArguments();
  }

  void _validateArguments() {
    if (_serviceId.trim().isEmpty) {
      _argumentError = 'ID do serviço ausente para abrir o pagamento.';
      return;
    }
    if (_paymentType != 'deposit' && _paymentType != 'remaining') {
      _argumentError =
          'Tipo de pagamento inválido. Reabra o fluxo a partir do serviço.';
      return;
    }
    if (_amount <= 0) {
      _argumentError =
          'Valor do pagamento inválido. Reabra o fluxo a partir do serviço.';
      return;
    }
    _argumentError = null;
  }

  bool _isLoading = false;

  String _resolvePixSuccessRoute() {
    if (_paymentType == 'remaining') {
      return '/home';
    }
    if (_isFixed) {
      return '/home';
    }
    return '/service-tracking/$_serviceId';
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _processPayment() async {
    if (_argumentError != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_argumentError!)));
      return;
    }
    if (_isFixedRemainingBlocked) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O pagamento restante do serviço fixo é feito diretamente ao prestador no local.',
            ),
          ),
        );
      }
      return;
    }

    if (_serviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro: ID do serviço não fornecido')),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      if (_isDirectProviderMethod) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este fluxo usa pagamento direto ao prestador. Nenhum QR do app será gerado.',
            ),
          ),
        );
        context.go(_resolvePixSuccessRoute());
        return;
      }

      if (_selectedMethod == 'pix') {
        final pixData = await _paymentService.getPixData(
          _serviceId,
          entityType: 'service',
          paymentStage: _paymentType == 'remaining' ? 'remaining' : 'deposit',
        );
        final reasonCode = (pixData['reason_code'] ?? '').toString().trim();
        final traceId = (pixData['trace_id'] ?? '').toString().trim();
        if (reasonCode == 'RESOURCE_NOT_FOUND') {
          PaymentAuditLogger.logServicePaymentEvent(
            serviceId: _serviceId,
            event: 'pix_resource_scope_mismatch',
            traceId: traceId.isNotEmpty ? traceId : null,
            extra: {
              'scope': _isFixed ? 'fixed' : 'mobile',
              'entity_type': _entityType,
              'route': '/payment/$_serviceId',
              'payment_type': _paymentType,
              'reason_code': reasonCode,
              'source': 'payment_screen',
            },
          );
        }
        if (pixData['success'] == false ||
            (pixData['error']?.toString().trim().isNotEmpty ?? false)) {
          final errorMap = Map<String, dynamic>.from(pixData);
          throw ApiException(
            message: (errorMap['error'] ?? 'Falha ao gerar PIX').toString(),
            statusCode: int.tryParse('${errorMap['status_code'] ?? ''}') ?? 400,
            details: errorMap,
          );
        }
        // Compat: `getPixData` pode retornar:
        // - wrapper `{ success, pix: {...} }` (antigo)
        // - o próprio mapa `pix` (atual no CentralService)
        final dynamic pix = (pixData['pix'] is Map) ? pixData['pix'] : pixData;

        final hasAnyPixPayload =
            pix is Map &&
            ((pix['copy_and_paste']?.toString().trim().isNotEmpty ?? false) ||
                (pix['payload']?.toString().trim().isNotEmpty ?? false) ||
                (pix['encodedImage']?.toString().trim().isNotEmpty ?? false) ||
                (pix['image_url']?.toString().trim().isNotEmpty ?? false));

        if (hasAnyPixPayload) {
          if (mounted) {
            setState(() => _isLoading = false);
            await context.push(
              '/pix-payment',
              extra: PixPaymentArgs(
                resourceId: _serviceId,
                title: _paymentType == 'remaining'
                    ? 'Pagamento restante'
                    : _isFixed
                    ? 'Pagamento do agendamento'
                    : 'Pagamento do serviço',
                description: _paymentType == 'remaining'
                    ? 'Conclua o Pix para finalizar o pagamento do serviço.'
                    : _isFixed
                    ? 'Conclua o Pix para confirmar o agendamento.'
                    : 'Conclua o Pix para liberar o acompanhamento do serviço.',
                providerName: _providerName,
                serviceLabel: _entityType == 'service_fixed'
                    ? 'agendamento intermediado'
                    : 'serviço intermediado',
                fiscalDescription: _paymentType == 'remaining'
                    ? 'Este Pix corresponde à liquidação final intermediada do serviço associado a ${(_providerName ?? 'prestador parceiro').trim()}. O pagamento é descrito para apoiar a conciliação operacional e tributária da cobrança.'
                    : _isFixed
                    ? 'Este Pix corresponde à taxa de intermediação e reserva do agendamento com ${(_providerName ?? 'salão parceiro').trim()}. O valor é identificado pela plataforma para conciliação e tributação da intermediação.'
                    : 'Este Pix corresponde ao sinal de intermediação do serviço solicitado pelo cliente junto a ${(_providerName ?? 'prestador parceiro').trim()}. O valor é recebido e descrito para conciliação e enquadramento tributário da intermediação.',
                qrCode: (pix['copy_and_paste'] ?? pix['payload'] ?? '')
                    .toString(),
                qrCodeImage: (pix['encodedImage'] ?? pix['image_url'] ?? '')
                    .toString(),
                amount: _amount,
                successRoute: _resolvePixSuccessRoute(),
                statusSource: 'service',
                paymentStage: _paymentType == 'remaining'
                    ? 'remaining'
                    : 'deposit',
              ),
            );
          }
        } else {
          final err = pixData['error'] ?? 'Falha ao gerar código PIX';
          throw Exception(err);
        }
      }
    } catch (e) {
      debugPrint('Erro no processamento de pagamento: $e');
      if (mounted) {
        int statusCode = 0;
        String errorMsg = 'Falha ao processar pagamento.';
        String traceId = '';

        if (e is ApiException) {
          statusCode = e.statusCode;
          errorMsg = e.message.trim().isNotEmpty
              ? e.message.trim()
              : 'Falha ao processar pagamento.';
          final details = e.details ?? const <String, dynamic>{};
          traceId = (details['trace_id'] ?? '').toString().trim();
        } else {
          final raw = e.toString();
          if (raw.contains('Exception:')) {
            errorMsg = raw.split('Exception:').last.trim();
          } else if (raw.trim().isNotEmpty) {
            errorMsg = raw.trim();
          }
          final traceMatch = RegExp(
            r'trace:\\s*([a-zA-Z0-9-]+)',
          ).firstMatch(raw);
          traceId = (traceMatch?.group(1) ?? '').trim();
          final statusMatch = RegExp(r'Status:\\s*(\\d+)').firstMatch(raw);
          statusCode = int.tryParse(statusMatch?.group(1) ?? '') ?? 0;
        }

        if (statusCode == 403) {
          errorMsg =
              'Acesso negado para gerar PIX desta solicitação. Faça login novamente e tente manualmente.';
        }
        if (traceId.isNotEmpty) {
          errorMsg = '$errorMsg (trace: $traceId)';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Pagamento',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (Navigator.canPop(context)) {
              Navigator.pop(context);
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            Container(
              height: 120,
              decoration: BoxDecoration(
                color: Theme.of(context).primaryColor,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(32),
                  bottomRight: Radius.circular(32),
                ),
              ),
            ),
            SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (_argumentError != null) ...[
                    _buildArgumentErrorCard(),
                    const SizedBox(height: 24),
                  ],
                  _buildProviderHeader(),
                  const SizedBox(height: 16),
                  _buildAmountCard(),
                  if (_isFixedRemainingBlocked) ...[
                    const SizedBox(height: 16),
                    _buildFixedRemainingBlockedCard(),
                    const SizedBox(height: 24),
                    _buildBackHomeButton(),
                    const SizedBox(height: 80),
                  ] else ...[
                    _buildRemainingInfo(),
                    const SizedBox(height: 24),
                    if (_isDirectProviderMethod) ...[
                      _buildDirectPaymentInfoCard(),
                    ] else ...[
                      const Text(
                        'Escolha o método',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.black,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildMethodCard(
                        'pix',
                        'Pix',
                        'Instantâneo e Seguro',
                        LucideIcons.qrCode,
                      ),
                    ],
                    const SizedBox(height: 40),
                    _buildSubmitButton(),
                    const SizedBox(height: 80),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProviderHeader() {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: Colors.black.withOpacity(0.1),
          child: const Icon(LucideIcons.user, color: Colors.black),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Prestador selecionado',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            Text(
              _providerName ?? 'Busca Automática',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: Colors.black,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildArgumentErrorCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.red.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Pagamento indisponível',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w800,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _argumentError!,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    final buttonText = _isDirectProviderMethod
        ? 'Continuar'
        : _paymentType == 'remaining'
        ? 'Pagar Restante com Pix'
        : 'Pagar com Pix';
    return ElevatedButton(
      key: const Key('pay_button'),
      onPressed: _isLoading ? null : _processPayment,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryBlue,
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
      ),
      child: _isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : Text(
              buttonText,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
    );
  }

  Widget _buildDirectPaymentInfoCard() {
    final subtitle = _selectedMethod == 'pix_direct'
        ? 'O prestador vai compartilhar a chave ou QR diretamente com você. O app não gera esse código.'
        : 'Esse pagamento é combinado diretamente com o prestador, fora do QR do app.';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(LucideIcons.wallet, color: Colors.black, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pagamento direto ao prestador',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            subtitle,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackHomeButton() {
    return OutlinedButton(
      onPressed: () => context.go('/home'),
      style: OutlinedButton.styleFrom(
        foregroundColor: AppTheme.primaryBlue,
        minimumSize: const Size(double.infinity, 56),
        side: BorderSide(color: AppTheme.primaryBlue.withOpacity(0.3)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      child: const Text(
        'Voltar para a Home',
        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      ),
    );
  }

  Widget _buildMethodCard(
    String methodId,
    String title,
    String subtitle,
    IconData icon,
  ) {
    final bool isSelected = _selectedMethod == methodId;
    return GestureDetector(
      onTap: () => setState(() => _selectedMethod = methodId),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Theme.of(context).primaryColor : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey[200]!,
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? Colors.black.withOpacity(0.1)
                    : Colors.grey[100],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: isSelected ? Colors.black : Colors.grey),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: isSelected ? Colors.black54 : Colors.grey,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                LucideIcons.checkCircle,
                color: Colors.black,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    final amountTitle = _isFixedRemainingBlocked
        ? 'Pagamento presencial ao prestador'
        : _paymentType == 'remaining'
        ? (_isFixed ? 'Valor a pagar no local (90%)' : 'Valor Restante (70%)')
        : (_isFixed ? 'Taxa de agendamento (10%)' : 'Valor da Entrada');
    final amountValue = _paymentType == 'remaining' ? _amount : _depositAmount;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          Text(
            amountTitle,
            style: TextStyle(
              color: Colors.black54,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'R\$ ${amountValue.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(
              color: Colors.black,
              fontSize: 48,
              fontWeight: FontWeight.w900,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.grey.shade300, width: 1),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(LucideIcons.shieldCheck, color: Colors.black, size: 16),
                SizedBox(width: 8),
                Text(
                  'Pagamento Seguro',
                  style: TextStyle(
                    color: Colors.black,
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRemainingInfo() {
    if (_paymentType == 'remaining') return const SizedBox.shrink();

    final double remaining = _totalAmount - _depositAmount;
    return Container(
      margin: const EdgeInsets.only(top: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withOpacity(0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              LucideIcons.wallet,
              color: Colors.orange,
              size: 24,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Valor Restante',
                  style: TextStyle(
                    color: Colors.black54,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                Text(
                  'R\$ ${remaining.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _isFixed
                      ? 'Será pago diretamente ao prestador no local do serviço'
                      : 'Será pago diretamente ao prestador após a conclusão (Exclusivo PIX)',
                  style: const TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.w400,
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFixedRemainingBlockedCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(LucideIcons.alertTriangle, color: Colors.black, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Pagamento final fora do app',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: Colors.black,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Text(
            'Para agendamentos em estabelecimento, o app cobra apenas a taxa inicial via Pix. O valor restante deve ser pago diretamente ao prestador no local.',
            style: TextStyle(color: Colors.black87, fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 12),
          Text(
            'Valor de referência: R\$ ${_amount.toStringAsFixed(2).replaceAll('.', ',')}',
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black,
            ),
          ),
        ],
      ),
    );
  }
}
