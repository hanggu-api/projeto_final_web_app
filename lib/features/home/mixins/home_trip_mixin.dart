import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../home_state.dart';
import '../../../services/map_service.dart';
import '../../../services/uber_service.dart';
import '../../../services/theme_service.dart';

mixin HomeTripMixin<T extends StatefulWidget> on State<T>, HomeStateMixin<T> {
  Future<void> toggleTripMode() async {
    setState(() {
      isInTripMode = !isInTripMode;
      if (isInTripMode) {
        if (pickupLocation == null) {
          pickupLocation = currentPosition;
          if (pickupController.text.isEmpty) {
            pickupController.text = 'Meu Local';
          }
        }
      } else {
        resetTripFields();
      }
      ThemeService().setNavBarVisible(!isInTripMode);
    });
  }

  void resetTripFields() {
    fareEstimate = {};
    fareEstimatesByVehicle.clear();
    searchResults = [];
    destinationController.clear();
    dropoffLocation = null;
    routePolyline = [];
    routeDistance = null;
    routeDuration = null;
  }

  Future<void> calculateRouteAndFare() async {
    if (pickupLocation == null || dropoffLocation == null) return;

    setState(() => isRequestingTrip = true);
    try {
      final route = await MapService().getRoute(pickupLocation!, dropoffLocation!);

      if (mounted) {
        setState(() {
          routeDistance = '${route['distance'].toStringAsFixed(1)} km';
          routeDuration = '${route['duration'].toStringAsFixed(0)} min';
          routePolyline = List<LatLng>.from(route['points']);
        });
      }

      await calculateFare();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao traçar rota: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isRequestingTrip = false);
    }
  }

  Future<void> calculateFare() async {
    if (pickupLocation == null || dropoffLocation == null) return;

    setState(() {
      isRequestingTrip = true;
      fareEstimatesByVehicle.clear();
    });

    try {
      final List<Future<void>> fareFutures = vehicleTypesList.map((type) async {
        final typeId = type['id'] as int;
        try {
          final fare = await UberService().calculateFare(
            pickupLat: pickupLocation!.latitude,
            pickupLng: pickupLocation!.longitude,
            dropoffLat: dropoffLocation!.latitude,
            dropoffLng: dropoffLocation!.longitude,
            vehicleTypeId: typeId,
          );
          if (mounted) {
            setState(() {
              fareEstimatesByVehicle[typeId] = fare;
            });
          }
        } catch (e) {
          debugPrint('Error calculating fare for vehicle type $typeId: $e');
        }
      }).toList();

      await Future.wait(fareFutures);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao calcular tarifas: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isRequestingTrip = false);
    }
  }

  double extractFareValue(dynamic data) {
    if (data == null) return 0.0;
    if (data is num) return data.toDouble();
    if (data is Map) {
      final value = data['estimated'] ?? data['fare'] ?? data['total'] ?? data['price'] ?? data['amount'] ?? data['estimated_fare'] ?? 0;
      if (value is Map) return extractFareValue(value);
      return double.tryParse(value.toString()) ?? 0.0;
    }
    return 0.0;
  }

  Future<void> requestRide(Function(String) onTripRequested) async {
    if (pickupLocation == null || dropoffLocation == null) return;

    setState(() => isRequestingTrip = true);
    try {
      final trip = await UberService().requestTrip(
        pickupLat: pickupLocation!.latitude,
        pickupLng: pickupLocation!.longitude,
        pickupAddress: pickupController.text,
        dropoffLat: dropoffLocation!.latitude,
        dropoffLng: dropoffLocation!.longitude,
        dropoffAddress: destinationController.text,
        vehicleTypeId: selectedVehicleTypeId,
        paymentMethod: selectedPaymentMethod,
        fare: extractFareValue(fareEstimatesByVehicle[selectedVehicleTypeId]),
      );

      if (mounted) {
        final tripId = trip['trip_id'] ?? trip['id'];
        if (tripId != null) {
          setState(() {
            activeTrip = trip;
            activeTripStatus = 'searching';
            isRequestingTrip = false;
          });
          onTripRequested(tripId.toString());
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao solicitar viagem: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => isRequestingTrip = false);
    }
  }

  void resetHomeScreen() {
    if (mounted) {
      setState(() {
        isInTripMode = false;
        activeTrip = null;
        activeTripStatus = null;
        dropoffLocation = null;
        destinationController.clear();
        routePolyline = [];
        routeDistance = null;
        routeDuration = null;
        fareEstimate = {};
        fareEstimatesByVehicle.clear();
        isSearchExpanded = false;
        pickupLocation = currentPosition;
      });
    }
  }
}
