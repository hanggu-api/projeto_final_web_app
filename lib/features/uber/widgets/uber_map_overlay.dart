import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:google_fonts/google_fonts.dart';
import './snap_pin_marker.dart';
import './car_marker_widget.dart';

enum MapOverlayMode { request, tracking, driver }

class UberMapOverlay extends StatelessWidget {
  final List<LatLng> routePoints;
  final LatLng? pickupLocation;
  final LatLng? dropoffLocation;
  final LatLng? driverLocation;
  final double driverHeading;
  final bool isMoto;
  final MapOverlayMode mode;
  final String? dropoffInfo; // Ex: "1.6km | 4 min"
  final bool showPulse;
  final Color? pulseColor;
  final AnimationController? pulseController;
  final Color? routeColor;
  final Color? routeBorderColor;

  const UberMapOverlay({
    super.key,
    required this.routePoints,
    this.pickupLocation,
    this.dropoffLocation,
    this.driverLocation,
    this.driverHeading = 0,
    this.isMoto = false,
    this.mode = MapOverlayMode.request,
    this.dropoffInfo,
    this.showPulse = false,
    this.pulseColor,
    this.pulseController,
    this.routeColor,
    this.routeBorderColor,
  });

  @override
  Widget build(BuildContext context) {
    // 1. Processamento da Polilinha com Snap Perfeito
    List<LatLng> processedPoints = List.from(routePoints);

    // Lógica de Vanishing Route (Encolhimento) para o Motorista e Cliente
    if ((mode == MapOverlayMode.driver || mode == MapOverlayMode.tracking) &&
        driverLocation != null &&
        processedPoints.isNotEmpty) {
      // Encontra o ponto da rota mais próximo do motorista para truncar os pontos passados
      int closestIndex = 0;
      double minDistance = double.infinity;
      const Distance distanceCalculator = Distance();

      for (int i = 0; i < processedPoints.length; i++) {
        final d = distanceCalculator.as(
          LengthUnit.Meter,
          driverLocation!,
          processedPoints[i],
        );
        if (d < minDistance) {
          minDistance = d.toDouble();
          closestIndex = i;
        }
      }

      // Trunca a lista: remove tudo antes do ponto mais próximo e insere a posição atual do carro como início
      processedPoints = processedPoints.sublist(closestIndex);
      if (processedPoints.isEmpty || processedPoints.first != driverLocation) {
        processedPoints.insert(0, driverLocation!);
      }
    } else {
      // Snap normal para Request/Tracking
      if (processedPoints.isNotEmpty) {
        if (pickupLocation != null && processedPoints.first != pickupLocation) {
          processedPoints.insert(0, pickupLocation!);
        }
        if (dropoffLocation != null &&
            processedPoints.last != dropoffLocation) {
          processedPoints.add(dropoffLocation!);
        }
      }
    }

    // Cor da Rota: Verde para Motorista indo buscar ou Passageiro acompanhando
    final effectiveRouteColor =
        routeColor ??
        ((mode == MapOverlayMode.driver || mode == MapOverlayMode.tracking)
            ? Colors.green.withOpacity(0.8)
            : const Color(0xFF2196F3).withOpacity(0.9));

    final effectiveBorderColor =
        routeBorderColor ??
        ((mode == MapOverlayMode.driver || mode == MapOverlayMode.tracking)
            ? Colors.green.shade900
            : const Color(0xFF1976D2));

    return Stack(
      children: [
        // Camada de Rota
        if (processedPoints.length >= 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: processedPoints,
                strokeWidth: 5,
                strokeCap: StrokeCap.round,
                strokeJoin: StrokeJoin.round,
                color: effectiveRouteColor,
                borderColor: effectiveBorderColor,
                borderStrokeWidth: 2.0,
              ),
            ],
          ),

        // Camada de Marcadores
        MarkerLayer(
          markers: [
            // Marcador de Embarque
            if (pickupLocation != null)
              Marker(
                point: pickupLocation!,
                width: 200,
                height: 100,
                alignment: Alignment.topCenter,
                child: _buildLabelMarker(
                  label: 'Origem',
                  color: const Color(0xFF2196F3),
                  isPickup: true,
                ),
              ),

            // Marcador de Destino
            if (dropoffLocation != null)
              Marker(
                point: dropoffLocation!,
                width: 200,
                height: 100,
                alignment: Alignment.topCenter,
                child: _buildLabelMarker(
                  label: 'Destino',
                  color: const Color(0xFFFF2D55),
                  info: dropoffInfo,
                  isPickup: false,
                ),
              ),

            // Marcador do Motorista
            if (driverLocation != null)
              Marker(
                point: driverLocation!,
                width: 60,
                height: 60,
                alignment: Alignment.center,
                child: PremiumDriverMarker(
                  heading: driverHeading,
                  isMoto: isMoto,
                  size: 44,
                  showPulse: showPulse,
                  pulseController: pulseController,
                  pulseColor: pulseColor,
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildLabelMarker({
    required String label,
    required Color color,
    String? info,
    required bool isPickup,
  }) {
    // Definimos uma cor única Uber (Preto ou cor principal)
    final Color markerColor = isPickup
        ? const Color(0xFF2196F3)
        : const Color(0xFFFF2D55);

    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: markerColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: kIsWeb
                ? []
                : [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                label,
                style: GoogleFonts.manrope(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (info != null) ...[
                Container(
                  width: 1,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  color: Colors.white.withOpacity(0.5),
                ),
                Text(
                  info,
                  style: GoogleFonts.manrope(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 2),
        SnapPinMarker(
          color: markerColor,
          size: 40,
          type: isPickup ? SnapMarkerType.pickup : SnapMarkerType.destination,
        ),
      ],
    );
  }
}
