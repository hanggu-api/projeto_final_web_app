import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:service_101/core/theme/app_theme.dart';
import '../models/tracking_state.dart';
import './driver_info_card.dart';

class ServicePanelContent extends StatelessWidget {
  static final Set<String> _directPaymentConfirmShown = <String>{};

  final TrackingState state;
  final VoidCallback onCall;
  final VoidCallback onMessage;
  final VoidCallback onCancel;
  final VoidCallback? onSimulatePixPaid;

  const ServicePanelContent({
    super.key,
    required this.state,
    required this.onCall,
    required this.onMessage,
    required this.onCancel,
    this.onSimulatePixPaid,
  });

  @override
  Widget build(BuildContext context) {
    const providerSingular = 'prestador';
    const providerPlural = 'prestadores';

    String title = 'Procurando prestadores...';
    String address = state.tripData?['pickup_address'] ?? 'Aguarde um momento';
    IconData statusIcon = LucideIcons.search;

    final isArrived = state.status == TripStatus.arrived;
    Color headerBgColor = Colors.transparent;
    Color headerTextColor = AppTheme.textDark;
    Color iconBgColor = Colors.blue.withOpacity(0.1);
    Color iconColor = Colors.blueAccent;
    String timerText = '';
    final isApproachingForPix =
        state.status == TripStatus.inProgress &&
        state.isNearDestination &&
        (state.isLoadingPix || state.pixPayload != null);

    if (state.status == TripStatus.pending_payment) {
      title = 'Aguardando pagamento...';
      address =
          'A busca por $providerPlural iniciará após a confirmação do pagamento.';
      statusIcon = LucideIcons.creditCard;
      iconColor = Colors.orange;
      iconBgColor = Colors.orange.withOpacity(0.1);
    } else if (state.status == TripStatus.searching) {
      title = state.showPulse
          ? 'Notificando $providerPlural...'
          : 'Aguardando resposta...';
      address = 'Buscando o melhor $providerSingular para você';
      statusIcon = LucideIcons.search;
    } else if (state.status == TripStatus.cancelled) {
      title = 'Serviço cancelado';
      address = 'Sua solicitação de serviço foi encerrada';
      statusIcon = LucideIcons.alertCircle;
      iconColor = Colors.redAccent;
      iconBgColor = Colors.red.withOpacity(0.1);
    } else if (state.status == TripStatus.noDrivers) {
      title = 'Prestador indisponível';
      address = 'Tente novamente em alguns instantes';
      statusIcon = LucideIcons.alertCircle;
      iconColor = Colors.redAccent;
      iconBgColor = Colors.red.withOpacity(0.1);
    } else if ([
      TripStatus.accepted,
      TripStatus.driverEnRoute,
    ].contains(state.status)) {
      title = 'Prestador a caminho';
      address =
          state.tripData?['pickup_address'] ?? 'Local do serviço';
      statusIcon = LucideIcons.navigation;
    } else if (state.status == TripStatus.inProgress) {
      if (state.isPaid) {
        final methodStr = _resolvePaymentMethod();
        title = 'Pagamento confirmado';
        address = 'Pagamento ${_friendlyPaymentLabel(methodStr)} confirmado.';
        statusIcon = LucideIcons.checkCircle;
        iconColor = Colors.green;
        iconBgColor = Colors.green.withOpacity(0.1);
      } else {
        title = isApproachingForPix
                    ? 'Estamos chegando ao local do serviço'
                    : 'A caminho do local do serviço';
        address =
            state.tripData?['dropoff_address'] ?? 'Local do serviço';
        statusIcon = LucideIcons.mapPin;
      }
    } else if (state.status == TripStatus.completed) {
      final isPaid = state.isPaid;
      final methodStr = _resolvePaymentMethod();
      final isPix = _isPixMethod(methodStr) || state.pixPayload != null;
      final isDirect = _isDirectDriverPaymentMethod(methodStr);
      final isCard = _isCardMethod(methodStr);

      title = 'Serviço finalizado';
      if (isPix) {
        address = isPaid
            ? 'Pagamento PIX confirmado.'
            : 'Aguardando confirmação do PIX';
      } else if (isDirect) {
        address = isPaid
            ? 'Pagamento direto confirmado.'
            : 'Pagamento direto pendente.';
      } else if (isCard) {
        // Para cartão, não exibir "pendente/aguardando" na UI.
        address = 'Pagamento no cartão registrado.';
      } else {
        address =
            isPaid
                ? 'Pagamento confirmado.'
                : 'Serviço concluído.';
      }

      statusIcon = isPaid
          ? LucideIcons.checkCircle
          : (isPix ? LucideIcons.qrCode : LucideIcons.checkCircle2);
      iconColor = isPaid ? Colors.green : (isPix ? Colors.orange : Colors.blue);
      final iconBase = isPaid
          ? Colors.green
          : (isPix ? Colors.orange : Colors.blue);
      iconBgColor = iconBase.withOpacity(0.1);
    } else if (isArrived) {
      statusIcon = LucideIcons.clock;
      // ... (keeping arrival logic)
      final elapsed = state.waitingSeconds;
      final mins = (elapsed / 60).floor();
      final secs = (elapsed % 60);
      timerText =
          '${mins.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';

      if (elapsed < 60) {
        headerBgColor = Colors.green.shade50;
        headerTextColor = Colors.green.shade800;
        iconBgColor = Colors.green.shade100;
        iconColor = Colors.green.shade700;
        title = 'Prestador aguardando';
      } else if (elapsed < 105) {
        headerBgColor = Colors.orange.shade50;
        headerTextColor = Colors.orange.shade800;
        iconBgColor = Colors.orange.shade100;
        iconColor = Colors.orange.shade700;
        title = 'Apresse-se, por favor';
      } else {
        headerBgColor = Colors.red.shade50;
        headerTextColor = Colors.red.shade800;
        iconBgColor = Colors.red.shade100;
        iconColor = Colors.red.shade700;
        title = elapsed >= 120 ? 'Tempo esgotado!' : 'Tempo quase esgotado';
      }
      address = 'Encontre o prestador no local do serviço';
    }

    final isSearching = state.status == TripStatus.searching;
    final canCancelUntilBoarding = <TripStatus>{
      TripStatus.accepted,
      TripStatus.driverEnRoute,
      TripStatus.arrived,
    }.contains(state.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isArrived)
          _buildArrivedHeader(
            headerBgColor,
            iconBgColor,
            headerTextColor,
            title,
            statusIcon,
            iconColor,
            timerText,
          )
        else if (isSearching)
          _buildSearchingHeader(state)
        else
          _buildNormalHeader(
            title,
            address,
            // Container azul claro como na Image 2 Marina! Marina! Marina!
            const Color(0xFFE8F4FF),
            statusIcon,
            const Color(0xFF2B80FF),
          ),

        const SizedBox(height: 12),

        if (!isSearching) ...[
          if (state.isLoadingDriver || state.driverProfile == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            DriverInfoCard(
              driverProfile: state.driverProfile,
              distanceToPickup: state.distanceToPickup,
              onCall: onCall,
              onMessage: onMessage,
              onCancel: canCancelUntilBoarding ? onCancel : null,
              showChat: state.status != TripStatus.completed,
              compactCancelOnly: false,
            ),
          Builder(
            builder: (context) {
              final methodStr = _resolvePaymentMethod();
              final isDirect =
                  _isDirectDriverPaymentMethod(methodStr) &&
                  !_isPixMethod(methodStr) &&
                  !state.usePixDirectWithDriver;
              if (!isDirect || state.status != TripStatus.inProgress) {
                return const SizedBox.shrink();
              }

              _maybeShowDirectPaymentConfirm(context, methodStr);

              return Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF9E6),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: const Color(0xFFFFE082),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        LucideIcons.banknote,
                        color: Color(0xFFE65100),
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Pague diretamente ao prestador: '
                          'R\$ ${_resolvedTripAmount().toStringAsFixed(2)}. '
                          'O prestador irá confirmar o recebimento.',
                          style: GoogleFonts.manrope(
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFFE65100),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          SizedBox(height: _shouldShowPixPaymentSection() ? 8 : 12),
        ],

        // Botão de Cancelamento exclusivo para o estado de Busca Marina! Marina! Marina!
        if (isSearching)
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onCancel,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF1F4F8),
                foregroundColor: AppTheme.textDark,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                'CANCELAR SOLICITAÇÃO',
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                ),
              ),
            ),
          ),

        if (_shouldShowPixPaymentSection()) ...[
          const SizedBox(height: 8),
          _buildPixPaymentSection(context),
        ],
      ],
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0.0;
  }

  double _resolvedTripAmount() {
    final finalFare = _toDouble(state.tripData?['fare_final']);
    if (finalFare > 0) return finalFare;
    return _toDouble(state.tripData?['fare_estimated']);
  }

  String _resolvePaymentMethod() {
    final paymentMethod = state.tripData?['payment_method']?.toString().trim();
    if (paymentMethod != null && paymentMethod.isNotEmpty) {
      return paymentMethod.toUpperCase();
    }
    final paymentMethodId = state.tripData?['payment_method_id']
        ?.toString()
        .trim();
    if (paymentMethodId != null && paymentMethodId.isNotEmpty) {
      return paymentMethodId.toUpperCase();
    }
    final preferredMethod = state.tripData?['preferred_payment_method']
        ?.toString()
        .trim();
    if (preferredMethod != null && preferredMethod.isNotEmpty) {
      return preferredMethod.toUpperCase();
    }
    return '';
  }

  bool _isPixMethod(String method) {
    final m = method.toUpperCase();
    return m.contains('PIX') && !_isPixDirectMethod(m);
  }

  bool _isPixDirectMethod(String method) {
    final m = method.toUpperCase();
    return m.contains('PIX_DIRECT') ||
        (m.contains('PIX') && m.contains('DIRETO'));
  }

  bool _isCardMachineMethod(String method) {
    final m = method.toUpperCase();
    return m.contains('CARD_MACHINE') ||
        m.contains('MACHINE') ||
        m.contains('MAQUINA') ||
        m.contains('MÁQUINA');
  }

  bool _isCashOnlyMethod(String method) {
    final m = method.toUpperCase();
    return m.contains('DINHEIRO') || m.contains('CASH');
  }

  bool _isDirectDriverPaymentMethod(String method) {
    final m = method.toUpperCase();
    return _isCashOnlyMethod(m) ||
        m.contains('DIRETO') ||
        _isPixDirectMethod(m) ||
        _isCardMachineMethod(m);
  }

  bool _isCardMethod(String method) {
    final m = method.toUpperCase();
    if (m.isEmpty) return false;
    final looksLikeToken =
        m.startsWith('CARD_') ||
        m.startsWith('PM_') ||
        m.startsWith('TOK_') ||
        m.contains('CREDIT') ||
        m.contains('CARTAO') ||
        m.contains('CARTÃO') ||
        m.contains('DEBIT') ||
        m.contains('DÉBITO');
    final looksLikeUuid = RegExp(
      r'^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$',
      caseSensitive: false,
    ).hasMatch(m);
    return looksLikeToken || looksLikeUuid;
  }

  String _extractLast4(String method) {
    final digits = method.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length >= 4) return digits.substring(digits.length - 4);
    return '';
  }

  String _friendlyPaymentLabel(String method) {
    final providerSingular = state.isService ? 'prestador' : 'motorista';
    if (_isPixDirectMethod(method)) return 'PIX (direto ao $providerSingular)';
    if (_isPixMethod(method)) return 'PIX';
    if (_isCardMachineMethod(method)) {
      final m = method.toUpperCase();
      if (m.contains('DIGITAL')) return 'Cartão na maquininha (digital)';
      if (m.contains('PHYSICAL') ||
          m.contains('FISICO') ||
          m.contains('FÍSICO')) {
        return 'Cartão na maquininha (físico)';
      }
      return 'Cartão na maquininha ($providerSingular)';
    }
    if (_isCashOnlyMethod(method) || method.toUpperCase().contains('DIRETO')) {
      return 'Pagamento direto ao $providerSingular';
    }
    if (_isCardMethod(method)) {
      final last4 = _extractLast4(method);
      return last4.isNotEmpty
          ? 'Cartão de crédito •••• $last4'
          : 'Cartão de crédito';
    }
    return method.isNotEmpty ? method : 'Método não informado';
  }

  bool _shouldShowPixPaymentSection() {
    if (state.status == TripStatus.completed) return true;
    if (state.status == TripStatus.inProgress) {
      final method = _resolvePaymentMethod();
      if (_isDirectDriverPaymentMethod(method) &&
          !state.usePixDirectWithDriver) {
        return true;
      }

      // Se for método PIX, mostra se estiver perto ou se o payload já existir/carregando
      final isPix = _isPixMethod(method);
      if (!isPix) return false;

      // Regra: não gerar/exibir PIX cedo demais.
      // O PIX da plataforma será gerado automaticamente quando estiver próximo do fim (<= 500m),
      // então só mostramos a seção quando já estivermos carregando/tenhamos o payload.
      return state.isPaid || state.pixPayload != null || state.isLoadingPix;
    }
    return false;
  }

  Widget _buildSearchingHeader(TrackingState state) {
    final pickupLabel = state.isService ? 'LOCAL' : 'PARTIDA';
    final destinationLabel = state.isService ? 'SERVIÇO' : 'DESTINO';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                state.isService
                    ? 'Procurando um prestador...'
                    : 'Procurando um prestador...',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '101 X',
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: Colors.blueAccent,
                  ),
                ),
                Text(
                  'CATEGORIA',
                  style: GoogleFonts.manrope(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: Colors.grey,
                    letterSpacing: 1,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          state.isService
              ? 'Localizando prestadores próximos na sua área'
              : 'Localizando veículos próximos na sua área',
          style: GoogleFonts.manrope(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey,
          ),
        ),
        const SizedBox(height: 16),

        // Barra de progresso linear amarela Marina! Marina! Marina!
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: LinearProgressIndicator(
            backgroundColor: AppTheme.primaryYellow.withOpacity(0.1),
            valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryYellow),
            minHeight: 6,
          ),
        ),

        const SizedBox(height: 16),

        // Badge de busca ativa Marina! Marina! Marina!
        Row(
          children: [
            Icon(
              state.isService ? LucideIcons.wrench : LucideIcons.car,
              color: const Color(0xFF00D1FF),
              size: 18,
            ),
            const SizedBox(width: 8),
            Text(
              state.isService
                  ? 'BUSCANDO PRESTADORES PRÓXIMOS...'
                  : 'BUSCANDO MOTORISTAS PRÓXIMOS...',
              style: GoogleFonts.manrope(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: const Color(0xFF00D1FF),
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),

        const SizedBox(height: 20),

        // Endereços Marina! Marina! Marina!
        _buildAddressItem(
          icon: LucideIcons.mapPin,
          iconColor: Colors.blueAccent,
          label: pickupLabel,
          address:
              state.tripData?['pickup_address'] ??
              (state.isService ? 'Local do serviço' : 'Local de partida'),
        ),
        const Padding(
          padding: EdgeInsets.only(left: 17),
          child: SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              color: Color(0xFFE5E7EB),
              thickness: 2,
            ),
          ),
        ),
        _buildAddressItem(
          icon: LucideIcons.flag,
          iconColor: Colors.grey,
          label: destinationLabel,
          address:
              state.tripData?['dropoff_address'] ??
              (state.isService ? 'Local do serviço' : 'Local de destino'),
        ),
      ],
    );
  }

  Widget _buildAddressItem({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String address,
  }) {
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: iconColor.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(icon, color: iconColor, size: 16),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: Colors.grey,
                  letterSpacing: 1,
                ),
              ),
              Text(
                address,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildArrivedHeader(
    Color bgColor,
    Color borderColor,
    Color textColor,
    String title,
    IconData icon,
    Color iconColor,
    String timer,
  ) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 2),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
                Text(
                  'Taxa de espera em breve',
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: textColor.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, color: iconColor, size: 18),
                const SizedBox(width: 4),
                Text(
                  timer,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNormalHeader(
    String title,
    String address,
    Color iconBg,
    IconData icon,
    Color iconColor,
  ) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  const Icon(LucideIcons.mapPin, size: 14, color: Colors.grey),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      address,
                      style: GoogleFonts.manrope(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: iconBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: iconColor, size: 24),
        ),
      ],
    );
  }

  Widget _buildPixPaymentSection(BuildContext context) {
    final providerSingular = state.isService ? 'prestador' : 'motorista';
    final tripLabel = state.isService ? 'serviço' : 'viagem';
    final isPaid = state.isPaid;
    final methodStr = _resolvePaymentMethod();
    final isPix = _isPixMethod(methodStr) || state.pixPayload != null;
    final isDirect = _isDirectDriverPaymentMethod(methodStr);
    final isCashOnly = _isCashOnlyMethod(methodStr);
    final isCardMachine = _isCardMachineMethod(methodStr);
    final isPixDirect = _isPixDirectMethod(methodStr);
    final isCard = _isCardMethod(methodStr) && !isCardMachine;

    // Regra de negócio (Uber): PIX direto com motorista não é selecionável.
    // Quando o motorista aceita PIX direto, exibimos apenas um aviso perto de 500m do destino.
    if (state.usePixDirectWithDriver) {
      if (!state.showPixDirectPaymentPrompt) return const SizedBox.shrink();
      return _buildPixDirectWithDriverPromptCard();
    }

    if (!isPix) {
      if (isDirect) {
        _maybeShowDirectPaymentConfirm(context, methodStr);
        if (isPaid) {
          return _buildSuccessFeedback(
            title: 'PAGAMENTO RECEBIDO COM SUCESSO',
            message:
                'Seu pagamento de R\$ ${_resolvedTripAmount().toStringAsFixed(2)} foi confirmado pelo $providerSingular.',
            subMessage:
                state.isService ? 'Obrigado por usar a 101!' : 'Obrigado por viajar com a 101!',
          );
        }

        return Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF9E6),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFFE082), width: 2),
          ),
          child: Column(
            children: [
              Icon(
                isCardMachine
                    ? LucideIcons.creditCard
                    : isPixDirect
                    ? LucideIcons.qrCode
                    : LucideIcons.banknote,
                color: const Color(0xFFF57C00),
                size: 48,
              ),
              const SizedBox(height: 12),
              Text(
                state.isService ? 'PAGUE AO PRESTADOR' : 'PAGUE AO MOTORISTA',
                style: GoogleFonts.manrope(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFFE65100),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'VALOR TOTAL: R\$ ${_resolvedTripAmount().toStringAsFixed(2)}',
                style: GoogleFonts.manrope(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: AppTheme.textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isCardMachine
                    ? 'O pagamento deve ser feito diretamente ao $providerSingular na maquininha ao final do $tripLabel.'
                    : isPixDirect
                    ? 'O pagamento deve ser feito diretamente ao $providerSingular via PIX pessoal dele.'
                    : isCashOnly
                    ? 'O pagamento deve ser feito diretamente ao $providerSingular.'
                    : 'O pagamento deve ser feito diretamente ao $providerSingular ao final do $tripLabel.',
                textAlign: TextAlign.center,
                style: GoogleFonts.manrope(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      LucideIcons.info,
                      size: 14,
                      color: Colors.orange,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      state.isService
                          ? 'Aguardando o prestador confirmar...'
                          : 'Aguardando o motorista confirmar...',
                      style: GoogleFonts.manrope(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      }

      if (isCard) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Row(
            children: [
              const Icon(LucideIcons.creditCard, color: Color(0xFF2B80FF)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _friendlyPaymentLabel(methodStr),
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textDark,
                  ),
                ),
              ),
            ],
          ),
        );
      }

      final resolvedMethod = _friendlyPaymentLabel(methodStr);
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            const Icon(LucideIcons.creditCard, color: Colors.grey),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                resolvedMethod,
                style: GoogleFonts.manrope(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.textDark,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (isPaid) {
      return _buildSuccessFeedback(
        title: 'PAGAMENTO CONFIRMADO',
        message:
            state.isService
                ? 'Seu serviço foi pago com sucesso via PIX.'
                : 'Sua corrida foi paga com sucesso via PIX.',
        subMessage:
            state.isService
                ? 'Pagamento confirmado.'
                : 'Pagamento confirmado. Você pode desembarcar com segurança.',
      );
    }

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'PAGUE COM CÓDIGO PIX',
            style: GoogleFonts.manrope(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: AppTheme.textDark,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: 8),
          if (state.isLoadingPix)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (state.pixPayload != null)
            Column(
              children: [
                Text(
                  'VALOR TOTAL: R\$ ${_resolvedTripAmount().toStringAsFixed(2)}',
                  style: GoogleFonts.manrope(
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                    color: AppTheme.textDark,
                  ),
                ),
                const SizedBox(height: 16),
                const SizedBox(height: 12),
                // QR Code removido da visão do passageiro (uso inadequado no mesmo dispositivo)
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade50,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Código copia e cola',
                              style: GoogleFonts.manrope(
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                color: Colors.black54,
                              ),
                            ),
                          ),
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: state.pixPayload!),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Código PIX copiado!'),
                                  backgroundColor: Color(0xFF1E6BFF),
                                ),
                              );
                            },
                            icon: const Icon(LucideIcons.copy, size: 14),
                            label: const Text('COPIAR'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1E6BFF),
                              foregroundColor: Colors.white,
                              elevation: 2,
                              shadowColor: Colors.black26,
                              minimumSize: const Size(0, 32),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SelectableText(
                          state.pixPayload!,
                          style: GoogleFonts.manrope(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textDark,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Abra seu banco, cole o código PIX e confirme o pagamento.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.black54,
                  ),
                ),
                if (kDebugMode && onSimulatePixPaid != null) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: onSimulatePixPaid,
                      icon: const Icon(LucideIcons.playCircle, size: 18),
                      label: const Text('SIMULAR PAGAMENTO PIX (SANDBOX)'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            )
          else
            Column(
              children: [
                Text(
                  'O código PIX será gerado automaticamente quando você estiver próximo do destino.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Assim evitamos PIX expirado/cancelado e mantemos o pagamento mais seguro.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.black45,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  void _maybeShowDirectPaymentConfirm(BuildContext context, String methodStr) {
    if (state.isPaid) return;
    final key = '${state.tripId}:${methodStr.toLowerCase()}';
    if (_directPaymentConfirmShown.contains(key)) return;
    _directPaymentConfirmShown.add(key);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!context.mounted) return;
      final amount = _resolvedTripAmount().toStringAsFixed(2);
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Text(
            'Pagamento direto ao prestador',
          ),
          content: Text(
            'O prestador solicitou pagamento direto.\n\n'
            'Valor (BRL): $amount\n\n'
            'Você confirma que fará o pagamento diretamente ao prestador?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('CONFIRMAR'),
            ),
          ],
        ),
      );
    });
  }

  Widget _buildPixDirectWithDriverPromptCard() {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFFFB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB2F0E6), width: 2),
      ),
      child: Column(
        children: [
          const Icon(LucideIcons.qrCode, color: Color(0xFF00BFA5), size: 44),
          const SizedBox(height: 10),
          Text(
            state.isService
                ? 'PAGUE DIRETO AO PRESTADOR (PIX)'
                : 'PAGUE DIRETO AO MOTORISTA (PIX)',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.w900,
              color: const Color(0xFF00796B),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'VALOR: R\$ ${_resolvedTripAmount().toStringAsFixed(2)}',
            style: GoogleFonts.manrope(
              fontSize: 22,
              fontWeight: FontWeight.w900,
              color: AppTheme.textDark,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            state.isService
                ? 'Estamos chegando. O prestador vai mostrar o QR na maquininha. '
                    'Abra seu banco e pague via PIX diretamente ao prestador.'
                : 'Estamos chegando. O prestador vai mostrar o QR na maquininha. '
                    'Abra seu banco e pague via PIX diretamente ao prestador.',
            textAlign: TextAlign.center,
            style: GoogleFonts.manrope(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessFeedback({
    required String title,
    required String message,
    required String subMessage,
  }) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 800),
      curve: Curves.elasticOut,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFBDD3FF), width: 2),
            ),
            child: Column(
              children: [
                const Icon(
                  LucideIcons.dollarSign,
                  color: Color(0xFF1E6BFF),
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  title,
                  style: GoogleFonts.manrope(
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                    color: const Color(0xFF1458A8),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2A5FCB),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subMessage,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.manrope(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: const Color(0xFF2A5FCB),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
