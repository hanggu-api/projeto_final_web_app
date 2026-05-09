import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';

class PaymentModeSelector extends StatefulWidget {
  final VoidCallback? onModeChanged;
  final bool isCompact;

  const PaymentModeSelector({
    super.key,
    this.onModeChanged,
    this.isCompact = false,
  });

  @override
  State<PaymentModeSelector> createState() => _PaymentModeSelectorState();
}

class _PaymentModeSelectorState extends State<PaymentModeSelector> {
  final ApiService _api = ApiService();
  String? _currentMode;
  bool _isLoading = true;
  bool _isUpdating = false;
  // ApiService não é necessário aqui (apenas mudança de modo via Supabase).

  @override
  void initState() {
    super.initState();
    _loadCurrentMode();
  }

  Future<void> _loadCurrentMode() async {
    try {
      final response = await _api.getProfile();

      if (mounted) {
        final raw = (response['driver_payment_mode'] ?? 'platform')
            .toString()
            .trim()
            .toLowerCase();
        setState(() {
          _currentMode = (raw == 'daily' || raw == 'direct') ? 'fixed' : raw;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Erro ao carregar modo de pagamento: $e');
      if (mounted) {
        setState(() {
          _currentMode = 'platform';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _updatePaymentMode(String newMode) async {
    if (_isUpdating || newMode == _currentMode) return;

    setState(() => _isUpdating = true);

    try {
      if (newMode != 'platform' && newMode != 'fixed') {
        setState(() => _isUpdating = false);
        return;
      }

      await _api.updateProfile(customFields: {'driver_payment_mode': newMode});

      if (mounted) {
        setState(() {
          _currentMode = newMode;
          _isUpdating = false;
        });

        widget.onModeChanged?.call();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${_getModeLabel(newMode)} ativado'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Erro ao atualizar modo de pagamento: $e');
      if (mounted) {
        final friendly = _friendlyModeUpdateError(e);
        setState(() {
          _isUpdating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendly), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _friendlyModeUpdateError(Object error) {
    final raw = error.toString();
    if (raw.contains(
      'Você só pode alterar o modo de pagamento a cada 24 horas',
    )) {
      return raw;
    }
    return 'Erro ao atualizar modo de pagamento';
  }

  String _getModeLabel(String mode) {
    switch (mode) {
      case 'fixed':
        return '📅 Taxa diária';
      case 'platform':
      default:
        return '📊 Comissão';
    }
  }

  String _getModeDescription(String mode) {
    switch (mode) {
      case 'fixed':
        return 'R\$ 10/dia • receba na sua máquina';
      case 'platform':
      default:
        return 'PIX 5% • Cartão 10%';
    }
  }

  IconData _getModeIcon(String mode) {
    switch (mode) {
      case 'fixed':
        return Icons.calendar_today;
      case 'platform':
      default:
        return Icons.percent;
    }
  }

  Color _getModeColor(String mode) {
    switch (mode) {
      case 'fixed':
        return Colors.blue;
      case 'platform':
      default:
        return AppTheme.primaryYellow;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Container(
          height: widget.isCompact ? 50 : 120,
          decoration: BoxDecoration(
            color: Colors.grey[100],
            borderRadius: BorderRadius.circular(12),
          ),
          child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
        ),
      );
    }

    if (widget.isCompact) {
      return _buildCompactMode();
    } else {
      return _buildExpandedMode();
    }
  }

  Widget _buildCompactMode() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: GestureDetector(
        onTap: _showModeModal,
        child: Container(
          height: 50,
          decoration: BoxDecoration(
            color: _getModeColor(_currentMode ?? 'platform').withOpacity(0.1),
            border: Border.all(
              color: _getModeColor(_currentMode ?? 'platform'),
              width: 1.5,
            ),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Row(
                  children: [
                    Icon(
                      _getModeIcon(_currentMode ?? 'platform'),
                      color: _getModeColor(_currentMode ?? 'platform'),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      _getModeLabel(_currentMode ?? 'platform'),
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: _getModeColor(_currentMode ?? 'platform'),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 12),
                child: Icon(Icons.keyboard_arrow_down, size: 18),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExpandedMode() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Modo de Recebimento',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 110,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                _buildModeCard('platform'),
                const SizedBox(width: 12),
                _buildModeCard('fixed'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeCard(String mode) {
    final isSelected = _currentMode == mode;
    final color = _getModeColor(mode);

    return GestureDetector(
      onTap: _isUpdating ? null : () => _updatePaymentMode(mode),
      child: Container(
        width: 110,
        decoration: AppTheme.surfacedCardDecoration(
          color: isSelected ? color.withOpacity(0.15) : Colors.white,
          radius: 14,
          border: Border.all(
            color: isSelected ? color : Colors.grey[300]!,
            width: isSelected ? 2.5 : 1.5,
          ),
        ),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(_getModeIcon(mode), color: color, size: 28),
                  const SizedBox(height: 6),
                  Text(
                    _getModeLabel(mode),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: color,
                      height: 1.2,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _getModeDescription(mode),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 9,
                      color: Colors.grey[600],
                      height: 1.1,
                    ),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check, color: Colors.white, size: 14),
                ),
              ),

            // Conexão Mercado Pago (opcional) pode ser exibida em outras telas;
            // aqui mantemos o seletor focado apenas nos 2 modos (comissão/taxa diária).
          ],
        ),
      ),
    );
  }

  void _showModeModal() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Escolha seu Modo de Recebimento',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              _buildModalModeOption(
                'platform',
                '📊 Comissão',
                'PIX 5% • Cartão 10%',
              ),
              const SizedBox(height: 12),
              _buildModalModeOption(
                'fixed',
                '📅 Taxa diária',
                'R\$ 10/dia • receba na sua máquina',
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[300],
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text('Fechar'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildModalModeOption(String mode, String title, String subtitle) {
    final isSelected = _currentMode == mode;
    final color = _getModeColor(mode);

    return GestureDetector(
      onTap: _isUpdating
          ? null
          : () {
              _updatePaymentMode(mode);
              Navigator.pop(context);
            },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? color.withOpacity(0.1) : Colors.grey[50],
          border: Border.all(
            color: isSelected ? color : Colors.grey[200]!,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(_getModeIcon(mode), color: color, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                child: const Icon(Icons.check, color: Colors.white, size: 16),
              ),
          ],
        ),
      ),
    );
  }
}
