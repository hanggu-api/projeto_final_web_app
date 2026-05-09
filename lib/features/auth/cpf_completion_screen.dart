import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../widgets/ios_date_time_picker.dart';
import '../../core/utils/input_formatters.dart';
import '../../services/api_service.dart';

/// Tela exibida obrigatoriamente após login via Google (ou qualquer SSO)
/// quando o usuário ainda não possui CPF e data de nascimento cadastrados.
class CpfCompletionScreen extends StatefulWidget {
  const CpfCompletionScreen({super.key});

  @override
  State<CpfCompletionScreen> createState() => _CpfCompletionScreenState();
}

class _CpfCompletionScreenState extends State<CpfCompletionScreen> {
  final _formKey = GlobalKey<FormState>();
  final _cpfController = TextEditingController();
  final _birthDateController = TextEditingController();
  final _phoneController = TextEditingController();
  final _api = ApiService();
  bool _isLoading = false;
  DateTime? _selectedDate;

  // Validação assíncrona do telefone
  Timer? _phoneDebounce;
  bool _isValidatingPhone = false;
  String? _phoneError;

  @override
  void dispose() {
    _cpfController.dispose();
    _birthDateController.dispose();
    _phoneController.dispose();
    _phoneDebounce?.cancel();
    super.dispose();
  }

  void _onPhoneChanged(String value) {
    if (_phoneDebounce?.isActive ?? false) {
      _phoneDebounce!.cancel();
    }

    final digits = phoneDigitsOnly(value);
    if (digits.length < 10) {
      setState(() {
        _phoneError = null;
        _isValidatingPhone = false;
      });
      return;
    }

    _phoneDebounce = Timer(const Duration(milliseconds: 700), () async {
      setState(() => _isValidatingPhone = true);

      try {
        final result = await _api.checkUnique(phone: digits);

        if (mounted) {
          setState(() {
            _isValidatingPhone = false;
            if (result['exists'] == true) {
              _phoneError = 'Este telefone já está cadastrado';
            } else if (result['invalid'] == true) {
              _phoneError = result['message'] ?? 'Número inválido';
            } else {
              _phoneError = null;
            }
          });
        }
      } catch (e) {
        if (mounted) setState(() => _isValidatingPhone = false);
      }
    });
  }

  /// Valida CPF pelo algoritmo de módulo 11 (padrão Receita Federal)
  bool _validateCpf(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(digits[i]) * (10 - i);
    }
    int remainder = (sum * 10) % 11;
    if (remainder == 10 || remainder == 11) remainder = 0;
    if (remainder != int.parse(digits[9])) return false;

    sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(digits[i]) * (11 - i);
    }
    remainder = (sum * 10) % 11;
    if (remainder == 10 || remainder == 11) remainder = 0;
    return remainder == int.parse(digits[10]);
  }

  Future<void> _selectDate() async {
    final picked = await AppCupertinoPicker.showDatePicker(
      context: context,
      initialDate: DateTime(1990, 1, 1),
      firstDate: DateTime(1920),
      lastDate: DateTime.now().subtract(const Duration(days: 365 * 18)),
      title: 'Data de nascimento',
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedDate = picked;
        _birthDateController.text =
            '${picked.day.toString().padLeft(2, '0')}/'
            '${picked.month.toString().padLeft(2, '0')}/'
            '${picked.year}';
      });
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) {
      return;
    }
    if (_selectedDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor, selecione sua data de nascimento.'),
        ),
      );
      return;
    }

    setState(() => _isLoading = true);
    try {
      final userId = _api.currentUserId;
      if (userId == null) throw Exception('Usuário não autenticado');

      final cpfClean = _cpfController.text.replaceAll(RegExp(r'\D'), '');
      final birthDateStr = _selectedDate!.toIso8601String().split('T')[0];
      final phoneClean = phoneDigitsOnly(_phoneController.text);

      final userRow = await _api.getUserData();
      await _api.updateProfile(
        phone: phoneClean.isNotEmpty ? phoneClean : null,
        customFields: <String, dynamic>{
          'document_value': cpfClean,
          'document_type': 'cpf',
          'birth_date': birthDateStr,
        },
      );

      debugPrint(
        '✅ [CpfCompletion] CPF, nascimento e telefone salvos para userId: ${userRow?['id']}',
      );

      final role = _api.role;

      if (mounted) {
        if (role == 'provider') {
          context.go('/provider-home');
        } else {
          context.go('/home');
        }
      }
    } catch (e) {
      debugPrint('❌ [CpfCompletion] Erro: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao salvar dados: $e')));
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
        backgroundColor: AppTheme.primaryYellow,
        elevation: 0,
        centerTitle: true,
        title: Text(
          'Complete seu Cadastro',
          style: GoogleFonts.manrope(
            color: AppTheme.textDark,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
        iconTheme: IconThemeData(color: AppTheme.textDark),
        automaticallyImplyLeading: false, // bloquear voltar
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                // Ícone + header
                Center(
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      color: AppTheme.primaryYellow.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      LucideIcons.shieldCheck,
                      size: 36,
                      color: AppTheme.primaryYellow,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Uma última etapa!',
                  style: GoogleFonts.manrope(
                    fontSize: 24,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Precisamos do seu CPF e data de nascimento para emissão '
                  'de notas fiscais, segurança e conformidade da plataforma. '
                  'Seus dados são protegidos pelo padrão LGPD.',
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    color: Colors.grey[600],
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                // Campo CPF
                Text(
                  'CPF',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _cpfController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    _CpfInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: '000.000.000-00',
                    prefixIcon: const Icon(LucideIcons.creditCard),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: AppTheme.primaryYellow,
                        width: 2,
                      ),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'CPF é obrigatório';
                    }
                    final digits = value.replaceAll(RegExp(r'\D'), '');
                    if (digits.length != 11) return 'CPF deve ter 11 dígitos';
                    if (!_validateCpf(digits)) {
                      return 'CPF inválido — verifique os números';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                // Campo Data de Nascimento
                Text(
                  'Data de Nascimento',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _birthDateController,
                  readOnly: true,
                  onTap: _selectDate,
                  decoration: InputDecoration(
                    hintText: 'DD/MM/AAAA',
                    prefixIcon: const Icon(LucideIcons.calendar),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Data de nascimento é obrigatória';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                // Campo Telefone
                Text(
                  'Telefone Celular',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 6),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    PhoneInputFormatter(),
                  ],
                  decoration: InputDecoration(
                    hintText: '(XX) 9XXXX-XXXX',
                    prefixIcon: const Icon(LucideIcons.phone),
                    suffixIcon: _isValidatingPhone
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : null,
                    errorText: _phoneError,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onChanged: _onPhoneChanged,
                  validator: (value) {
                    if (value == null || value.isEmpty)
                      return 'Telefone é obrigatório';
                    if (_phoneError != null) return _phoneError;
                    final digits = phoneDigitsOnly(value);
                    if (digits.length < 10)
                      return 'Telefone inválido (mínimo 10 dígitos)';
                    if (digits.length == 11 && digits[2] != '9')
                      return 'Celular deve ter 9 após o DDD';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                // Aviso LGPD
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.blue.withOpacity(0.2)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.lock,
                        size: 16,
                        color: Colors.blue,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Seus dados são criptografados e nunca compartilhados com terceiros.',
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            color: Colors.blue[700],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                // Botão enviar
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.primaryYellow,
                      foregroundColor: AppTheme.textDark,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: _isLoading
                        ? const CircularProgressIndicator(strokeWidth: 2)
                        : Text(
                            'SALVAR E CONTINUAR',
                            style: GoogleFonts.manrope(
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Formatador de máscara para CPF: 000.000.000-00
class _CpfInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length && i < 11; i++) {
      if (i == 3 || i == 6) buffer.write('.');
      if (i == 9) buffer.write('-');
      buffer.write(digits[i]);
    }
    final formatted = buffer.toString();
    return newValue.copyWith(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
