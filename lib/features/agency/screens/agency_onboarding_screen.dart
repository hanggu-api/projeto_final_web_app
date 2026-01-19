import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AgencyOnboardingScreen extends StatefulWidget {
  const AgencyOnboardingScreen({super.key});

  @override
  State<AgencyOnboardingScreen> createState() => _AgencyOnboardingScreenState();
}

class _AgencyOnboardingScreenState extends State<AgencyOnboardingScreen> {
  int _currentStep = 0;

  // Data
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  String _selectedTone = 'Profissional';
  String _selectedGoal = 'Vendas';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Configuração da Agência')),
      body: Stepper(
        currentStep: _currentStep,
        onStepContinue: () {
          if (_currentStep < 2) {
            setState(() => _currentStep += 1);
          } else {
            // Finish
            context.pop();
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Agência configurada com sucesso!')),
            );
          }
        },
        onStepCancel: () {
          if (_currentStep > 0) {
            setState(() => _currentStep -= 1);
          }
        },
        steps: [
          Step(
            title: const Text('Sobre a Empresa'),
            content: Column(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome da Empresa',
                  ),
                ),
                TextFormField(
                  controller: _descController,
                  decoration: const InputDecoration(
                    labelText: 'Descrição Resumida',
                  ),
                  maxLines: 3,
                ),
              ],
            ),
            isActive: _currentStep >= 0,
          ),
          Step(
            title: const Text('Identidade e Tom'),
            content: Column(
              children: [
                DropdownButtonFormField<String>(
                  initialValue: _selectedTone,
                  items:
                      ['Profissional', 'Descontraído', 'Sofisticado', 'Jovem']
                          .map(
                            (e) => DropdownMenuItem(value: e, child: Text(e)),
                          )
                          .toList(),
                  onChanged: (v) => setState(() => _selectedTone = v!),
                  decoration: const InputDecoration(labelText: 'Tom de Voz'),
                ),
                const SizedBox(height: 16),
                const Text('Cores da Marca (IA irá sugerir se vazio)'),
                // Color picker placeholder
                Container(height: 50, color: Colors.grey.shade200),
              ],
            ),
            isActive: _currentStep >= 1,
          ),
          Step(
            title: const Text('Objetivos'),
            content: Column(
              children: [
                RadioGroup<String>(
                  groupValue: _selectedGoal,
                  onChanged: (v) {
                    if (v != null) setState(() => _selectedGoal = v);
                  },
                  child: Column(
                    children: const [
                      RadioListTile<String>(
                        title: Text('Aumentar Vendas'),
                        value: 'Vendas',
                      ),
                      RadioListTile<String>(
                        title: Text('Gerar Leads'),
                        value: 'Leads',
                      ),
                      RadioListTile<String>(
                        title: Text('Reconhecimento de Marca'),
                        value: 'Branding',
                      ),
                    ],
                  ),
                ),
              ],
            ),
            isActive: _currentStep >= 2,
          ),
        ],
      ),
    );
  }
}
