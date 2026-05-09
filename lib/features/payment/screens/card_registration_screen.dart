import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:lucide_icons/lucide_icons.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/payment/payment_service.dart';
import '../../../services/security_service.dart';
import '../../../services/central_service.dart';
import '../../../widgets/face_verification_sheet.dart';

class CardRegistrationScreen extends StatefulWidget {
  const CardRegistrationScreen({super.key});

  @override
  State<CardRegistrationScreen> createState() => _CardRegistrationScreenState();
}

class _CardRegistrationScreenState extends State<CardRegistrationScreen> {
  final PaymentService _paymentService = PaymentService();
  final SecurityService _securityService = SecurityService();
  final CentralService _uberService = CentralService();

  final _formKey = GlobalKey<FormState>();
  final _holderNameController = TextEditingController();
  final _cardNumberController = TextEditingController();
  final _expiryController = TextEditingController();
  final _cvvController = TextEditingController();
  final _cepController = TextEditingController();
  final _addressNumberController = TextEditingController();

  bool _showCardForm = false;
  bool _biometricallyValidated = false;
  bool _isLoading = false;
  String? _error;
  bool _cepAutoFilled = false;
  String? _cepFieldError;

  @override
  void initState() {
    super.initState();
    _checkBiometricCache();
    _prefillAddressData();
  }

  Future<void> _checkBiometricCache() async {
    try {
      final needsValidation = await _securityService.needsFaceValidation();

      if (!needsValidation) {
        debugPrint('✅ [FaceCache] Validação facial válida via SecurityService');
        setState(() {
          _biometricallyValidated = true;
          _showCardForm = true;
        });
      }
    } catch (e) {
      debugPrint('❌ [FaceCache] Erro ao ler cache: $e');
    }
  }

  @override
  void dispose() {
    _holderNameController.dispose();
    _cardNumberController.dispose();
    _expiryController.dispose();
    _cvvController.dispose();
    _cepController.dispose();
    _addressNumberController.dispose();
    super.dispose();
  }

  String _onlyDigits(String value) => value.replaceAll(RegExp(r'\D'), '');

  Future<void> _prefillAddressData() async {
    try {
      final profile = await _loadProfileAddress();
      final profileCep = _onlyDigits(profile['postal_code']?.toString() ?? '');
      final profileNumber = (profile['address_number'] ?? '').toString().trim();

      if (mounted && profileCep.length == 8) {
        _cepController.text = profileCep;
      }
      if (mounted && profileNumber.isNotEmpty) {
        _addressNumberController.text = profileNumber;
      }

      if (profileCep.length == 8) return;

      final detectedCep = await _tryPrefillCepByGeolocation();
      if (!mounted || detectedCep == null || detectedCep.length != 8) return;

      _cepController.text = detectedCep;
      _cepAutoFilled = true;
      setState(() {});
    } catch (e) {
      debugPrint('⚠️ [CardRegistration] Falha ao pré-preencher CEP: $e');
    }
  }

  Future<Map<String, dynamic>> _loadProfileAddress() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return {};
    final data = await Supabase.instance.client
        .from('users')
        .select('postal_code,address_number')
        .eq('supabase_uid', user.id)
        .maybeSingle();
    return Map<String, dynamic>.from(data ?? const {});
  }

  Future<String?> _tryPrefillCepByGeolocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return null;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.medium,
          timeLimit: Duration(seconds: 6),
        ),
      );

      final url = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse?lat=${pos.latitude}&lon=${pos.longitude}&format=json&addressdetails=1&zoom=18&accept-language=pt-BR',
      );
      final response = await http
          .get(url, headers: {'User-Agent': 'Service101-App'})
          .timeout(const Duration(seconds: 6));

      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final addr = data['address'] as Map<String, dynamic>?;
      final cepRaw = addr?['postcode']?.toString() ?? '';
      final cepDigits = _onlyDigits(cepRaw);
      if (cepDigits.length != 8) return null;
      return cepDigits;
    } catch (_) {
      return null;
    }
  }

  Future<void> _persistAddressHintsIfNeeded() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) return;

    final cepDigits = _onlyDigits(_cepController.text);
    if (cepDigits.length != 8) return;

    final profile = await _loadProfileAddress();
    final currentCep = _onlyDigits(profile['postal_code']?.toString() ?? '');
    final currentNumber = (profile['address_number'] ?? '').toString().trim();
    final newNumber = _addressNumberController.text.trim();

    final updates = <String, dynamic>{};
    if (currentCep != cepDigits) updates['postal_code'] = cepDigits;
    if (newNumber.isNotEmpty && currentNumber != newNumber) {
      updates['address_number'] = newNumber;
    }
    if (updates.isEmpty) return;

    await Supabase.instance.client
        .from('users')
        .update(updates)
        .eq('supabase_uid', user.id);
  }

  Future<void> _startBiometricValidation() async {
    final bool? success = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const FaceVerificationSheet(),
    );

    if (success == true) {
      setState(() {
        _biometricallyValidated = true;
        _showCardForm = true;
      });
    }
  }

  Future<void> _registerCard() async {
    if (!_biometricallyValidated) {
      _startBiometricValidation();
      return;
    }

    if (!_showCardForm) {
      setState(() => _showCardForm = true);
      return;
    }

    if (!_formKey.currentState!.validate()) return;

    final cepDigits = _onlyDigits(_cepController.text);
    if (cepDigits.length != 8) {
      setState(() {
        _cepFieldError = 'Informe um CEP válido com 8 dígitos.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
      _cepFieldError = null;
    });

    try {
      final existingCards = await _paymentService.getSavedCards();
      if (existingCards.isNotEmpty) {
        throw Exception(
          'Você já possui um cartão cadastrado. Remova o cartão atual em "Formas de Pagamento" para cadastrar outro.',
        );
      }

      final expiryParts = _expiryController.text.split('/');
      final expiryMonth = expiryParts[0];
      final expiryYear = '20${expiryParts[1]}';

      debugPrint('💳 [MercadoPago] Tokenizando cartão...');
      final tokenizeResult = await _uberService.tokenizeCard({
        'holderName': _holderNameController.text.trim(),
        'number': _cardNumberController.text.replaceAll(' ', ''),
        'expiryMonth': expiryMonth,
        'expiryYear': expiryYear,
        'ccv': _cvvController.text,
        'postalCode': cepDigits,
        'addressNumber': _addressNumberController.text.trim(),
      });

      if (tokenizeResult['creditCardToken'] != null) {
        final token = tokenizeResult['creditCardToken'];
        final brand = tokenizeResult['brand'] ?? 'Cartão';
        final mpPaymentMethodId = tokenizeResult['mp_payment_method_id']?.toString();
        final last4 = _cardNumberController.text.substring(
          _cardNumberController.text.length - 4,
        );

        await _paymentService.savePaymentMethod(
          paymentMethodId: token,
          brand: brand,
          last4: last4,
          expMonth: int.parse(expiryMonth),
          expYear: int.parse(expiryYear),
          provider: 'mercado_pago',
          mpPaymentMethodId: mpPaymentMethodId,
        );
        await _persistAddressHintsIfNeeded();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cartão Mercado Pago salvo com sucesso!'),
            ),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception("Token do cartão não gerado pela API do Mercado Pago.");
      }
    } catch (e) {
      final msg = e.toString();
      final isCepError =
          msg.toLowerCase().contains('cep') ||
          msg.toLowerCase().contains('postalcode') ||
          msg.contains('MISSING_CARD_HOLDER_INFO');
      setState(() {
        if (msg.contains('CARD_ALREADY_EXISTS') ||
            msg.toLowerCase().contains('já possui um cartão')) {
          _error =
              'Você já possui um cartão cadastrado. Remova o cartão atual para cadastrar outro.';
        } else if (msg.contains('CARD_TYPE_NOT_ALLOWED')) {
          _error = 'Apenas cartão de crédito é aceito neste momento.';
        } else {
          _error = "Erro ao cadastrar cartão. Revise os dados e tente novamente.";
        }
        if (isCepError) {
          _cepFieldError = 'Informe um CEP válido do titular do cartão.';
        }
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Cadastrar Cartão',
          style: GoogleFonts.manrope(fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!_showCardForm) ...[
                Icon(
                  Icons.credit_card,
                  size: 80,
                  color: AppTheme.primaryYellow,
                ),
                const SizedBox(height: 24),
                Text(
                  'Pagamento Seguro',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  'Para sua segurança, solicitamos uma validação facial rápida antes de cadastrar seu cartão de crédito.',
                  style: GoogleFonts.manrope(color: Colors.grey.shade600),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 60),
              ] else ...[
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      TextFormField(
                        controller: _holderNameController,
                        decoration: AppTheme.inputDecoration(
                          'Nome no Cartão',
                          LucideIcons.user,
                        ),
                        textCapitalization: TextCapitalization.characters,
                        validator: (v) =>
                            v == null || v.isEmpty ? 'Informe o nome' : null,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cardNumberController,
                        decoration: AppTheme.inputDecoration(
                          'Número do Cartão',
                          LucideIcons.creditCard,
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(16),
                          _CardNumberFormatter(),
                        ],
                        validator: (v) => v == null || v.length < 16
                            ? 'Número inválido'
                            : null,
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: TextFormField(
                              controller: _expiryController,
                              decoration: AppTheme.inputDecoration(
                                'Validade (MM/AA)',
                                LucideIcons.calendar,
                              ),
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                                _ExpiryDateFormatter(),
                              ],
                              validator: (v) =>
                                  v == null || v.length < 5 ? 'Inválido' : null,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: TextFormField(
                              controller: _cvvController,
                              decoration: AppTheme.inputDecoration(
                                'CVV',
                                LucideIcons.lock,
                              ),
                              keyboardType: TextInputType.number,
                              obscureText: true,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(4),
                              ],
                              validator: (v) =>
                                  v == null || v.length < 3 ? 'Invalido' : null,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _cepController,
                        decoration:
                            AppTheme.inputDecoration(
                              'CEP',
                              LucideIcons.mapPin,
                            ).copyWith(
                              hintText: '00000-000',
                              helperText: _cepAutoFilled
                                  ? 'CEP sugerido automaticamente. Você pode editar.'
                                  : null,
                              errorText: _cepFieldError,
                            ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(8),
                          _CepFormatter(),
                        ],
                        validator: (v) {
                          final digits = _onlyDigits(v ?? '');
                          if (digits.length != 8) {
                            return 'Informe o CEP com 8 dígitos';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressNumberController,
                        decoration: AppTheme.inputDecoration(
                          'Número (opcional)',
                          LucideIcons.hash,
                        ).copyWith(hintText: 'Ex: 123'),
                        textInputAction: TextInputAction.done,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),
              ],

              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Text(
                    _error!,
                    style: const TextStyle(color: Colors.red),
                    textAlign: TextAlign.center,
                  ),
                ),
              Padding(
                padding: const EdgeInsets.only(bottom: 30),
                child: SizedBox(
                  height: 56,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: AppTheme.primaryYellow.withOpacity(0.3),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _registerCard,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryYellow,
                        foregroundColor: AppTheme.textDark,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isLoading
                          ? const CircularProgressIndicator(color: Colors.black)
                          : Text(
                              _showCardForm
                                  ? 'SALVAR CARTÃO'
                                  : 'VALIDAR E AVANÇAR',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CardNumberFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.length > oldValue.text.length) {
      if (newValue.text.length > 0 && (newValue.text.length + 1) % 5 == 0) {
        return TextEditingValue(
          text:
              '${oldValue.text} ${newValue.text.substring(newValue.text.length - 1)}',
          selection: TextSelection.collapsed(
            offset: newValue.selection.end + 1,
          ),
        );
      }
    }
    return newValue;
  }
}

class _ExpiryDateFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text;
    if (newValue.selection.baseOffset == 0) return newValue;

    var buffer = StringBuffer();
    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);
      var nonZeroIndex = i + 1;
      if (nonZeroIndex % 2 == 0 && nonZeroIndex != text.length) {
        buffer.write('/');
      }
    }

    var string = buffer.toString();
    return newValue.copyWith(
      text: string,
      selection: TextSelection.collapsed(offset: string.length),
    );
  }
}

class _CepFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'[^\d]'), '');
    final trimmed = digits.length > 8 ? digits.substring(0, 8) : digits;

    final buffer = StringBuffer();
    for (int i = 0; i < trimmed.length; i++) {
      if (i == 5) buffer.write('-');
      buffer.write(trimmed[i]);
    }
    final text = buffer.toString();
    return TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }
}
