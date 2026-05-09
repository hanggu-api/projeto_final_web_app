enum TipoFluxo { fixed, mobile }

enum StatusAgendamento {
  pending,
  confirmed,
  processing,
  inProgress,
  completed,
  cancelled,
}

class AgendamentoModel {
  final String? id;
  final String clienteUid;
  final String? prestadorUid;
  final int? clienteUserId;
  final int? prestadorUserId;
  final TipoFluxo tipoFluxo;
  final StatusAgendamento status;
  final DateTime? dataAgendada;
  final int? duracaoEstimadaMinutos;
  final double latitude;
  final double longitude;
  final double? clientLatitude;
  final double? clientLongitude;
  final String? enderecoCompleto;
  final int? tarefaId;
  final double precoTotal;
  final double valorEntrada;
  final List<String> imageKeys;
  final String? videoKey;
  final DateTime? clientDepartingAt;
  final DateTime? arrivedAt;
  final String? legacyServiceRequestId;
  final DateTime? createdAt;

  AgendamentoModel({
    this.id,
    required this.clienteUid,
    this.prestadorUid,
    this.clienteUserId,
    this.prestadorUserId,
    required this.tipoFluxo,
    this.status = StatusAgendamento.pending,
    this.dataAgendada,
    this.duracaoEstimadaMinutos,
    required this.latitude,
    required this.longitude,
    this.clientLatitude,
    this.clientLongitude,
    this.enderecoCompleto,
    this.tarefaId,
    this.precoTotal = 0.0,
    this.valorEntrada = 0.0,
    this.imageKeys = const [],
    this.videoKey,
    this.clientDepartingAt,
    this.arrivedAt,
    this.legacyServiceRequestId,
    this.createdAt,
  });

  factory AgendamentoModel.fromMap(Map<String, dynamic> map) {
    // Tratamento de geolocalização (PostGIS format)
    double lat = 0.0;
    double lon = 0.0;
    if (map['localizacao_origem'] != null) {
      final geo = map['localizacao_origem'];
      if (geo is Map && geo['coordinates'] != null) {
        lon = (geo['coordinates'][0] as num).toDouble();
        lat = (geo['coordinates'][1] as num).toDouble();
      }
    }

    return AgendamentoModel(
      id: map['id'],
      clienteUid: map['cliente_uid'],
      prestadorUid: map['prestador_uid'],
      clienteUserId: map['cliente_user_id'],
      prestadorUserId: map['prestador_user_id'],
      tipoFluxo: _parseTipoFluxo(map['tipo_fluxo']),
      status: _parseStatus(map['status']),
      dataAgendada: map['data_agendada'] != null
          ? DateTime.parse(map['data_agendada'])
          : null,
      duracaoEstimadaMinutos: map['duracao_estimada_minutos'],
      latitude: lat,
      longitude: lon,
      clientLatitude: (map['client_latitude'] as num?)?.toDouble(),
      clientLongitude: (map['client_longitude'] as num?)?.toDouble(),
      enderecoCompleto: map['endereco_completo'],
      tarefaId: map['tarefa_id'],
      precoTotal: (map['preco_total'] as num?)?.toDouble() ?? 0.0,
      valorEntrada: (map['valor_entrada'] as num?)?.toDouble() ?? 0.0,
      imageKeys: List<String>.from(map['image_keys'] ?? []),
      videoKey: map['video_key'],
      clientDepartingAt: map['client_departing_at'] != null
          ? DateTime.parse(map['client_departing_at'])
          : null,
      arrivedAt: map['arrived_at'] != null
          ? DateTime.parse(map['arrived_at'])
          : null,
      legacyServiceRequestId: map['legacy_service_request_id']?.toString(),
      createdAt: map['created_at'] != null
          ? DateTime.parse(map['created_at'])
          : null,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'cliente_uid': clienteUid,
      'prestador_uid': prestadorUid,
      'cliente_user_id': clienteUserId,
      'prestador_user_id': prestadorUserId,
      'tipo_fluxo': tipoFluxo == TipoFluxo.fixed ? 'FIXO' : 'MOVEL',
      'status': _statusToDb(status),
      'data_agendada': dataAgendada?.toIso8601String(),
      'duracao_estimada_minutos': duracaoEstimadaMinutos,
      'latitude': latitude,
      'longitude': longitude,
      'client_latitude': clientLatitude,
      'client_longitude': clientLongitude,
      'localizacao_origem':
          'POINT($longitude $latitude)', // Formato WKT para PostGIS
      'endereco_completo': enderecoCompleto,
      'tarefa_id': tarefaId,
      'preco_total': precoTotal,
      'valor_entrada': valorEntrada,
      'image_keys': imageKeys,
      'video_key': videoKey,
      'client_departing_at': clientDepartingAt?.toIso8601String(),
      'arrived_at': arrivedAt?.toIso8601String(),
      'legacy_service_request_id': legacyServiceRequestId,
    };
  }

  static String _statusToDb(StatusAgendamento status) {
    switch (status) {
      case StatusAgendamento.pending:
        return 'PENDENTE';
      case StatusAgendamento.confirmed:
        return 'CONFIRMADO';
      case StatusAgendamento.processing:
        return 'EM_DESLOCAMENTO';
      case StatusAgendamento.inProgress:
        return 'EM_EXECUCAO';
      case StatusAgendamento.completed:
        return 'CONCLUIDO';
      case StatusAgendamento.cancelled:
        return 'CANCELADO';
    }
  }

  static TipoFluxo _parseTipoFluxo(String? val) {
    if (val == 'FIXO') return TipoFluxo.fixed;
    if (val == 'MOVEL') return TipoFluxo.mobile;
    return TipoFluxo.mobile;
  }

  static StatusAgendamento _parseStatus(String? val) {
    switch (val) {
      case 'PENDENTE':
        return StatusAgendamento.pending;
      case 'CONFIRMADO':
        return StatusAgendamento.confirmed;
      case 'EM_DESLOCAMENTO':
        return StatusAgendamento.processing;
      case 'EM_EXECUCAO':
        return StatusAgendamento.inProgress;
      case 'CONCLUIDO':
        return StatusAgendamento.completed;
      case 'CANCELADO':
        return StatusAgendamento.cancelled;
      default:
        return StatusAgendamento.pending;
    }
  }
}
