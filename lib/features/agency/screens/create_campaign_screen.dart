
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/theme/app_theme.dart';

class CreateCampaignScreen extends StatefulWidget {
  const CreateCampaignScreen({super.key});

  @override
  State<CreateCampaignScreen> createState() => _CreateCampaignScreenState();
}

class _CreateCampaignScreenState extends State<CreateCampaignScreen> {
  final _nameController = TextEditingController();
  String _selectedPlatform = 'Instagram';
  bool _isGenerating = false;

  Future<void> _generateCampaign() async {
    setState(() => _isGenerating = true);
    // Simulate AI delay
    await Future.delayed(const Duration(seconds: 3));
    if (mounted) {
      setState(() => _isGenerating = false);
      context.pop(); // Go back to dashboard
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Campanha gerada com sucesso!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nova Campanha IA')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'A IA vai criar textos e artes para você.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Nome da Campanha (ex: Dia das Mães)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              initialValue: _selectedPlatform,
              items: ['Instagram', 'TikTok', 'Google Ads', 'Facebook']
                  .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                  .toList(),
              onChanged: (v) => setState(() => _selectedPlatform = v!),
              decoration: const InputDecoration(
                labelText: 'Plataforma Principal',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
             const TextField(
               maxLines: 4,
              decoration: InputDecoration(
                labelText: 'Instruções extras para a IA',
                hintText: 'Foque em promoção de 50% off...',
                border: OutlineInputBorder(),
              ),
            ),
            const Spacer(),
            ElevatedButton(
              onPressed: _isGenerating ? null : _generateCampaign,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.accentOrange,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              child: _isGenerating
                  ? const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        ),
                        SizedBox(width: 12),
                        Text('Gerando com IA...'),
                      ],
                    )
                  : const Text('Gerar Campanha'),
            ),
          ],
        ),
      ),
    );
  }
}
