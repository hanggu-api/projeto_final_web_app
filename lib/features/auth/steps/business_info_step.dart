import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/input_formatters.dart';

class BusinessInfoStep extends StatefulWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController addressController;
  final TextEditingController businessNameController;
  final TextEditingController nameController;
  final TextEditingController docController;
  final TextEditingController phoneController;
  final TextEditingController emailController;
  final TextEditingController passwordController;
  final Function(double lat, double lng)? onLocationChanged;

  const BusinessInfoStep({
    super.key,
    required this.formKey,
    required this.addressController,
    required this.businessNameController,
    required this.nameController,
    required this.docController,
    required this.phoneController,
    required this.emailController,
    required this.passwordController,
    this.onLocationChanged,
  });

  @override
  State<BusinessInfoStep> createState() => _BusinessInfoStepState();
}

class _BusinessInfoStepState extends State<BusinessInfoStep> {
  final MapController _mapController = MapController();
  LatLng _currentCenter = const LatLng(-5.5265, -47.4761); // Imperatriz Default
  bool _locating = false;

  @override
  void initState() {
    super.initState();
    _locateUser();
  }

  Future<void> _locateUser() async {
    setState(() => _locating = true);
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return;
      }

      Position position = await Geolocator.getCurrentPosition();
      final latLng = LatLng(position.latitude, position.longitude);

      setState(() {
        _currentCenter = latLng;
      });
      _mapController.move(latLng, 15);
      widget.onLocationChanged?.call(position.latitude, position.longitude);
    } catch (e) {
      debugPrint('Error locating user: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Form(
        key: widget.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Localização e Dados',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // MAP SECTION
            SizedBox(
              height: 200,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  children: [
                    FlutterMap(
                      mapController: _mapController,
                      options: MapOptions(
                        initialCenter: _currentCenter,
                        initialZoom: 15.0,
                        onPositionChanged: (pos, hasGesture) {
                          if (hasGesture) {
                            widget.onLocationChanged?.call(
                              pos.center.latitude,
                              pos.center.longitude,
                            );
                          }
                        },
                      ),
                      children: [
                        TileLayer(
                          urlTemplate:
                              'https://api.mapbox.com/styles/v1/mapbox/streets-v12/tiles/512/{z}/{x}/{y}@2x?access_token=${dotenv.env['MAPBOX_TOKEN'] ?? ''}',
                          userAgentPackageName: 'com.play101.app',
                          tileDimension: 512,
                          zoomOffset: -1,
                          maxZoom: 22,
                        ),
                        const MarkerLayer(
                          markers: [
                            // Center marker is usually static in UI, but here we can just show one at center
                          ],
                        ),
                      ],
                    ),
                    const Center(
                      child: Icon(
                        Icons.location_on,
                        color: Colors.red,
                        size: 40,
                      ),
                    ),
                    Positioned(
                      bottom: 8,
                      right: 8,
                      child: FloatingActionButton.small(
                        onPressed: _locateUser,
                        child: _locating
                            ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.my_location),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Ajuste o mapa para a localização exata do estabelecimento',
              style: TextStyle(fontSize: 12, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // FIELDS
            TextFormField(
              controller: widget.addressController,
              decoration: AppTheme.inputDecoration(
                'Endereço Completo',
                Icons.map,
              ),
              validator: (v) =>
                  v?.isEmpty == true ? 'Informe o endereço' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.businessNameController,
              decoration: AppTheme.inputDecoration(
                'Nome do Local (Barbearia)',
                Icons.store,
              ),
              validator: (v) =>
                  v?.isEmpty == true ? 'Informe o nome do local' : null,
            ),
            const SizedBox(height: 16),

            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: widget.docController,
                    decoration: AppTheme.inputDecoration(
                      'CPF ou CNPJ',
                      Icons.badge,
                    ),
                    keyboardType: TextInputType.number,
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      CpfCnpjInputFormatter(),
                    ],
                    validator: (v) {
                      if (v?.isEmpty == true) return 'Obrigatório';
                      final digits = v!.replaceAll(RegExp(r'\D'), '');
                      if (digits.length != 11 && digits.length != 14) {
                        return 'Inválido';
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.phoneController,
              decoration: AppTheme.inputDecoration(
                'Telefone / WhatsApp',
                Icons.phone,
              ),
              keyboardType: TextInputType.phone,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                PhoneInputFormatter(),
              ],
              validator: (v) {
                if (v?.isEmpty == true) return 'Obrigatório';
                final digits = v!.replaceAll(RegExp(r'\D'), '');
                if (digits.length < 10) return 'Inválido';
                return null;
              },
            ),
            const SizedBox(height: 24),

            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Dados de Acesso',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.nameController,
              decoration: AppTheme.inputDecoration(
                'Nome do Responsável',
                Icons.person,
              ),
              validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.emailController,
              decoration: AppTheme.inputDecoration('E-mail', Icons.email),
              keyboardType: TextInputType.emailAddress,
              validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
            ),
            const SizedBox(height: 16),

            TextFormField(
              controller: widget.passwordController,
              decoration: AppTheme.inputDecoration('Senha', Icons.lock),
              obscureText: true,
              validator: (v) =>
                  (v?.length ?? 0) < 6 ? 'Mínimo 6 caracteres' : null,
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
