import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:go_router/go_router.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/central_service.dart';
import '../../../services/api_service.dart';
import '../../../services/payment/payment_service.dart';
import '../../../widgets/app_dialog_actions.dart';
import './card_registration_screen.dart';

/// Modelo simples de método de pagamento
class _PaymentMethod {
  final String id; // Valor salvo no banco
  final String title; // Texto exibido ao usuário
  final String subtitle;
  final IconData icon;

  const _PaymentMethod({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

class PaymentMethodsScreen extends StatefulWidget {
  const PaymentMethodsScreen({super.key});

  @override
  State<PaymentMethodsScreen> createState() => _PaymentMethodsScreenState();
}

class _PaymentMethodsScreenState extends State<PaymentMethodsScreen>
    with WidgetsBindingObserver {
  final CentralService _uberService = CentralService();
  final ApiService _apiService = ApiService();
  final PaymentService _paymentService = PaymentService();

  bool _isLoading = true;
  String? _error;
  String _preferredMethod = 'PIX';
  List<Map<String, dynamic>> _savedCards = const [];

  /// Meios de pagamento fixos (excluindo cartões dinâmicos)
  static final List<_PaymentMethod> _fixedMethods = [
    _PaymentMethod(
      id: 'PIX',
      title: 'PIX',
      subtitle: 'Pagamento instantâneo via plataforma',
      icon: LucideIcons.scanLine,
    ),
    _PaymentMethod(
      id: 'Dinheiro/Direto',
      title: 'Direto com Prestador',
      subtitle: 'Pague diretamente ao prestador (combinar forma)',
      icon: LucideIcons.banknote,
    ),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadInitialData();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint(
        '🔄 [PaymentMethodsScreen] App retomado, atualizando métodos...',
      );
      _loadInitialData();
    }
  }

  Future<void> _loadInitialData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final userId = _apiService.userId;
      if (userId == null) throw Exception("Usuário não autenticado");
      final preferred = await _uberService.getPreferredPaymentMethod(userId);
      final cardsRaw = await _paymentService.getSavedCards();
      final cards = cardsRaw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();

      if (!mounted) return;
      setState(() {
        // Mercado Pago (saldo/cartão) desabilitado para clientes por enquanto.
        // Se algum usuário estiver com preferência antiga, forçamos para PIX.
        if (preferred == 'MERCADO_PAGO_WALLET' ||
            preferred.toString().toLowerCase().contains('mercado')) {
          _preferredMethod = 'PIX';
        } else {
          _preferredMethod = preferred;
        }
        _savedCards = cards;
        _isLoading = false;
      });

      // Atualiza no backend fora do setState (best-effort), para não voltar a aparecer.
      if (preferred == 'MERCADO_PAGO_WALLET' ||
          preferred.toString().toLowerCase().contains('mercado')) {
        try {
          await _uberService.updatePreferredPaymentMethod(
            userId: userId,
            method: 'PIX',
          );
        } catch (_) {}
      }
    } catch (e) {
      debugPrint("Erro ao carregar dados de pagamento: $e");
      if (!mounted) return;
      setState(() {
        _error = "Não foi possível carregar as formas de pagamento.";
        _isLoading = false;
      });
    }
  }

  Future<void> _openCardRegistration() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const CardRegistrationScreen()),
    );
    if (!mounted) return;
    if (result == true) {
      await _loadInitialData();
    }
  }

  Future<void> _deleteCard(Map<String, dynamic> card) async {
    final id = card['id'];
    if (id == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover cartão'),
        content: const Text(
          'Deseja remover este cartão? Você poderá cadastrar outro depois.',
        ),
        actions: [
          AppDialogCancelAction(onPressed: () => Navigator.of(ctx).pop(false)),
          AppDialogCancelAction(
            label: 'Remover',
            onPressed: () => Navigator.of(ctx).pop(true),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    try {
      await _paymentService.deletePaymentMethod(paymentMethodId: id);
      // Se o preferido era o cartão removido, volta para PIX
      if (_preferredMethod.toString() == id.toString()) {
        final userId = _apiService.userId;
        if (userId != null) {
          await _uberService.updatePreferredPaymentMethod(
            userId: userId,
            method: 'PIX',
          );
        }
        if (mounted) setState(() => _preferredMethod = 'PIX');
      }
      await _loadInitialData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Cartão removido com sucesso.')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao remover cartão: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _updatePreference(String method) async {
    final userId = _apiService.userId;
    if (userId == null) return;

    final oldMethod = _preferredMethod;
    setState(() => _preferredMethod = method);

    try {
      await _uberService.updatePreferredPaymentMethod(
        userId: userId,
        method: method,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Meio de pagamento preferido atualizado!'),
            backgroundColor: AppTheme.primaryBlue,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _preferredMethod = oldMethod);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erro ao atualizar preferência.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Formas de Pagamento',
          style: GoogleFonts.manrope(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.black),
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go('/home');
            }
          },
        ),
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isLoading
          ? Center(
              child: CircularProgressIndicator(color: AppTheme.primaryYellow),
            )
          : _error != null
          ? _buildErrorState()
          : _buildContent(),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(LucideIcons.alertCircle, size: 48, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(_error!, style: GoogleFonts.manrope(color: Colors.red)),
          const SizedBox(height: 16),
          TextButton(
            onPressed: _loadInitialData,
            child: const Text('Tentar Novamente'),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final defaultCard = _savedCards.isNotEmpty ? _savedCards.first : null;
    final hasCard = defaultCard != null;
    final cardLabel = hasCard
        ? '${(defaultCard['brand']?.toString().toUpperCase() ?? 'CARTÃO')} •••• ${(defaultCard['last4']?.toString() ?? '****')}'
        : 'Adicionar Cartão de Crédito';
    final cardSubtitle = hasCard
        ? 'Cartão salvo (por segurança, apenas 1 cartão por vez)'
        : 'Cadastre um cartão para pagar pelo app';

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(
        horizontal: 20,
        vertical: 24,
      ).copyWith(bottom: 100),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSectionHeader('Meios de Pagamento'),
          const SizedBox(height: 16),

          ..._fixedMethods.map(
            (method) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _buildPaymentMethodItem(
                id: method.id,
                title: method.title,
                subtitle: method.subtitle,
                icon: method.icon,
                isSelected: _preferredMethod == method.id,
                onTap: () => _updatePreference(method.id),
              ),
            ),
          ),

          const SizedBox(height: 24),
          _buildSectionHeader('Cartão de Crédito'),
          const SizedBox(height: 16),
          _buildPaymentMethodItem(
            id: hasCard ? defaultCard['id'].toString() : 'Card',
            title: hasCard ? cardLabel : 'Cartão de Crédito',
            subtitle: cardSubtitle,
            icon: LucideIcons.creditCard,
            isSelected:
                hasCard &&
                _preferredMethod.toString() == defaultCard['id'].toString(),
            onTap: () async {
              if (!hasCard) {
                await _openCardRegistration();
                return;
              }
              await _updatePreference(defaultCard['id'].toString());
            },
            trailing: hasCard
                ? IconButton(
                    tooltip: 'Remover cartão',
                    icon: Icon(
                      Icons.delete_outline,
                      color: Colors.red.shade400,
                    ),
                    onPressed: () => _deleteCard(defaultCard),
                  )
                : TextButton(
                    onPressed: _openCardRegistration,
                    child: const Text('Adicionar'),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.manrope(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: Colors.grey.shade600,
      ),
    );
  }

  Widget _buildPaymentMethodItem({
    required String id,
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(20),
        decoration: AppTheme.surfacedCardDecoration(
          color: Colors.white,
          radius: 16,
          border: Border.all(
            color: isSelected ? AppTheme.primaryBlue : Colors.grey.shade200,
            width: isSelected ? 2 : 1,
          ),
          shadow: isSelected
              ? [
                  BoxShadow(
                    color: AppTheme.primaryBlue.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ]
              : AppTheme.cardShadow,
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isSelected
                    ? AppTheme.primaryBlue.withValues(alpha: 0.1)
                    : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                icon,
                color: isSelected ? AppTheme.primaryBlue : AppTheme.textDark,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.manrope(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) ...[trailing],
            if (isSelected)
              Icon(LucideIcons.checkCircle2, color: AppTheme.primaryBlue),
          ],
        ),
      ),
    );
  }
}
