import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import './driver_debt_pix_dialog.dart';
import '../../../services/api_service.dart';
import '../../../services/payment/mercado_pago_connect_service.dart';
import '../../payment/screens/mercado_pago_connect_webview_screen.dart';
import '../../../core/payment/backend_payment_api.dart';
import '../../../core/utils/payment_audit_logger.dart';

class DriverEarningsCard extends StatefulWidget {
  final VoidCallback? onModeChanged;
  final bool isActive;
  final int notificationCount;
  final Map<String, dynamic>? latestNotification;
  final VoidCallback onToggleOnline;
  final VoidCallback onProfileTap;
  final VoidCallback onNotificationsTap;
  final double currentBalance;
  final bool isMoto;
  final String balanceLabel;
  final String? settlementHint;

  const DriverEarningsCard({
    super.key,
    this.onModeChanged,
    required this.isActive,
    required this.notificationCount,
    this.latestNotification,
    required this.onToggleOnline,
    required this.onProfileTap,
    required this.onNotificationsTap,
    required this.currentBalance,
    this.isMoto = false,
    this.balanceLabel = 'Saldo em Conta',
    this.settlementHint,
  });

  @override
  State<DriverEarningsCard> createState() => _DriverEarningsCardState();
}

class _DriverEarningsCardState extends State<DriverEarningsCard>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  String? _currentMode;
  bool _isLoading = true;
  bool _isExpanded = false;
  late AnimationController _expandController;

  double _totalAppBalance = 0;
  double _totalCommissionDue = 0;
  double _totalDirectEarnings = 0;
  double _receivablePix = 0;
  double _receivableCard = 0;
  double _cancellationPending = 0;
  bool _isMPConnected = false;
  late ApiService _api;
  late MercadoPagoConnectService _mpService;
  final BackendPaymentApi _backendPaymentApi = const BackendPaymentApi();

  String _formatMoney(double value) {
    return 'R\$ ${value.toStringAsFixed(2).replaceAll('.', ',')}';
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _api = ApiService();
    _expandController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _mpService = MercadoPagoConnectService(_api);
    _loadData();
    _setupRefreshTimer();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _expandController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 [DriverEarningsCard] App retomado, atualizando dados...');
      _loadData();
    }
  }

  void _setupRefreshTimer() {
    Future.delayed(const Duration(seconds: 30), () {
      if (mounted) {
        _loadData();
        _setupRefreshTimer();
      }
    });
  }

  Future<void> _loadData() async {
    try {
      final userResponse = await _api.getProfile();

      final intUserId = userResponse['id'];
      final rawMode = (userResponse['driver_payment_mode'] ?? 'platform')
          .toString()
          .trim()
          .toLowerCase();
      // Compat: valores antigos (daily/direct) agora viram "fixed"
      if (rawMode == 'daily' || rawMode == 'direct') {
        _currentMode = 'fixed';
      } else {
        _currentMode = rawMode;
      }
      final dailyFeeAmount =
          (userResponse['driver_daily_fee_amount'] as num?)?.toDouble() ?? 0.0;
      final platformTxFeeRate =
          (userResponse['driver_platform_tx_fee_rate'] as num?)?.toDouble() ??
          0.0;

      // Saldos reais vêm do backend (Edge Function mp-driver-balance)
      final wallet = await _backendPaymentApi.fetchWallet();
      if (wallet == null) {
        throw Exception('Carteira indisponível no backend canônico.');
      }
      // Disponível para saque = saldo local do app (driver_balances/providers.wallet_balance)
      _totalAppBalance = (wallet['balance'] as num?)?.toDouble() ?? 0.0;
      _totalDirectEarnings =
          (wallet['cash_in_hand_balance'] as num?)?.toDouble() ?? 0.0;
      _totalCommissionDue =
          (wallet['commission_due'] as num?)?.toDouble() ?? 0.0;
      _receivablePix =
          (wallet['receivable_pix_platform'] as num?)?.toDouble() ?? 0.0;
      _receivableCard =
          (wallet['receivable_card_platform'] as num?)?.toDouble() ?? 0.0;
      _cancellationPending =
          (wallet['cancellation_fees_pending'] as num?)?.toDouble() ?? 0.0;

      // Verificar conexão Mercado Pago (usando ID inteiro)
      _isMPConnected = await _mpService.isConnected(intUserId.toString());

      PaymentAuditLogger.logDriverWalletSnapshot(
        driverUserId: intUserId.toString(),
        mode: (_currentMode ?? 'platform').toString(),
        appBalancePending: _totalAppBalance,
        commissionDueTotal: _totalCommissionDue,
        directEarningsTotal: _totalDirectEarnings,
        paymentsCount: 0,
        amountsByMethod: const {},
        driverDailyFeeAmount: dailyFeeAmount,
        driverPlatformTxFeeRate: platformTxFeeRate,
        source: 'driver_earnings_card',
      );

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _updateMode(String newMode) async {
    try {
      if (newMode != 'platform' && newMode != 'fixed') {
        return;
      }
      await _api.updateProfile(customFields: {'driver_payment_mode': newMode});

      setState(() => _currentMode = newMode);
      widget.onModeChanged?.call();
    } catch (e) {
      debugPrint('❌ Erro ao atualizar modo: $e');
      if (mounted) {
        final msg = _friendlyModeUpdateError(e);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(msg), backgroundColor: Colors.red.shade800),
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
    return 'Não foi possível atualizar o modo agora.';
  }

  void _toggleExpanded() {
    setState(() => _isExpanded = !_isExpanded);
    if (_isExpanded) {
      _expandController.forward();
    } else {
      _expandController.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Container(
        margin: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 60,
          left: 16,
          right: 16,
        ),
        height: 80,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 20),
          ],
        ),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final mode = _currentMode ?? 'platform';
    final screenHeight = MediaQuery.of(context).size.height;
    final viewPadding = MediaQuery.of(context).viewPadding;
    final topPadding = viewPadding.top;
    final bottomPadding = viewPadding.bottom;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 500),
      curve: Curves.fastOutSlowIn,
      height: _isExpanded ? screenHeight - topPadding - bottomPadding - 40 : 95,
      margin: EdgeInsets.only(
        top: topPadding + 10,
        left: 12,
        right: 12,
        bottom: bottomPadding + 10,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
        border: Border.all(color: Colors.grey[100]!, width: 1.5),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: Column(
          children: [
            // HEADER (FIXO)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              child: Row(
                children: [
                  _buildHeaderIcon(
                    icon: Icons.person_outline_rounded,
                    onTap: widget.onProfileTap,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: widget.onToggleOnline,
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: (widget.isActive ? Colors.green : Colors.red)
                              .withOpacity(0.06),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: (widget.isActive ? Colors.green : Colors.red)
                                .withOpacity(0.15),
                            width: 1,
                          ),
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: widget.isActive
                                    ? Colors.green
                                    : Colors.red,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 22),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,

                                children: [
                                  const SizedBox(height: 8),
                                  Text(
                                    widget.isActive ? 'ONLINE' : ' OFFLINE',
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w900,
                                      color: widget.isActive
                                          ? Colors.green[700]
                                          : Colors.red[700],
                                    ),
                                  ),
                                  Text(
                                    widget.isActive ? '' : '',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: _toggleExpanded,
                    child: Container(
                      width: 44,
                      height: 64,
                      decoration: BoxDecoration(
                        color: Colors.grey[50],
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        _isExpanded
                            ? Icons.keyboard_arrow_up_rounded
                            : Icons.keyboard_arrow_down_rounded,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  _buildHeaderIcon(
                    icon: Icons.notifications_none_rounded,
                    onTap: widget.onNotificationsTap,
                    badgeCount: widget.notificationCount,
                  ),
                ],
              ),
            ),

            // CONTEÚDO SCROLLABLE (EXPANDIDO)
            if (_isExpanded)
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(
                    parent: AlwaysScrollableScrollPhysics(),
                  ),
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 30),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildWalletSection(),
                      const SizedBox(height: 24),
                      const Text(
                        'MODELO DE TRABALHO',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          _buildMainModeButton(
                            'platform',
                            'COMISSÃO',
                            'PIX 5% • Cartão 10%',
                            Icons.analytics_rounded,
                          ),
                          const SizedBox(width: 12),
                          _buildMainModeButton(
                            'fixed',
                            'TAXA DIÁRIA',
                            'R\$ 10/dia • Receba direto',
                            Icons.verified_user_rounded,
                          ),
                        ],
                      ),
                      const SizedBox(height: 32),
                      _buildModeExplanation(mode),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderIcon({
    required IconData icon,
    required VoidCallback onTap,
    int badgeCount = 0,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 64,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.grey[100]!),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, size: 24, color: Colors.grey[700]),
            if (badgeCount > 0)
              Positioned(
                top: 15,
                right: 15,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Colors.red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildWalletSection() {
    final receivableTotal =
        _receivablePix + _receivableCard + _cancellationPending;
    final netTotal = (_totalAppBalance + receivableTotal) - _totalCommissionDue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              Icons.account_balance_wallet_rounded,
              size: 18,
              color: Colors.grey[600],
            ),
            const SizedBox(width: 8),
            const Text(
              'MINHA CARTEIRA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.grey,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildBalanceCard(
          title: 'DISPONÍVEL PARA SAQUE',
          amount: _totalAppBalance,
          color: Colors.green,
          icon: Icons.account_balance_rounded,
          buttonText: 'SOLICITAR SAQUE',
          onTap: _totalAppBalance > 0 ? _showPayoutDialog : null,
        ),
        const SizedBox(height: 12),
        if (_receivablePix > 0 || _receivableCard > 0)
          _buildBalanceCard(
            title: 'A RECEBER (PLATAFORMA)',
            amount: _receivablePix + _receivableCard,
            color: Colors.indigo,
            icon: Icons.schedule_rounded,
            subtitle:
                'PIX: ${_formatMoney(_receivablePix)} • Cartão: ${_formatMoney(_receivableCard)}',
          ),
        if (_receivablePix > 0 || _receivableCard > 0)
          const SizedBox(height: 12),
        if (_totalCommissionDue > 0)
          _buildBalanceCard(
            title: 'TAXAS PENDENTES (DÍVIDA)',
            amount: _totalCommissionDue,
            color: Colors.red,
            icon: Icons.error_outline_rounded,
            buttonText: 'PAGAR AGORA',
            onTap: () => DriverDebtPixDialog.show(context, _totalCommissionDue),
          ),
        const SizedBox(height: 12),
        if (_cancellationPending > 0)
          _buildBalanceCard(
            title: 'TAXAS DE CANCELAMENTO (PENDENTE)',
            amount: _cancellationPending,
            color: Colors.deepOrange,
            icon: Icons.warning_amber_rounded,
            subtitle: 'Créditos de cancelamento a receber',
          ),
        if (_cancellationPending > 0) const SizedBox(height: 12),
        _buildBalanceCard(
          title: 'TOTAL LÍQUIDO (APÓS DÍVIDA)',
          amount: netTotal,
          color: netTotal >= 0 ? Colors.black : Colors.red,
          icon: Icons.summarize_rounded,
          subtitle:
              'Saldo: ${_formatMoney(_totalAppBalance)} • A receber: ${_formatMoney(receivableTotal)} • Dívida: ${_formatMoney(_totalCommissionDue)}',
        ),
        const SizedBox(height: 12),
        _buildBalanceCard(
          title: 'RECEBIDO EM MÃOS (DIRETO)',
          amount: _totalDirectEarnings,
          color: Colors.blueGrey,
          icon: Icons.payments_rounded,
          subtitle: 'Dinheiro / Máquina Própria',
        ),
        const SizedBox(height: 24),
        _buildMPConnectionSection(),
      ],
    );
  }

  Widget _buildMPConnectionSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(Icons.sync_alt_rounded, size: 18, color: Colors.blue[600]),
            const SizedBox(width: 8),
            Text(
              'CONTA DE RECEBIMENTO',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w900,
                color: Colors.blue[600],
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isMPConnected ? Colors.blue[50] : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: _isMPConnected ? Colors.blue[100]! : Colors.grey[100]!,
            ),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF009EE3).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.account_balance_rounded,
                  color: Color(0xFF009EE3),
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'MERCADO PAGO',
                      style: GoogleFonts.manrope(
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        color: Colors.grey[500],
                      ),
                    ),
                    Row(
                      children: [
                        Text(
                          _isMPConnected ? 'Conta Vinculada' : 'Não Vinculado',
                          style: GoogleFonts.manrope(
                            fontSize: 16,
                            fontWeight: FontWeight.w900,
                            color: _isMPConnected
                                ? Colors.blue[900]
                                : Colors.black87,
                          ),
                        ),
                        if (_isMPConnected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            color: Colors.green,
                            size: 18,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (!_isMPConnected)
                ElevatedButton(
                  onPressed: _handleMPConnect,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF009EE3),
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: Text(
                    'CONECTAR',
                    style: GoogleFonts.manrope(
                      fontSize: 11,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              if (_isMPConnected)
                IconButton(
                  onPressed: _handleMPDisconnect,
                  icon: Icon(
                    Icons.link_off_rounded,
                    color: Colors.red[400],
                    size: 22,
                  ),
                  tooltip: 'Desconectar conta',
                ),
            ],
          ),
        ),
      ],
    );
  }

  void _handleMPConnect() async {
    try {
      final intUserId = _api.userIdInt;
      if (intUserId == null) throw Exception('Usuário não identificado.');
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
          builder: (_) => const MercadoPagoConnectWebViewScreen(role: 'driver'),
        ),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Finalize a conexão com o Mercado Pago.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
      if (result == true) {
        await _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao iniciar conexão: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _handleMPDisconnect() async {
    try {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Desconectar Conta'),
          content: const Text(
            'Deseja realmente desconectar sua conta do Mercado Pago? Você deixará de receber pagamentos diretamente nela.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('CANCELAR'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('DESCONECTAR'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        setState(() => _isLoading = true);
        try {
          await _api.disconnectDriverMercadoPago();
          // Forçamos a atualização imediata do estado de conexão
          _isMPConnected = false;
        } finally {
          await _loadData();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Conta desconectada com sucesso.'),
                backgroundColor: Colors.green,
              ),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao desconectar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildBalanceCard({
    required String title,
    required double amount,
    required Color color,
    required IconData icon,
    String? subtitle,
    String? buttonText,
    VoidCallback? onTap,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.grey[100]!),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.08),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(icon, color: color, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey[500],
                  ),
                ),
                Text(
                  'R\$ ${amount.toStringAsFixed(2).replaceAll('.', ',')}',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle,
                    style: GoogleFonts.manrope(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: Colors.grey[400],
                    ),
                  ),
              ],
            ),
          ),
          if (buttonText != null)
            ElevatedButton(
              onPressed: onTap,
              style: ElevatedButton.styleFrom(
                backgroundColor: buttonText == 'PAGAR AGORA'
                    ? Colors.red
                    : (onTap != null ? color : Colors.grey[200]),
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                buttonText,
                style: GoogleFonts.manrope(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMainModeButton(
    String mode,
    String title,
    String sub,
    IconData icon,
  ) {
    final isSelected = _currentMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () => _updateMode(mode),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected ? Colors.blue[50] : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? Colors.blue : Colors.grey[200]!,
              width: isSelected ? 2.0 : 1.0,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 32,
                color: isSelected ? Colors.blue : Colors.grey[400],
              ),
              const SizedBox(height: 12),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: isSelected ? Colors.blue : Colors.grey[700],
                ),
              ),
              Text(
                sub,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.blue.withOpacity(0.7)
                      : Colors.grey[400],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildModeExplanation(String mode) {
    String title = '';
    String description = '';
    Color color = mode == 'platform' ? Colors.orange : Colors.blue;

    List<Widget> flowItems = [];

    if (mode == 'platform') {
      title = 'MODO COMISSÃO';
      description = 'PIX: 5% de comissão • Cartão: 10% de comissão.';
      flowItems = [
        _buildFlowStep(Icons.person_rounded, 'Passageiro', Colors.grey[600]!),
        _buildFlowArrow(color),
        _buildFlowStep(Icons.business_rounded, 'App (taxa)', color),
        _buildFlowArrow(color),
        _buildFlowStep(
          Icons.directions_car_rounded,
          'Você (Net)',
          Colors.green,
        ),
      ];
    } else {
      title = 'TAXA DIÁRIA';
      description = 'R\$ 10 por dia. Você recebe diretamente na sua máquina.';
      flowItems = [
        _buildFlowStep(Icons.person_rounded, 'Passageiro', Colors.grey[600]!),
        _buildFlowArrow(Colors.green),
        _buildFlowStep(
          Icons.point_of_sale_rounded,
          'Sua máquina',
          Colors.green,
        ),
        _buildFlowArrow(Colors.green),
        _buildFlowStep(
          Icons.directions_car_rounded,
          'Você (100%)',
          Colors.green,
        ),
      ];
    }

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: color.withOpacity(0.06),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: color.withOpacity(0.15), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 20, color: color),
              const SizedBox(width: 10),
              Text(
                title,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey[700],
              fontWeight: FontWeight.w600,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 20),
          // ARTE DO FLUXO
          Container(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.5),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: flowItems,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFlowStep(IconData icon, String label, Color color) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: color, size: 20),
        ),
        const SizedBox(height: 6),
        Text(
          label,
          style: GoogleFonts.manrope(
            fontSize: 9,
            fontWeight: FontWeight.w800,
            color: color == Colors.green ? Colors.green[700] : Colors.grey[700],
          ),
        ),
      ],
    );
  }

  Widget _buildFlowArrow(Color color) {
    return Icon(
      Icons.arrow_forward_ios_rounded,
      size: 14,
      color: color.withOpacity(0.3),
    );
  }

  void _showPayoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: const Text(
          'Solicitar Saque',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        content: Text(
          'Valor do Saque: R\$ ${_totalAppBalance.toStringAsFixed(2)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCELAR'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CONFIRMAR'),
          ),
        ],
      ),
    );
  }
}
