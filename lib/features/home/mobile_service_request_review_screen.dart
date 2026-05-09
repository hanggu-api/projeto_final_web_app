import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/home/backend_home_api.dart';
import '../../core/config/supabase_config.dart';
import '../../core/maps/app_tile_layer.dart';
import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class MobileServiceRequestReviewScreen extends StatefulWidget {
  final Map<String, dynamic> suggestion;

  const MobileServiceRequestReviewScreen({super.key, required this.suggestion});

  @override
  State<MobileServiceRequestReviewScreen> createState() =>
      _MobileServiceRequestReviewScreenState();
}

class _MobileServiceRequestReviewScreenState
    extends State<MobileServiceRequestReviewScreen> {
  final ApiService _api = ApiService();
  final BackendHomeApi _backendHomeApi = const BackendHomeApi();
  final TextEditingController _addressController = TextEditingController();
  final FocusNode _addressFocusNode = FocusNode();
  final MapController _mapController = MapController();

  double? _latitude;
  double? _longitude;
  String? _address;
  bool _loadingLocation = true;
  bool _locationError = false;
  bool _creating = false;
  bool _mapExpanded = false;
  Timer? _geoDebounce;
  Map<String, dynamic>? _restServiceData;

  Map<String, dynamic> get _seedServiceData =>
      widget.suggestion['service'] is Map<String, dynamic>
      ? Map<String, dynamic>.from(
          widget.suggestion['service'] as Map<String, dynamic>,
        )
      : Map<String, dynamic>.from(widget.suggestion);

  Map<String, dynamic> get _serviceData => _restServiceData ?? _seedServiceData;

  String get _taskName =>
      (_serviceData['task_name'] ?? _serviceData['name'] ?? 'Servico movel')
          .toString();

  String get _professionName =>
      (_serviceData['profession_name'] ?? 'Prestador').toString();

  double get _price =>
      double.tryParse(
        '${_serviceData['unit_price'] ?? _serviceData['price'] ?? 0}',
      ) ??
      0.0;

  double get _upfrontAmount =>
      _price > 0 ? double.parse((_price * 0.30).toStringAsFixed(2)) : 0.0;

  double get _remainingAmount => _price > 0
      ? double.parse((_price - _upfrontAmount).toStringAsFixed(2))
      : 0.0;

  String _addressOptionLabel(Map<String, dynamic> option) {
    final address = option['address'];
    final poi = option['poi'];
    final candidates = <Object?>[
      option['display_name'],
      option['place_name'],
      option['freeformAddress'],
      if (address is Map) address['freeformAddress'],
      if (poi is Map) poi['name'],
    ];

    if (address is Map) {
      final street = (address['streetName'] ?? '').toString().trim();
      final number = (address['streetNumber'] ?? '').toString().trim();
      final city = (address['municipality'] ?? '').toString().trim();
      final state = (address['countrySubdivision'] ?? '').toString().trim();
      final composed = [
        [street, number].where((part) => part.isNotEmpty).join(' '),
        city,
        state,
      ].where((part) => part.isNotEmpty).join(', ');
      candidates.add(composed);
    }

    for (final candidate in candidates) {
      final value = candidate?.toString().trim() ?? '';
      if (value.isNotEmpty) return value;
    }
    return '';
  }

  double? _addressOptionLat(Map<String, dynamic> option) {
    final position = option['position'];
    final value = option['lat'] ?? (position is Map ? position['lat'] : null);
    return double.tryParse(value?.toString() ?? '');
  }

  double? _addressOptionLon(Map<String, dynamic> option) {
    final position = option['position'];
    final value =
        option['lon'] ??
        option['lng'] ??
        (position is Map ? position['lon'] ?? position['lng'] : null);
    return double.tryParse(value?.toString() ?? '');
  }

  List<Map<String, dynamic>> _normalizeAddressOptions(List<dynamic> results) {
    final normalized = <Map<String, dynamic>>[];
    final seen = <String>{};

    for (final item in results) {
      if (item is! Map) continue;
      final option = Map<String, dynamic>.from(item);
      final label = _addressOptionLabel(option);
      final lat = _addressOptionLat(option);
      final lon = _addressOptionLon(option);
      if (label.isEmpty || lat == null || lon == null) continue;

      final key = '$label|${lat.toStringAsFixed(5)}|${lon.toStringAsFixed(5)}';
      if (!seen.add(key)) continue;
      normalized.add({
        ...option,
        'display_name': label,
        'lat': lat,
        'lon': lon,
      });
      if (normalized.length >= 6) break;
    }

    return normalized;
  }

  @override
  void initState() {
    super.initState();
    unawaited(_hydrateServiceDataFromRest());
    _bootstrapLocation();
  }

  Future<void> _hydrateServiceDataFromRest() async {
    try {
      final snapshot = await _backendHomeApi.fetchClientHome();
      final services = List<Map<String, dynamic>>.from(
        snapshot?.services ?? [],
      );
      if (services.isEmpty) return;

      final seed = _seedServiceData;
      final seedTaskId = int.tryParse('${seed['task_id'] ?? seed['id'] ?? ''}');
      final seedTaskName = (seed['task_name'] ?? seed['name'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      Map<String, dynamic>? matched;
      if (seedTaskId != null) {
        for (final row in services) {
          final taskId = int.tryParse('${row['task_id'] ?? row['id'] ?? ''}');
          if (taskId == seedTaskId) {
            matched = row;
            break;
          }
        }
      }
      matched ??= services.cast<Map<String, dynamic>?>().firstWhere(
        (row) =>
            ((row?['task_name'] ?? row?['name'] ?? '')
                    .toString()
                    .trim()
                    .toLowerCase() ==
                seedTaskName) &&
            seedTaskName.isNotEmpty,
        orElse: () => null,
      );

      if (!mounted || matched == null) return;
      setState(() => _restServiceData = Map<String, dynamic>.from(matched!));
    } catch (_) {
      // Mantém seed atual caso snapshot backend não esteja disponível.
    }
  }

  @override
  void dispose() {
    _geoDebounce?.cancel();
    _addressController.dispose();
    _addressFocusNode.dispose();
    super.dispose();
  }

  Future<void> _bootstrapLocation() async {
    setState(() {
      _loadingLocation = true;
      _locationError = false;
    });
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        await Geolocator.requestPermission();
      }
      final pos = await Geolocator.getCurrentPosition();
      _latitude = pos.latitude;
      _longitude = pos.longitude;
      await _reverseGeocode(pos.latitude, pos.longitude, animateMap: false);
    } catch (_) {
      _locationError = true;
    } finally {
      if (mounted) {
        setState(() => _loadingLocation = false);
      }
    }
  }

  Future<void> _reverseGeocode(
    double lat,
    double lon, {
    bool animateMap = true,
  }) async {
    try {
      final res = await _api.reverseGeocode(lat, lon);
      if (!mounted) return;
      final displayName = (res['display_name'] ?? res['address'] ?? '')
          .toString()
          .trim();
      setState(() {
        _latitude = lat;
        _longitude = lon;
        _address = displayName.isEmpty ? _address : displayName;
        if (displayName.isNotEmpty) {
          _addressController.text = displayName;
        }
      });
      if (animateMap) {
        _mapController.move(LatLng(lat, lon), _mapController.camera.zoom);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _latitude = lat;
        _longitude = lon;
      });
    }
  }

  Future<void> _createServiceAndOpenPayment() async {
    if (_creating) return;
    if (_latitude == null ||
        _longitude == null ||
        (_addressController.text.trim().isEmpty && (_address ?? '').isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Confirme o endereco do servico antes de continuar.'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    setState(() => _creating = true);
    try {
      await _api.loadToken();
      final categoryId =
          int.tryParse('${_serviceData['category_id'] ?? 1}') ?? 1;
      final professionId = int.tryParse(
        '${_serviceData['profession_id'] ?? ''}',
      );
      final taskId = int.tryParse(
        '${_serviceData['task_id'] ?? _serviceData['id'] ?? ''}',
      );
      final estimatedPrice = _price > 0 ? _price : 80.0;
      final upfrontAmount = double.parse(
        (estimatedPrice * 0.30).toStringAsFixed(2),
      );
      final addressSafe = _addressController.text.trim().isNotEmpty
          ? _addressController.text.trim()
          : (_address ?? 'Endereco a definir');

      final blockingDispute = await _api.getBlockingDisputeForCurrentClient();
      if (blockingDispute != null) {
        final blockedServiceId = (blockingDispute['service_id'] ?? '')
            .toString();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Voce tem um servico sob contestacao. Consulte os detalhes antes de contratar outro servico.',
            ),
            backgroundColor: Colors.orange.shade700,
            action: blockedServiceId.isEmpty
                ? null
                : SnackBarAction(
                    label: 'Ver detalhes',
                    textColor: Colors.white,
                    onPressed: () =>
                        context.go('/service-tracking/$blockedServiceId'),
                  ),
          ),
        );
        return;
      }

      final created = await _api.createService(
        categoryId: categoryId,
        description: _taskName,
        latitude: _latitude!,
        longitude: _longitude!,
        address: addressSafe,
        priceEstimated: estimatedPrice,
        priceUpfront: upfrontAmount,
        profession: _professionName,
        professionId: professionId,
        locationType: 'client',
        providerId: null,
        taskId: taskId,
      );

      final serviceId = (created['serviceId'] ?? '').toString();
      if (serviceId.isEmpty) {
        throw Exception('Servico criado sem ID valido');
      }

      if (!mounted) return;
      context.go('/service-tracking/$serviceId');
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao criar servico movel: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _creating = false);
      }
    }
  }

  Widget _buildFlowStep({
    required IconData icon,
    required String text,
    Color iconBgColor = Colors.white,
    Color? iconColor,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 26,
          height: 26,
          decoration: BoxDecoration(
            color: iconBgColor,
            borderRadius: BorderRadius.circular(99),
          ),
          child: Icon(icon, size: 15, color: iconColor ?? AppTheme.primaryBlue),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              height: 1.45,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStickyAddressSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF0B3),
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.06)),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Onde o servico vai acontecer?',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Text(
            'Confirme seu endereco atual ou busque outro local. O campo fica fixo no topo para facilitar o ajuste antes do pagamento.',
            style: TextStyle(
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 14),
          RawAutocomplete<Map<String, dynamic>>(
            textEditingController: _addressController,
            focusNode: _addressFocusNode,
            optionsBuilder: (TextEditingValue text) async {
              if (text.text.length < 3) return const [];
              try {
                final results = await _api.searchAddress(
                  text.text,
                  lat: _latitude,
                  lon: _longitude,
                );
                return _normalizeAddressOptions(results);
              } catch (_) {
                return const [];
              }
            },
            displayStringForOption: (option) => _addressOptionLabel(option),
            onSelected: (option) {
              final lat = _addressOptionLat(option);
              final lon = _addressOptionLon(option);
              if (lat == null || lon == null) return;
              final label = _addressOptionLabel(option);
              setState(() {
                _latitude = lat;
                _longitude = lon;
                _address = label;
                _addressController.text = _address ?? '';
              });
              _mapController.move(LatLng(lat, lon), 18);
              FocusScope.of(context).unfocus();
            },
            fieldViewBuilder:
                (context, controller, focusNode, onEditingComplete) {
                  return TextField(
                    controller: controller,
                    focusNode: focusNode,
                    onEditingComplete: onEditingComplete,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      prefixIcon: const Padding(
                        padding: EdgeInsets.only(left: 6),
                        child: Icon(LucideIcons.mapPin, size: 22),
                      ),
                      prefixIconConstraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                      hintText: 'Digite ou busque outro endereco',
                      hintStyle: TextStyle(
                        color: Colors.grey.shade500,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                      suffixIcon: Container(
                        margin: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.black.withValues(alpha: 0.08),
                          ),
                        ),
                        child: IconButton(
                          onPressed: _bootstrapLocation,
                          icon: const Icon(Icons.my_location),
                        ),
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: AppTheme.primaryBlue.withValues(alpha: 0.18),
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(18),
                        borderSide: BorderSide(
                          color: AppTheme.primaryBlue,
                          width: 1.6,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 18,
                      ),
                    ),
                  );
                },
            optionsViewBuilder: (context, onSelected, options) {
              if (options.isEmpty) return const SizedBox.shrink();
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 8,
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  child: SizedBox(
                    width: MediaQuery.of(context).size.width - 32,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 260),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: options.length,
                        itemBuilder: (BuildContext context, int index) {
                          final option = options.elementAt(index);
                          final label = _addressOptionLabel(option);
                          return ListTile(
                            leading: const Icon(
                              Icons.location_on,
                              size: 20,
                              color: Colors.grey,
                            ),
                            title: Text(
                              label,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: AppTheme.textDark,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            onTap: () => onSelected(option),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 10),
          if ((_addressController.text.trim().isNotEmpty ||
                  (_address ?? '').trim().isNotEmpty) &&
              !_loadingLocation)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
              ),
              child: Text(
                _addressController.text.trim().isNotEmpty
                    ? _addressController.text.trim()
                    : (_address ?? ''),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Confirmar servico')),
      body: SafeArea(
        child: Column(
          children: [
            _buildStickyAddressSection(),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF7F8FA),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _taskName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _professionName,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        if (_price > 0) ...[
                          const SizedBox(height: 10),
                          Text(
                            'R\$ ${_price.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: AppTheme.primaryBlue,
                              fontWeight: FontWeight.w900,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _creating
                          ? null
                          : _createServiceAndOpenPayment,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: _creating
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Confirmar serviço e pagar sinal Pix',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEFF6FF),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFBFDBFE)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Como funciona',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 10),
                        _buildFlowStep(
                          icon: Icons.search_rounded,
                          text:
                              '1. Buscamos um prestador parceiro disponivel para voce.',
                          iconBgColor: const Color(0xFFE0EFFF),
                          iconColor: const Color(0xFF1565C0),
                        ),
                        const SizedBox(height: 10),
                        _buildFlowStep(
                          icon: Icons.home_repair_service_rounded,
                          text:
                              '2. O prestador vai ate o endereco confirmado abaixo.',
                          iconBgColor: const Color(0xFFE0EFFF),
                          iconColor: const Color(0xFF1565C0),
                        ),
                        const SizedBox(height: 10),
                        _buildFlowStep(
                          icon: Icons.payments_outlined,
                          text: _price > 0
                              ? '3. Voce paga 30% de sinal agora: R\$ ${_upfrontAmount.toStringAsFixed(2)}.'
                              : '3. Voce paga 30% de sinal para confirmar o servico.',
                          iconBgColor: const Color(0xFFFFF3CD),
                          iconColor: const Color(0xFFB26A00),
                        ),
                        const SizedBox(height: 10),
                        _buildFlowStep(
                          icon: Icons.qr_code_2_rounded,
                          text: _price > 0
                              ? '4. Quando o prestador chegar, voce paga os 70% restantes: R\$ ${_remainingAmount.toStringAsFixed(2)}.'
                              : '4. Quando o prestador chegar, voce paga os 70% restantes.',
                          iconBgColor: const Color(0xFFE8F5E9),
                          iconColor: const Color(0xFF1B5E20),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: Colors.black.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Column(
                      children: [
                        InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: () =>
                              setState(() => _mapExpanded = !_mapExpanded),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            child: Row(
                              children: [
                                const Icon(LucideIcons.map, size: 18),
                                const SizedBox(width: 8),
                                const Expanded(
                                  child: Text(
                                    'Ver no mapa',
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                Icon(
                                  _mapExpanded
                                      ? LucideIcons.chevronUp
                                      : LucideIcons.chevronDown,
                                  size: 18,
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_mapExpanded)
                          SizedBox(
                            height: 280,
                            child: ClipRRect(
                              borderRadius: const BorderRadius.vertical(
                                bottom: Radius.circular(14),
                              ),
                              child: Stack(
                                children: [
                                  if (_loadingLocation)
                                    const Center(
                                      child: CircularProgressIndicator(),
                                    )
                                  else if (_locationError ||
                                      _latitude == null ||
                                      _longitude == null)
                                    Center(
                                      child: Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            LucideIcons.mapPinOff,
                                            size: 42,
                                            color: Colors.redAccent,
                                          ),
                                          const SizedBox(height: 12),
                                          const Text(
                                            'Nao foi possivel carregar sua localizacao.',
                                            textAlign: TextAlign.center,
                                          ),
                                          const SizedBox(height: 12),
                                          ElevatedButton.icon(
                                            onPressed: _bootstrapLocation,
                                            icon: const Icon(
                                              LucideIcons.refreshCw,
                                              size: 16,
                                            ),
                                            label: const Text(
                                              'Tentar novamente',
                                            ),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    FlutterMap(
                                      mapController: _mapController,
                                      options: MapOptions(
                                        initialCenter: LatLng(
                                          _latitude!,
                                          _longitude!,
                                        ),
                                        initialZoom: 16.5,
                                        onPositionChanged: (pos, hasGesture) {
                                          if (!hasGesture) return;
                                          _geoDebounce?.cancel();
                                          _geoDebounce = Timer(
                                            const Duration(milliseconds: 800),
                                            () {
                                              _reverseGeocode(
                                                pos.center.latitude,
                                                pos.center.longitude,
                                                animateMap: false,
                                              );
                                            },
                                          );
                                        },
                                      ),
                                      children: [
                                        AppTileLayer.standard(
                                          mapboxToken:
                                              SupabaseConfig.mapboxToken,
                                        ),
                                      ],
                                    ),
                                  const Center(
                                    child: Padding(
                                      padding: EdgeInsets.only(bottom: 40),
                                      child: Icon(
                                        Icons.location_on,
                                        color: Colors.redAccent,
                                        size: 50,
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    right: 16,
                                    top: 16,
                                    child: Column(
                                      children: [
                                        FloatingActionButton.small(
                                          heroTag: 'review_zoom_in',
                                          onPressed: () {
                                            final zoom =
                                                _mapController.camera.zoom + 1;
                                            _mapController.move(
                                              _mapController.camera.center,
                                              zoom,
                                            );
                                          },
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          child: const Icon(LucideIcons.plus),
                                        ),
                                        const SizedBox(height: 8),
                                        FloatingActionButton.small(
                                          heroTag: 'review_zoom_out',
                                          onPressed: () {
                                            final zoom =
                                                _mapController.camera.zoom - 1;
                                            _mapController.move(
                                              _mapController.camera.center,
                                              zoom,
                                            );
                                          },
                                          backgroundColor: Colors.white,
                                          foregroundColor: Colors.black,
                                          child: const Icon(LucideIcons.minus),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
