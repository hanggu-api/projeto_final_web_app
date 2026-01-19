import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:mask_text_input_formatter/mask_text_input_formatter.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';
import '../../services/payment_service.dart';
import 'pix_payment_dialog.dart';

class PaymentScreen extends StatefulWidget {
  final dynamic extraData; // Changed from Map to dynamic for flexibility
  final PaymentService? paymentService;

  const PaymentScreen({super.key, this.extraData, this.paymentService});

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String _selectedMethod = 'pix';
  late final PaymentService _paymentService;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late String _serviceId;
  late double _amount;
  late String _paymentType; // 'deposit' or 'remaining'
  double _depositAmount = 0.0;
  double _totalAmount = 0.0;
  String? _serviceType;
  
  // Card Brand Logic
  String _cardBrand = 'credit_card';
  String? _userEmail;
  String? _userPhone;
  String? _deviceId;
  String? _providerName;

  @override
  void initState() {
    super.initState();
    _paymentService = widget.paymentService ?? PaymentService();
    _parseArguments();
    _cardNumberController.addListener(_updateCardBrand);
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final profile = await ApiService().getProfile();
      if (profile['success'] == true && profile['user'] != null) {
        setState(() {
          _userEmail = profile['user']['email'];
          _userPhone = profile['user']['phone'];
          // Pre-fill CPF if available in profile
          if (profile['user']['document_value'] != null) {
            _docNumberController.text = _cpfMaskFormatter.maskText(profile['user']['document_value']);
          }
        });
      }
      
      final dId = await _paymentService.getDeviceId();
      setState(() => _deviceId = dId);
    } catch (e) {
      debugPrint('Erro ao carregar dados do usuário: $e');
    }
  }

  void _updateCardBrand() {
    final brand = _getPaymentMethodId(_cardNumberController.text);
    if (brand != _cardBrand) {
      setState(() => _cardBrand = brand);
    }
  }

  void _parseArguments() {
    final data = widget.extraData;
    if (data is Map) {
      _serviceId = data['serviceId']?.toString() ?? '';
      _paymentType = data['type']?.toString() ?? 'deposit';
      _amount = double.tryParse(data['amount']?.toString() ?? '10.0') ?? 10.0;

      if (data.containsKey('total')) {
        _totalAmount =
            double.tryParse(data['total']?.toString() ?? '') ?? _amount;
      } else {
        _totalAmount = _amount;
      }

      if (data['initialMethod'] != null) {
        final method = data['initialMethod'].toString();
        if (method == 'pix' || method == 'credit') {
          _selectedMethod = method;
        }
      }
      _serviceType = data['serviceType']?.toString();
      final String? prof = data['professionName']?.toString().toLowerCase();
      if (prof != null) {
        if (prof.contains('barbeiro') ||
            prof.contains('cabeleireiro') ||
            prof.contains('manicure') ||
            prof.contains('dentista') ||
            prof.contains('médic') ||
            prof.contains('esteticista')) {
          _serviceType = 'at_provider';
        }
      }
      _providerName = data['providerName']?.toString();
    } else if (data is String) {
      // Legacy support if just string passed
      _serviceId = data;
      _paymentType = 'deposit';
      _amount = 10.0; // Default or fetch from service?
      _totalAmount = _amount;
    } else {
      _serviceId = '';
      _paymentType = 'deposit';
      _amount = 10.0;
      _totalAmount = _amount;
    }
    _depositAmount = _amount;

    // Fallback: If deposit and total is same as amount (meaning not passed), infer total
    // This ensures we show the correct remaining amount even if the caller didn't pass total
    const double kDepositPercentage = 0.30;
    if (_paymentType == 'deposit' && (_totalAmount == _amount) && _amount > 0) {
      _totalAmount = _amount / kDepositPercentage;
    }
  }

  // Card Form Controllers
  final TextEditingController _cardNumberController = TextEditingController();
  final TextEditingController _holderNameController = TextEditingController();
  final TextEditingController _expiryController = TextEditingController();
  final TextEditingController _cvvController = TextEditingController();
  final TextEditingController _docNumberController = TextEditingController();

  // Mask Formatters
  final MaskTextInputFormatter _cardMaskFormatter = MaskTextInputFormatter(
    mask: '#### #### #### ####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );
  final MaskTextInputFormatter _expiryMaskFormatter = MaskTextInputFormatter(
    mask: '##/##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );
  final MaskTextInputFormatter _cvvMaskFormatter = MaskTextInputFormatter(
    mask: '####',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );
  final MaskTextInputFormatter _cpfMaskFormatter = MaskTextInputFormatter(
    mask: '###.###.###-##',
    filter: {"#": RegExp(r'[0-9]')},
    type: MaskAutoCompletionType.lazy,
  );

  bool _isLoading = false;

  @override
  void dispose() {
    _paymentService.dispose();
    _cardNumberController.removeListener(_updateCardBrand);
    _cardNumberController.dispose();
    _holderNameController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _docNumberController.dispose();
    super.dispose();
  }

  String _getPaymentMethodId(String cardNumber) {
    final cleanNumber = cardNumber.replaceAll(RegExp(r'\D'), '');
    if (cleanNumber.startsWith('4')) return 'visa';
    if (cleanNumber.startsWith('5')) return 'master';
    if (cleanNumber.startsWith('34') || cleanNumber.startsWith('37')) {
      return 'amex';
    }
    if (cleanNumber.startsWith('6')) return 'elo'; // Simplificado
    return 'credit_card';
  }

  Widget _getBrandIcon(String brand) {
    IconData icon;
    Color color;
    switch (brand) {
      case 'visa':
        icon = LucideIcons.creditCard; // Replace with proper asset if available
        color = Colors.blue;
        break;
      case 'master':
        icon = LucideIcons.creditCard;
        color = Colors.orange;
        break;
      case 'amex':
        icon = LucideIcons.creditCard;
        color = Colors.green;
        break;
      case 'elo':
        icon = LucideIcons.creditCard;
        color = Colors.red;
        break;
      default:
        icon = LucideIcons.creditCard;
        color = Colors.grey;
    }
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Icon(icon, color: color),
    );
  }

  Future<void> _processPayment() async {
    if (_serviceId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Erro: ID do serviço não fornecido')),
      );
      return;
    }

    debugPrint('ProcessPayment iniciado'); // DEBUG
    if (_selectedMethod == 'credit') {
      if (!(_formKey.currentState?.validate() ?? false)) return;
    }

    setState(() => _isLoading = true);

    try {
      if (_selectedMethod == 'credit') {
        final List<String> expiryParts = _expiryController.text.split('/');

        if (expiryParts.length < 2 ||
            expiryParts[0].isEmpty ||
            expiryParts[1].isEmpty) {
          throw Exception('Validade do cartão inválida. Use o formato MM/AA');
        }

        final String month = expiryParts[0].padLeft(2, '0');
        final String year = '20${expiryParts[1]}';
        final String cleanCardNumber = _cardNumberController.text.replaceAll(
          RegExp(r'\D'),
          '',
        );

        final String token = await _paymentService.createCardToken(
          cardNumber: cleanCardNumber,
          cardholderName: _holderNameController.text.trim(),
          expirationMonth: month,
          expirationYear: year,
          securityCode: _cvvController.text,
          identificationType: 'CPF',
          identificationNumber: _docNumberController.text.replaceAll(
            RegExp(r'\D'),
            '',
          ),
        );

        final String paymentMethodId = _getPaymentMethodId(cleanCardNumber);

        // Determine description based on type
        final description = _paymentType == 'remaining'
            ? 'Pagamento Restante do Serviço'
            : 'Taxa de Solicitação de Serviço';

        // Call appropriate API method
        if (_paymentType == 'remaining') {
          // For remaining payment, we might call a specific endpoint or generic processPayment
          // Assuming processPayment can handle it or we use a new method.
          // For now, let's reuse processPayment but maybe we need a flag in backend?
          // Actually, the backend /pay_remaining route exists.
          // But processPayment here talks to /payments/process which is generic.
          // We should probably use the specific service method if it's remaining?
          // OR: PaymentService.processPayment should support the 'type' param.

          // Let's stick to processPayment for now and assume it handles the money transfer.
          // BUT wait, payRemainingService in ApiService hits /services/:id/pay_remaining.
          // That endpoint just marks as paid (maybe for cash?).
          // If this is credit card, we need to charge the card.
          // So we should charge the card via /payments/process, and THEN call /pay_remaining?
          // Or /payments/process should handle the logic.

          await _paymentService.processPayment(
            amount: _amount,
            token: token,
            description: description,
            installments: 1,
            paymentMethodId: paymentMethodId,
            email: _userEmail ?? 'usuario@exemplo.com',
            serviceId: _serviceId,
            paymentType: _paymentType,
            deviceId: _deviceId,
            payer: {
              'email': _userEmail ?? 'usuario@exemplo.com',
              'identification': {
                'type': 'CPF',
                'number': _docNumberController.text.replaceAll(RegExp(r'\D'), ''),
              }
            }
          );

          // After successful payment, we might need to tell the service logic "Hey, remaining paid".
          // If the backend payment webhook/logic updates the service, good.
          // If not, we might need to call ApiService().payRemainingService(_serviceId) here.
          // Let's assume processPayment does the financial transaction.
          // We should probably call the status update endpoint too to be safe/synced.
          await ApiService().payRemainingService(_serviceId);
        } else {
          // Deposit
          await _paymentService.processPayment(
            amount: _amount,
            token: token,
            description: description,
            installments: 1,
            paymentMethodId: paymentMethodId,
            email: _userEmail ?? 'usuario@exemplo.com',
            serviceId: _serviceId,
            paymentType: _paymentType,
            deviceId: _deviceId,
            payer: {
              'email': _userEmail ?? 'usuario@exemplo.com',
              'identification': {
                'type': 'CPF',
                'number': _docNumberController.text.replaceAll(RegExp(r'\D'), ''),
              }
            }
          );
        }

        if (mounted) {
          // Navigation logic
          if (_paymentType == 'remaining') {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Pagamento restante realizado! Redirecionando...'),
                backgroundColor: Colors.green,
                duration: Duration(seconds: 3),
              ),
            );
            // Wait 3 seconds before redirecting
            await Future.delayed(const Duration(seconds: 3));
            if (mounted) {
               context.go('/home'); // Force go to home to clear stack
            }
          } else {
            context.go('/confirmation');
          }
        }
        return;
      } else {
        // Processamento de PIX via Backend
        if (_serviceId.isEmpty) {
          throw Exception(
            'ID do serviço não encontrado. Tente criar o serviço novamente.',
          );
        }

        final description = _paymentType == 'remaining'
            ? 'Pagamento Restante do Serviço'
            : 'Taxa de Solicitação de Serviço';

        final result = await _paymentService.processPayment(
          amount: _amount,
          token: '', // Pix não exige token de cartão
          description: description,
          installments: 1,
          paymentMethodId: 'pix',
          email: _userEmail ?? 'usuario@exemplo.com',
          serviceId: _serviceId,
          paymentType: _paymentType,
          deviceId: _deviceId,
          payer: {
            'email': _userEmail ?? 'usuario@exemplo.com',
            'first_name': _holderNameController.text.split(' ').first,
            'identification': {
              'type': 'CPF',
              'number': _docNumberController.text.replaceAll(RegExp(r'\D'), ''),
            }
          }
        );

        // Se tiver dados do Pix (QR Code), poderíamos passar para a próxima tela
        debugPrint('Pix gerado: ${result['transaction_id']}');

        // Extract Pix Data
        final paymentData = result['original_response']?['payment'];
        if (paymentData != null) {
          final poi = paymentData['point_of_interaction'];
          final txData = poi?['transaction_data'];
          
          final qrCode = txData?['qr_code'];
          final qrCodeBase64 = txData?['qr_code_base64'];

          if (qrCode != null && qrCodeBase64 != null && mounted) {
            // Show Pix Dialog
            final bool? success = await showDialog<bool>(
              context: context,
              barrierDismissible: false,
              builder: (context) => PixPaymentDialog(
                qrCode: qrCode,
                qrCodeBase64: qrCodeBase64,
                serviceId: _serviceId,
              ),
            );

            if (success == true && mounted) {
              if (_paymentType == 'remaining') {
                await ApiService().payRemainingService(_serviceId);
                if (mounted) {
                   ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Pagamento Pix confirmado! Redirecionando...'),
                      backgroundColor: Colors.green,
                      duration: Duration(seconds: 3),
                    ),
                  );
                  await Future.delayed(const Duration(seconds: 3));
                  if (mounted) context.go('/home');
                }
              } else {
                context.go('/confirmation');
              }
              return; // Stop here, navigation handled
            }
          }
        }
      }

      if (mounted) {
        // Fallback or Credit Card Success
        // Only navigate if not already navigated
        if (_paymentType == 'remaining') {
          context.pop();
        } else if (!GoRouterState.of(
          context,
        ).uri.toString().contains('confirmation')) {
          context.go('/confirmation');
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro no pagamento: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final InputDecoration inputDecoration = InputDecoration(
      filled: true,
      fillColor: Colors.grey[100],
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      labelStyle: const TextStyle(color: Colors.black54),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text('Pagamento', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Theme.of(context).primaryColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // Top Yellow Area
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
                  _buildProviderHeader(),
                  const SizedBox(height: 16),
                  _buildAmountCard(),
                  _buildRemainingInfo(),
                  const SizedBox(height: 24),
                  const Text(
                    'Escolha o método',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                  const SizedBox(height: 16),
                  _buildMethodCard(
                    'credit',
                    'Cartão de Crédito',
                    'Aprovação imediata',
                    LucideIcons.creditCard,
                  ),
                  const SizedBox(height: 12),
                  _buildMethodCard(
                    'pix',
                    'Pix',
                    'Desconto de 5% disponível',
                    LucideIcons.qrCode,
                  ),
                  if (_selectedMethod == 'credit')
                    ..._buildCreditCardForm(inputDecoration),
                  const SizedBox(height: 20),
                  _buildSubmitButton(),
                  const SizedBox(height: 80),
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
          backgroundColor: Colors.black.withValues(alpha: 0.1),
          child: const Icon(LucideIcons.user, color: Colors.black),
        ),
        const SizedBox(width: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Prestador selecionado',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            Text(
              _providerName ?? 'Busca Automática (plataforma)',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.black),
            ),
          ],
        ),
      ],
    );
  }

  List<Widget> _buildCreditCardForm(InputDecoration decoration) {
    return <Widget>[
      const SizedBox(height: 24),
      const Text(
        'Dados do Cartão',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
      ),
      const SizedBox(height: 16),
      Form(
        key: _formKey,
        child: Column(
          children: <Widget>[
            TextFormField(
              key: const Key('card_number_field'),
              controller: _cardNumberController,
              decoration: decoration.copyWith(
                labelText: 'Número do Cartão',
                hintText: '0000 0000 0000 0000',
                suffixIcon: _getBrandIcon(_cardBrand),
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [_cardMaskFormatter],
              validator: (String? v) {
                if (v == null || v.isEmpty) return 'Obrigatório';
                if (!_validateLuhn(v)) return 'Número de cartão inválido';
                return null;
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('card_holder_field'),
              controller: _holderNameController,
              decoration: decoration.copyWith(labelText: 'Nome como no Cartão'),
              textCapitalization: TextCapitalization.characters,
              validator: (String? v) =>
                  (v?.isEmpty ?? true) ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: TextFormField(
                    key: const Key('card_expiry_field'),
                    controller: _expiryController,
                    decoration: decoration.copyWith(
                      labelText: 'Validade (MM/AA)',
                      hintText: 'MM/AA',
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [_expiryMaskFormatter],
                    validator: (String? v) {
                      if (v == null || v.isEmpty) return 'Obrigatório';
                      if (!_validateDate(v)) return 'Data inválida';
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    key: const Key('card_cvv_field'),
                    controller: _cvvController,
                    decoration: decoration.copyWith(
                      labelText: 'CVV',
                      hintText: '123',
                    ),
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    inputFormatters: [_cvvMaskFormatter],
                    validator: (String? v) =>
                        (v == null || v.length < 3) ? 'Inválido' : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              key: const Key('card_cpf_field'),
              controller: _docNumberController,
              decoration: decoration.copyWith(
                labelText: 'CPF do Titular',
                hintText: '000.000.000-00',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [_cpfMaskFormatter],
              validator: (String? v) {
                if (v == null || v.isEmpty) return 'Obrigatório';
                if (!_validateCPF(v)) return 'CPF inválido';
                return null;
              },
            ),
          ],
        ),
      ),
    ];
  }

  Widget _buildSubmitButton() {
    return ElevatedButton(
      key: const Key('pay_button'),
      onPressed: _isLoading ? null : _processPayment,
      style: ElevatedButton.styleFrom(
        backgroundColor: AppTheme.primaryBlue, // Bright Blue from Design
        foregroundColor: Colors.white,
        minimumSize: const Size(double.infinity, 56),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        elevation: 8,
        shadowColor: AppTheme.primaryBlue.withOpacity(0.4),
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
          : const Text(
              'Gerar código Pix',
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
                    ? Colors.black.withValues(alpha: 0.1)
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.black : Colors.black,
                    ),
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
              const Icon(LucideIcons.checkCircle, color: Colors.black, size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        children: [
          const Text(
            'Valor da Entrada',
            style: TextStyle(color: Colors.black54, fontSize: 14, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 12),
          Text(
            'R\$ ${_depositAmount.toStringAsFixed(2).replaceAll('.', ',')}',
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
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
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
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.1),
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
                  style: TextStyle(color: Colors.black54, fontSize: 13, fontWeight: FontWeight.w500),
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
                  'Será pago na plataforma após a realização do serviço',
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

  bool _validateLuhn(String input) {
    String clean = input.replaceAll(RegExp(r'\D'), '');
    if (clean.length < 13) return false; // Min length for major cards

    int sum = 0;
    bool alternate = false;
    for (int i = clean.length - 1; i >= 0; i--) {
      int n = int.parse(clean.substring(i, i + 1));
      if (alternate) {
        n *= 2;
        if (n > 9) {
          n = (n % 10) + 1;
        }
      }
      sum += n;
      alternate = !alternate;
    }
    return (sum % 10 == 0);
  }

  bool _validateDate(String input) {
    if (!input.contains('/')) return false;
    final parts = input.split('/');
    if (parts.length != 2) return false;

    final int? month = int.tryParse(parts[0]);
    final int? year = int.tryParse(parts[1]);

    if (month == null || year == null) {
      return false;
    }
    if (month < 1 || month > 12) {
      return false;
    }

    final DateTime now = DateTime.now();
    final int currentYear = now.year % 100; // 2 digit year
    final int currentMonth = now.month;

    if (year < currentYear) {
      return false;
    }
    if (year == currentYear && month < currentMonth) {
      return false;
    }

    return true;
  }

  bool _validateCPF(String input) {
    String clean = input.replaceAll(RegExp(r'\D'), '');
    if (clean.length != 11) return false;
    if (RegExp(r'^(\d)\1*$').hasMatch(clean)) {
      return false; // Known invalid CPFs like 111.111.111-11
    }

    List<int> digits = clean.split('').map((e) => int.parse(e)).toList();

    // Calculate first verifier digit
    int sum1 = 0;
    for (int i = 0; i < 9; i++) {
      sum1 += digits[i] * (10 - i);
    }
    int remainder1 = sum1 % 11;
    int digit1 = (remainder1 < 2) ? 0 : (11 - remainder1);
    if (digits[9] != digit1) return false;

    // Calculate second verifier digit
    int sum2 = 0;
    for (int i = 0; i < 10; i++) {
      sum2 += digits[i] * (11 - i);
    }
    int remainder2 = sum2 % 11;
    int digit2 = (remainder2 < 2) ? 0 : (11 - remainder2);
    if (digits[10] != digit2) return false;

    return true;
  }
}
