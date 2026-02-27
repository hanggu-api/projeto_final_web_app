import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';

class MedicalServiceStep extends StatefulWidget {
  final Function(double price, bool hasReturn) onChanged;
  final bool isDoctor; // To show/hide return policy
  final double? initialPrice;
  final bool? initialHasReturn;

  const MedicalServiceStep({
    super.key,
    required this.onChanged,
    required this.isDoctor,
    this.initialPrice,
    this.initialHasReturn,
  });

  @override
  State<MedicalServiceStep> createState() => _MedicalServiceStepState();
}

class _MedicalServiceStepState extends State<MedicalServiceStep> {
  final _priceController = TextEditingController();
  bool _hasReturn = false;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    if (widget.initialPrice != null) {
      _priceController.text = widget.initialPrice!.toStringAsFixed(2);
    }
    if (widget.initialHasReturn != null) {
      _hasReturn = widget.initialHasReturn!;
    } else if (widget.isDoctor) {
      _hasReturn = true; // Default to true for doctors
    }
  }

  void _update() {
    if (_formKey.currentState?.validate() ?? false) {
      final price =
          double.tryParse(
            _priceController.text
                .replaceAll(',', '.')
                .replaceAll(RegExp(r'[^\d.]'), ''),
          ) ??
          0.0;
      widget.onChanged(price, _hasReturn);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Configuração da Consulta',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const Text(
              'Defina o valor do seu atendimento e a política de retorno.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextFormField(
              controller: _priceController,
              decoration: AppTheme.inputDecoration('Valor da Consulta', Icons.attach_money).copyWith(
                hintText: r'R$ 0,00',
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [CurrencyInputFormatter()],
              onChanged: (_) => _update(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Informe o valor da consulta';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            if (widget.isDoctor) ...[
              const Text(
                'Política de Retorno',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Container(
                decoration: BoxDecoration(
                  color: AppTheme.lightGray,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    RadioListTile<bool>(
                      activeColor: Colors.green,
                      title: const Text('Com retorno (30 dias)'),
                      subtitle: const Text(
                        'O paciente tem direito a um retorno gratuito em até 30 dias.',
                      ),
                      value: true,
                      groupValue: _hasReturn,
                      onChanged: (val) {
                        setState(() => _hasReturn = val!);
                        _update();
                      },
                    ),
                    const Divider(height: 1),
                    RadioListTile<bool>(
                      activeColor: Colors.green,
                      title: const Text('Sem retorno'),
                      subtitle: const Text(
                        'Cada consulta é cobrada individualmente.',
                      ),
                      value: false,
                      groupValue: _hasReturn,
                      onChanged: (val) {
                        setState(() => _hasReturn = val!);
                        _update();
                      },
                    ),
                  ],
                ),
              ),
            ],
            if (!widget.isDoctor)
              const Card(
                color: Color(0xFFFFF3CD),
                child: Padding(
                  padding: EdgeInsets.all(12.0),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: Color(0xFF856404)),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Para sua categoria, o agendamento é único (sem retorno incluso).',
                          style: TextStyle(color: Color(0xFF856404)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
