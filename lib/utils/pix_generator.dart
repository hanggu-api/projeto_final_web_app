import 'dart:convert';

/// Utilitário para gerar payloads de PIX Estático no padrão EMV (BCB)
class PixGenerator {
  /// Gera o payload "Copia e Cola" para um PIX estático
  static String generatePayload({
    required String pixKey,
    required String merchantName,
    required String merchantCity,
    double? amount,
    String? txid,
  }) {
    // PADRÃO EMV PIX (BCB)
    // ID 00: Payload Format Indicator (01)
    String payload = _formatField('00', '01');

    // ID 26: Merchant Account Information - Point of Initiation Method
    // Dentro do ID 26:
    //   ID 00: GUI (br.gov.bcb.pix)
    //   ID 01: Chave PIX
    String merchantInfo =
        _formatField('00', 'br.gov.bcb.pix') + _formatField('01', pixKey);
    payload += _formatField('26', merchantInfo);

    // ID 52: Merchant Category Code (0000)
    payload += _formatField('52', '0000');

    // ID 53: Transaction Currency (986 - BRL)
    payload += _formatField('53', '986');

    // ID 54: Transaction Amount (Opcional)
    if (amount != null && amount > 0) {
      payload += _formatField('54', amount.toStringAsFixed(2));
    }

    // ID 58: Country Code (BR)
    payload += _formatField('58', 'BR');

    // ID 59: Merchant Name
    payload += _formatField('59', _sanitize(merchantName));

    // ID 60: Merchant City
    payload += _formatField('60', _sanitize(merchantCity));

    // ID 62: Additional Data Field Template
    // Dentro do ID 62:
    //   ID 05: Reference Label (TXID) - Se nulo, usar ***
    String additionalData = _formatField('05', txid ?? '***');
    payload += _formatField('62', additionalData);

    // ID 63: CRC16 (Calculado no final)
    payload += '6304';
    payload += _calculateCRC16(payload);

    return payload;
  }

  static String _formatField(String id, String value) {
    String length = value.length.toString().padLeft(2, '0');
    return '$id$length$value';
  }

  static String _sanitize(String text) {
    // Remove acentos e caracteres especiais para compatibilidade EMV
    var decoded = utf8.encode(text);
    // Para simplificar, vamos apenas remover caracteres não ASCII básicos
    return text.replaceAll(RegExp(r'[^\w\s]'), '').toUpperCase();
  }

  static String _calculateCRC16(String payload) {
    int crc = 0xFFFF;
    int polynomial = 0x1021;

    List<int> bytes = utf8.encode(payload);

    for (int b in bytes) {
      for (int i = 0; i < 8; i++) {
        bool bit = ((b >> (7 - i) & 1) == 1);
        bool c15 = ((crc >> 15 & 1) == 1);
        crc <<= 1;
        if (c15 ^ bit) crc ^= polynomial;
      }
    }

    crc &= 0xFFFF;
    return crc.toRadixString(16).toUpperCase().padLeft(4, '0');
  }
}
