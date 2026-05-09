import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/remote_ui/remote_screen_body.dart';
import '../../core/theme/app_theme.dart';
import '../../services/app_config_service.dart';
import '../../widgets/app_runtime_diagnostic_banner.dart';

class HomeExploreScreen extends StatefulWidget {
  const HomeExploreScreen({super.key});

  @override
  State<HomeExploreScreen> createState() => _HomeExploreScreenState();
}

class _HomeExploreScreenState extends State<HomeExploreScreen> {
  final AppConfigService _appConfig = AppConfigService();

  @override
  Widget build(BuildContext context) {
    final content = _readHomeMarketingContent();
    final hero = _mapValue(content['hero']);
    final platform = _mapValue(content['platform_steps']);
    final beauty = _mapValue(content['beauty_booking']);
    final payment = _mapValue(content['payment']);
    final security = _mapValue(content['security']);

    final platformSteps = _mapList(platform['steps']);
    final beautyCards = _mapList(beauty['cards']);
    final heroPrimaryAction = _mapValue(hero['primary_cta']);
    final heroSecondaryAction = _mapValue(hero['secondary_cta']);
    final beautyAction = _mapValue(beauty['primary_cta']);
    final securityAction = _mapValue(security['primary_cta']);
    final platformHighlights = _stringList(platform['highlights']);
    final paymentHighlights = _stringList(payment['highlights']);
    final securityHighlights = _stringList(security['highlights']);
    final heroHighlights = _stringList(hero['highlights']);
    final heroEyebrow = _stringValue(hero['eyebrow']);
    final platformSubtitle = _stringValue(platform['subtitle']);
    final securityEyebrow = _stringValue(security['eyebrow']);

    return Scaffold(
      appBar: AppBar(title: const Text('Explorar servicos')),
      bottomNavigationBar: const AppRuntimeDiagnosticBanner(),
      body: SafeArea(
        child: RemoteScreenBody(
          screenKey: 'home_explore',
          padding: const EdgeInsets.symmetric(vertical: 16),
          fallbackBuilder: (context) => ListView(
            padding: const EdgeInsets.symmetric(vertical: 16),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(24),
                        child: _buildConfigurableImage(
                          imageUrl: _stringValue(hero['image_url']),
                          fallbackAssetPath: 'assets/images/hero_destaque.jpg',
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Container(
                      width: double.infinity,
                      height: 220,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.06),
                            const Color(0xFF0D1B2A).withValues(alpha: 0.72),
                          ],
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 16,
                      left: 16,
                      right: 16,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (heroEyebrow.isNotEmpty) ...[
                            _buildMarketingEyebrow(
                              heroEyebrow,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.18,
                              ),
                              textColor: Colors.white,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            _stringValue(hero['title']),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 26,
                              height: 1.05,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _stringValue(hero['description']),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.9),
                              fontSize: 13,
                              height: 1.35,
                            ),
                          ),
                          if (heroHighlights.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildMarketingHighlightWrap(
                              heroHighlights,
                              backgroundColor: Colors.white.withValues(
                                alpha: 0.12,
                              ),
                              textColor: Colors.white,
                            ),
                          ],
                          if (heroPrimaryAction.isNotEmpty ||
                              heroSecondaryAction.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                if (heroPrimaryAction.isNotEmpty)
                                  _buildMarketingActionButton(
                                    heroPrimaryAction,
                                    isPrimary: true,
                                  ),
                                if (heroSecondaryAction.isNotEmpty)
                                  _buildMarketingActionButton(
                                    heroSecondaryAction,
                                    isPrimary: false,
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildMarketingSurface(
                  color: const Color(0xFFFDFDFD),
                  borderColor: const Color(0xFFEAECEF),
                  shadowColor: const Color(0xFF0F172A),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMarketingEyebrow(
                        'Fluxo da plataforma',
                        backgroundColor: const Color(0xFFF3F5F7),
                        textColor: AppTheme.darkBlueText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _stringValue(platform['title']),
                        style: TextStyle(
                          color: AppTheme.darkBlueText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      if (platformSubtitle.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Text(
                          platformSubtitle,
                          style: TextStyle(
                            color: AppTheme.darkBlueText.withValues(
                              alpha: 0.72,
                            ),
                            fontSize: 13,
                            height: 1.35,
                          ),
                        ),
                      ],
                      if (platformHighlights.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        _buildMarketingHighlightWrap(
                          platformHighlights,
                          backgroundColor: const Color(0xFFF3F5F7),
                          textColor: AppTheme.darkBlueText,
                        ),
                      ],
                      const SizedBox(height: 16),
                      for (var i = 0; i < platformSteps.length; i++) ...[
                        _buildPlatformStep(
                          icon: _resolveMarketingIcon(
                            _stringValue(platformSteps[i]['icon_key']),
                          ),
                          title: _stringValue(platformSteps[i]['title']),
                          description: _stringValue(
                            platformSteps[i]['description'],
                          ),
                        ),
                        if (i != platformSteps.length - 1)
                          const SizedBox(height: 12),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildMarketingSurface(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF7F0E4), Color(0xFFFFFBF5)],
                  ),
                  borderColor: const Color(0xFFE8D9C0),
                  shadowColor: const Color(0xFFB45309),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildMarketingEyebrow(
                        'Agenda em local parceiro',
                        backgroundColor: Colors.white.withValues(alpha: 0.82),
                        textColor: AppTheme.darkBlueText,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _stringValue(beauty['title']),
                        style: TextStyle(
                          color: AppTheme.darkBlueText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stringValue(beauty['description']),
                        style: TextStyle(
                          color: AppTheme.darkBlueText.withValues(alpha: 0.72),
                          fontSize: 13,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: 16),
                      for (var i = 0; i < beautyCards.length; i++) ...[
                        _buildBeautyBookingCard(
                          imageUrl: _stringValue(beautyCards[i]['image_url']),
                          fallbackAssetPath: i == 0
                              ? 'assets/images/hero_destaque.jpg'
                              : 'assets/images/security_tools.jpg',
                          icon: _resolveMarketingIcon(
                            _stringValue(beautyCards[i]['icon_key']),
                          ),
                          title: _stringValue(beautyCards[i]['title']),
                          description: _stringValue(
                            beautyCards[i]['description'],
                          ),
                          footnote: _stringValue(beautyCards[i]['footnote']),
                          ctaLabel: _stringValue(beautyCards[i]['cta_label']),
                          action: _mapValue(beautyCards[i]['action']),
                        ),
                        if (i != beautyCards.length - 1)
                          const SizedBox(height: 16),
                      ],
                      if (beautyAction.isNotEmpty) ...[
                        const SizedBox(height: 18),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: _buildMarketingActionButton(
                            beautyAction,
                            isPrimary: true,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _buildMarketingSurface(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFFFF8D9), Color(0xFFFFF1C2)],
                  ),
                  borderColor: const Color(0xFFE7C75C),
                  shadowColor: const Color(0xFFE7C75C),
                  child: Column(
                    children: [
                      _buildMarketingEyebrow(
                        'Reserva e pagamento',
                        backgroundColor: Colors.white.withValues(alpha: 0.86),
                        textColor: AppTheme.darkBlueText,
                      ),
                      const SizedBox(height: 12),
                      Icon(
                        Icons.account_balance_wallet_outlined,
                        color: AppTheme.darkBlueText,
                        size: 28,
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _stringValue(payment['title']),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.darkBlueText,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _stringValue(payment['description']),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: AppTheme.darkBlueText,
                          fontSize: 13,
                          height: 1.3,
                        ),
                      ),
                      if (paymentHighlights.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        ...paymentHighlights.map(
                          (highlight) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Icon(
                                  Icons.check_circle_rounded,
                                  color: AppTheme.darkBlueText,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    highlight,
                                    style: TextStyle(
                                      color: AppTheme.darkBlueText.withValues(
                                        alpha: 0.84,
                                      ),
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      height: 1.35,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 360;
                    final securityImage = ClipRRect(
                      borderRadius: isCompact
                          ? const BorderRadius.vertical(
                              top: Radius.circular(24),
                            )
                          : const BorderRadius.horizontal(
                              right: Radius.circular(24),
                            ),
                      child: _buildConfigurableImage(
                        imageUrl: _stringValue(security['image_url']),
                        fallbackAssetPath: 'assets/images/security_tools.jpg',
                        height: isCompact ? 180 : 140,
                        width: double.infinity,
                        fit: BoxFit.cover,
                      ),
                    );

                    final securityContent = Padding(
                      padding: const EdgeInsets.all(20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (securityEyebrow.isNotEmpty) ...[
                            _buildMarketingEyebrow(
                              securityEyebrow,
                              backgroundColor: const Color(0xFFE9EEF5),
                              textColor: AppTheme.darkBlueText,
                            ),
                            const SizedBox(height: 10),
                          ],
                          Text(
                            _stringValue(security['title']),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: AppTheme.darkBlueText,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _stringValue(security['description']),
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              color: AppTheme.darkBlueText.withValues(
                                alpha: 0.6,
                              ),
                            ),
                          ),
                          if (securityHighlights.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            _buildMarketingHighlightWrap(
                              securityHighlights,
                              backgroundColor: Colors.white,
                              textColor: AppTheme.darkBlueText,
                            ),
                          ],
                          if (securityAction.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            _buildMarketingActionButton(
                              securityAction,
                              isPrimary: true,
                            ),
                          ],
                        ],
                      ),
                    );

                    return _buildMarketingSurface(
                      color: const Color(0xFFF7F8FA),
                      borderColor: const Color(0xFFEAECEF),
                      shadowColor: const Color(0xFF0F172A),
                      padding: EdgeInsets.zero,
                      child: isCompact
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [securityImage, securityContent],
                            )
                          : Row(
                              children: [
                                Expanded(flex: 2, child: securityContent),
                                Expanded(child: securityImage),
                              ],
                            ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );
  }

  Map<String, dynamic> _readHomeMarketingContent() {
    final defaults = _defaultHomeMarketingContent();
    final remote = _appConfig.getMap('home_marketing_content_v1');
    return _deepMergeMaps(defaults, remote);
  }

  Map<String, dynamic> _defaultHomeMarketingContent() {
    return {
      'hero': {
        'eyebrow': 'Atendimento movel e em estabelecimentos',
        'title': 'A plataforma 101 Service',
        'description':
            'Encontre prestadores disponiveis perto de voce, compare opcoes e solicite atendimento movel ou em estabelecimento em um so lugar.',
        'image_url': '',
        'highlights': [
          'Profissionais proximos',
          'Busca movel e fixa',
          'Acompanhamento no app',
        ],
        'primary_cta': {
          'label': 'Buscar servicos',
          'action_type': 'search',
          'query': '',
        },
        'secondary_cta': {'label': 'Explorar beleza', 'action_type': 'beauty'},
      },
      'platform_steps': {
        'title': 'Como usar a plataforma',
        'subtitle':
            'Solicite atendimento com poucos toques, acompanhe a resposta do prestador e finalize tudo pelo app.',
        'highlights': [
          'Busca movel e em estabelecimentos',
          'Comparacao rapida de opcoes',
          'Acompanhamento do status em tempo real',
        ],
        'steps': [
          {
            'icon_key': 'search',
            'title': '1. Busque o que voce precisa',
            'description':
                'Pesquise por servicos, escolha a categoria e encontre prestadores disponiveis perto de voce.',
          },
          {
            'icon_key': 'calendar',
            'title': '2. Encontre o prestador ideal',
            'description':
                'Veja os detalhes do atendimento, compare opcoes e siga com o profissional que atende melhor voce.',
          },
          {
            'icon_key': 'thumb',
            'title': '3. Receba ou va ao atendimento',
            'description':
                'Acompanhe o status do servico, fale com o profissional e finalize tudo com mais praticidade.',
          },
        ],
      },
      'beauty_booking': {
        'title': 'Agendamento para beleza e estetica',
        'description':
            'Para salao, estetica e barbearia, a plataforma mostra locais proximos com agenda disponivel para voce reservar o melhor horario.',
        'primary_cta': {
          'label': 'Abrir agenda de beleza',
          'action_type': 'beauty_booking',
        },
        'cards': [
          {
            'icon_key': 'spa',
            'title': 'Salao e estetica',
            'description':
                'Escolha um espaco proximo, veja os horarios livres e confirme seu atendimento de beleza com mais praticidade.',
            'footnote':
                'Reserva com taxa Pix e restante pago diretamente no estabelecimento.',
            'image_url':
                'https://images.pexels.com/photos/705255/pexels-photo-705255.jpeg?cs=srgb&dl=pexels-delbeautybox-211032-705255.jpg&fm=jpg',
            'cta_label': 'Ver opcoes proximas',
            'action': {'action_type': 'beauty'},
          },
          {
            'icon_key': 'cut',
            'title': 'Barbearia',
            'description':
                'Encontre uma barbearia proxima, selecione corte, barba ou acabamento e reserve o horario ideal.',
            'footnote':
                'Chegue no local no horario combinado e conclua o atendimento direto com o profissional.',
            'image_url':
                'https://images.pexels.com/photos/1813272/pexels-photo-1813272.jpeg?cs=srgb&dl=pexels-thgusstavo-1813272.jpg&fm=jpg',
            'cta_label': 'Buscar barbearias',
            'action': {'action_type': 'search', 'query': 'barbearia'},
          },
        ],
      },
      'payment': {
        'title': 'Pagamento alinhado ao tipo de servico',
        'description':
            'No atendimento movel, a reserva segue o sinal da plataforma. Nos agendamentos em estabelecimento, voce paga 10% via Pix para confirmar e 90% direto no local.',
        'highlights': [
          'Reserva protegida pela plataforma',
          'Confirmacao de agenda com Pix',
          'Pagamento final conforme o tipo de atendimento',
        ],
      },
      'security': {
        'eyebrow': 'Confianca e suporte',
        'title': 'Sua protecao\nem primeiro lugar',
        'description': 'Parceiros verificados e atendimento mais seguro.',
        'image_url': '',
        'highlights': [
          'Perfis verificados',
          'Chat com o prestador',
          'Acompanhamento do atendimento',
        ],
        'primary_cta': {'label': 'Preciso de ajuda', 'action_type': 'help'},
      },
    };
  }

  Map<String, dynamic> _deepMergeMaps(
    Map<String, dynamic> base,
    Map<String, dynamic> override,
  ) {
    final merged = <String, dynamic>{...base};
    override.forEach((key, value) {
      final current = merged[key];
      if (current is Map && value is Map) {
        merged[key] = _deepMergeMaps(_mapValue(current), _mapValue(value));
        return;
      }
      if (value is List && value.isNotEmpty) {
        merged[key] = value;
        return;
      }
      if (value != null) {
        merged[key] = value;
      }
    });
    return merged;
  }

  Map<String, dynamic> _mapValue(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map((key, value) => MapEntry(key.toString(), value));
    }
    return <String, dynamic>{};
  }

  List<Map<String, dynamic>> _mapList(dynamic raw) {
    if (raw is! List) return const <Map<String, dynamic>>[];
    return raw
        .map((item) => _mapValue(item))
        .where((item) => item.isNotEmpty)
        .toList();
  }

  String _stringValue(dynamic raw, {String fallback = ''}) {
    final value = raw?.toString().trim() ?? '';
    return value.isEmpty ? fallback : value;
  }

  List<String> _stringList(dynamic raw) {
    if (raw is! List) return const <String>[];
    return raw
        .map((item) {
          if (item is String || item is num || item is bool) {
            return item.toString().trim();
          }
          if (item is Map) {
            final map = _mapValue(item);
            return _stringValue(
              map['label'],
              fallback: _stringValue(
                map['title'],
                fallback: _stringValue(map['text']),
              ),
            );
          }
          return '';
        })
        .where((item) => item.isNotEmpty)
        .toList();
  }

  Future<void> _executeMarketingAction(Map<String, dynamic> action) async {
    final actionType = _stringValue(
      action['action_type'],
      fallback: _stringValue(action['type']),
    ).toLowerCase();
    final query = _stringValue(action['query']);
    final route = _stringValue(
      action['route'],
      fallback: _stringValue(action['target']),
    );
    final url = _stringValue(
      action['url'],
      fallback: _stringValue(action['target']),
    );

    switch (actionType) {
      case 'search':
        context.push('/home-search', extra: {'query': query});
        return;
      case 'services':
        context.push('/home-search');
        return;
      case 'beauty':
        context.push(
          '/home-search',
          extra: query.isNotEmpty
              ? {'query': query}
              : const <String, dynamic>{},
        );
        return;
      case 'beauty_booking':
        context.push('/beauty-booking');
        return;
      case 'help':
        context.push('/help');
        return;
      case 'chats':
        context.push('/chats');
        return;
      case 'route':
        if (route.isNotEmpty) {
          context.push(route);
        }
        return;
      case 'external_url':
        if (url.isEmpty) return;
        final uri = Uri.tryParse(url);
        if (uri == null) return;
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      default:
        if (route.isNotEmpty) {
          context.push(route);
          return;
        }
        if (url.isNotEmpty) {
          final uri = Uri.tryParse(url);
          if (uri != null) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        }
    }
  }

  Widget _buildMarketingEyebrow(
    String label, {
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: textColor,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildMarketingHighlightWrap(
    List<String> items, {
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: items
          .map(
            (item) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: backgroundColor,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                item,
                style: TextStyle(
                  color: textColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
          .toList(),
    );
  }

  Widget _buildMarketingActionButton(
    Map<String, dynamic> action, {
    required bool isPrimary,
  }) {
    final label = _stringValue(action['label']);
    if (label.isEmpty) {
      return const SizedBox.shrink();
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _executeMarketingAction(action),
        borderRadius: BorderRadius.circular(999),
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isPrimary ? AppTheme.primaryYellow : Colors.white,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: isPrimary ? AppTheme.primaryYellow : Colors.grey.shade300,
            ),
            boxShadow: isPrimary
                ? [
                    BoxShadow(
                      color: AppTheme.primaryYellow.withValues(alpha: 0.26),
                      blurRadius: 18,
                      offset: const Offset(0, 8),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: isPrimary ? AppTheme.darkBlueText : Colors.black87,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.arrow_forward_rounded,
                size: 18,
                color: isPrimary ? AppTheme.darkBlueText : Colors.black87,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMarketingSurface({
    required Widget child,
    Gradient? gradient,
    Color? color,
    Color? borderColor,
    Color? shadowColor,
    EdgeInsetsGeometry padding = const EdgeInsets.all(20),
  }) {
    return Container(
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: gradient == null ? (color ?? Colors.white) : null,
        gradient: gradient,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: borderColor ?? const Color(0xFFEAECEF)),
        boxShadow: [
          BoxShadow(
            color: (shadowColor ?? Colors.black).withValues(alpha: 0.08),
            blurRadius: 20,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: child,
    );
  }

  IconData _resolveMarketingIcon(String iconKey) {
    switch (iconKey) {
      case 'calendar':
        return Icons.event_available_rounded;
      case 'thumb':
        return Icons.thumb_up_alt_outlined;
      case 'spa':
        return Icons.spa_outlined;
      case 'cut':
        return Icons.content_cut_rounded;
      case 'search':
      default:
        return Icons.search_rounded;
    }
  }

  Widget _buildPlatformStep({
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFF9FBFC)],
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFEEF1F4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: const Color(0xFFF3F5F7),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: AppTheme.darkBlueText, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.darkBlueText,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: AppTheme.darkBlueText.withValues(alpha: 0.72),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBeautyBookingCard({
    required String imageUrl,
    required String fallbackAssetPath,
    required IconData icon,
    required String title,
    required String description,
    required String footnote,
    required String ctaLabel,
    required Map<String, dynamic> action,
  }) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(22)),
            child: Stack(
              children: [
                _buildConfigurableImage(
                  imageUrl: imageUrl,
                  fallbackAssetPath: fallbackAssetPath,
                  height: 176,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(icon, color: AppTheme.darkBlueText, size: 16),
                        const SizedBox(width: 6),
                        Text(
                          title,
                          style: TextStyle(
                            color: AppTheme.darkBlueText,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: AppTheme.darkBlueText,
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  description,
                  style: TextStyle(
                    color: AppTheme.darkBlueText.withValues(alpha: 0.8),
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  footnote,
                  style: TextStyle(
                    color: AppTheme.darkBlueText.withValues(alpha: 0.62),
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
                if (ctaLabel.isNotEmpty && action.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  _buildMarketingActionButton(action, isPrimary: false),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfigurableImage({
    required String imageUrl,
    required String fallbackAssetPath,
    double? height,
    double? width,
    BoxFit fit = BoxFit.cover,
  }) {
    final resolvedUrl = imageUrl.trim();
    if (resolvedUrl.isEmpty) {
      return Image.asset(
        fallbackAssetPath,
        height: height,
        width: width,
        fit: fit,
      );
    }

    return Image.network(
      resolvedUrl,
      height: height,
      width: width,
      fit: fit,
      errorBuilder: (_, __, ___) => Image.asset(
        fallbackAssetPath,
        height: height,
        width: width,
        fit: fit,
      ),
    );
  }
}
