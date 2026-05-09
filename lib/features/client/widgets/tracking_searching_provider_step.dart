import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

class TrackingSearchingProviderStep extends StatelessWidget {
  final String title;
  final String subtitle;

  const TrackingSearchingProviderStep({
    super.key,
    required this.title,
    required this.subtitle,
  });

  ({String label, String detail, IconData icon}) _searchingActionForUi(
    String title,
    String subtitle,
  ) {
    final base = '$title $subtitle'.toLowerCase();

    if (base.contains('aguardando resposta')) {
      return (
        label: 'Aguardando resposta do prestador',
        detail:
            'A tentativa atual já foi enviada e estamos aguardando o retorno deste prestador dentro da janela de 30 segundos.',
        icon: LucideIcons.timer,
      );
    }
    if (base.contains('novo contato enviado') ||
        base.contains('prestador notificado') ||
        base.contains('contato enviado')) {
      return (
        label: 'Notificando o prestador mais próximo',
        detail:
            'A solicitação foi enviada para um prestador elegível priorizado por distância, dentro do fluxo de até 3 rodadas.',
        icon: LucideIcons.send,
      );
    }
    if (base.contains('buscando novo prestador') ||
        base.contains('ampliando a busca') ||
        base.contains('busca continua ativa') ||
        base.contains('sem retorno')) {
      return (
        label: 'Chamando o próximo mais próximo',
        detail:
            'O último contato não avançou e a plataforma agora segue para a próxima tentativa elegível por ordem de distância.',
        icon: LucideIcons.refreshCcw,
      );
    }
    return (
      label: 'Buscando o prestador mais próximo',
      detail:
          'Estamos consultando um prestador por vez, começando pelo mais próximo elegível, em até 3 rodadas.',
      icon: LucideIcons.radar,
    );
  }

  String _nextSearchActionLabel(String title, String subtitle) {
    final base = '$title $subtitle'.toLowerCase();
    if (base.contains('aguardando resposta')) {
      return 'Se não houver resposta em 30 segundos, a plataforma avança para a próxima tentativa elegível.';
    }
    if (base.contains('contactando') ||
        base.contains('notificado') ||
        base.contains('enviado')) {
      return 'Próximo passo: aguardar a confirmação deste prestador.';
    }
    if (base.contains('novo prestador') || base.contains('ampliando a busca')) {
      return 'Próximo passo: enviar nova tentativa para o próximo prestador elegível dentro das 3 rodadas.';
    }
    return 'Próximo passo: manter a busca sequencial por distância até o aceite ou o fim das 3 rodadas.';
  }

  String _searchRetryCountdownLabel() {
    final cycleSeconds = 30;
    final now = DateTime.now();
    final seconds = now.second % cycleSeconds;
    final remaining = seconds == 0 ? cycleSeconds : cycleSeconds - seconds;
    return '${remaining}s';
  }

  @override
  Widget build(BuildContext context) {
    final action = _searchingActionForUi(title, subtitle);
    final nextAction = _nextSearchActionLabel(title, subtitle);
    final retryIn = _searchRetryCountdownLabel();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.primaryBlue.withOpacity(0.18)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(LucideIcons.radar, size: 12, color: Colors.white),
                    SizedBox(width: 6),
                    Text(
                      'Busca ativa',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const Spacer(),
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: AppTheme.primaryBlue.withOpacity(0.10),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        AppTheme.primaryBlue,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            action.label,
            style: const TextStyle(
              fontSize: 17,
              height: 1.15,
              fontWeight: FontWeight.w900,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            action.detail,
            style: TextStyle(
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 14),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryYellow.withOpacity(0.22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(action.icon, size: 15, color: Colors.black87),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Ação ativa agora',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            title.trim().isNotEmpty
                                ? title.trim()
                                : action.label,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: AppTheme.primaryBlue.withOpacity(0.10),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        LucideIcons.arrowRight,
                        size: 15,
                        color: AppTheme.primaryBlue,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Próxima ação da plataforma',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                              color: Colors.black54,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            nextAction,
                            style: TextStyle(
                              fontSize: 12,
                              height: 1.35,
                              fontWeight: FontWeight.w800,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      margin: const EdgeInsets.only(left: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF7D6),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        retryIn,
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
