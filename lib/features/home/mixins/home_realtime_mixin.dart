import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../home_state.dart';
import '../../../services/uber_service.dart';
import '../../../services/map_service.dart';

mixin HomeRealtimeMixin<T extends StatefulWidget> on State<T>, HomeStateMixin<T> {
  void listenToTripUpdates(String tripId, {required VoidCallback onRatingRequired, required VoidCallback onReset}) {
    tripSubscription?.cancel();
    tripSubscription = UberService().watchTrip(tripId).listen((trip) {
      if (mounted) {
        setState(() {
          if (activeTripStatus != trip['status'] && trip['status'] == 'arrived') {
            HapticFeedback.vibrate();
          }
          activeTrip = trip;
          activeTripStatus = trip['status'];
        });

        if (trip['status'] == 'accepted' || trip['status'] == 'arrived' || trip['status'] == 'in_progress') {
          startWatchingDriverLocation(tripId);
        } else {
          stopWatchingDriverLocation();
        }

        if (trip['status'] == 'completed') {
          tripSubscription?.cancel();
          tripSubscription = null;
          stopWatchingDriverLocation();
          onRatingRequired();
          onReset();
        } else if (trip['status'] == 'cancelled') {
          tripSubscription?.cancel();
          tripSubscription = null;
          stopWatchingDriverLocation();
          setState(() {
            activeTrip = null;
            activeTripStatus = null;
            distanceToDriver = null;
            driverLatLng = null;
          });
        }
      }
    });
  }

  void startWatchingDriverLocation(String tripId) {
    if (driverLocationSubscription != null) return;
    
    final driverId = activeTrip?['driver_id'];
    if (driverId == null) return;
    
    final int id = (driverId is String) ? (int.tryParse(driverId) ?? 0) : (driverId as num).toInt();
    if (id == 0) return;
    
    driverLocationSubscription = UberService().watchDriverLocation(id).listen((locations) {
      if (mounted && locations.isNotEmpty) {
        final loc = locations.first;
        final driverLat = loc['latitude'] as double;
        final driverLng = loc['longitude'] as double;
        final newDriverPos = LatLng(driverLat, driverLng);
        
        final pickupLat = activeTrip?['pickup_lat'] as double?;
        final pickupLng = activeTrip?['pickup_lon'] as double?;

        if (pickupLat != null && pickupLng != null) {
          final double distMoved = driverLatLng != null 
              ? Geolocator.distanceBetween(driverLatLng!.latitude, driverLatLng!.longitude, driverLat, driverLng)
              : 1000.0;
          
          if (distMoved > 30 || arrivalPolyline.isEmpty) {
            MapService().getRoute(newDriverPos, LatLng(pickupLat, pickupLng)).then((res) {
              if (mounted) {
                setState(() => arrivalPolyline = res['points'] as List<LatLng>);
              }
            });
          }
        }

        setState(() {
          driverLatLng = newDriverPos;
          if (pickupLat != null && pickupLng != null) {
            distanceToDriver = Geolocator.distanceBetween(
              driverLat, driverLng, pickupLat, pickupLng
            );
          }
        });
      }
    });
  }

  void stopWatchingDriverLocation() {
    driverLocationSubscription?.cancel();
    driverLocationSubscription = null;
    if (mounted) {
      setState(() {
        distanceToDriver = null;
        driverLatLng = null;
        arrivalPolyline = [];
      });
    }
  }
}
