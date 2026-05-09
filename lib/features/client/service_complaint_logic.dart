class ServiceComplaintLogic {
  static String resolveClaimType({
    required String claimType,
    required String title,
  }) {
    final normalizedClaimType = claimType.trim().toLowerCase();
    if (normalizedClaimType.isNotEmpty) {
      return normalizedClaimType;
    }

    return title.toLowerCase().contains('devolu')
        ? 'refund_request'
        : 'complaint';
  }

  static String attachmentTypeFromPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.m4a') ||
        lower.endsWith('.aac') ||
        lower.endsWith('.mp3') ||
        lower.endsWith('.wav')) {
      return 'audio';
    }
    if (lower.endsWith('.mp4') ||
        lower.endsWith('.mov') ||
        lower.endsWith('.webm') ||
        lower.endsWith('.avi')) {
      return 'video';
    }
    return 'photo';
  }

  static String buildReason({
    required Map<String, bool> quickAnswers,
    required String observation,
  }) {
    final selectedQuickAnswers = quickAnswers.entries
        .where((entry) => entry.value)
        .map((entry) => entry.key)
        .toList();
    final normalizedObservation = observation.trim();

    final buffer = StringBuffer();
    if (selectedQuickAnswers.isNotEmpty) {
      buffer.writeln('Respostas rápidas:');
      for (final item in selectedQuickAnswers) {
        buffer.writeln('- $item');
      }
    }
    if (normalizedObservation.isNotEmpty) {
      if (buffer.isNotEmpty) buffer.writeln();
      buffer.writeln('Observação do cliente:');
      buffer.write(normalizedObservation);
    }
    buffer.writeln();
    buffer.writeln();
    buffer.write(
      'Aviso exibido ao cliente: os dados e anexos foram enviados para análise e a resposta será enviada por e-mail em até 3 dias úteis.',
    );

    return buffer.toString().trim();
  }
}
