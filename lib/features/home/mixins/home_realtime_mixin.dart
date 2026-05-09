import 'package:flutter/material.dart';
import '../home_state.dart';

mixin HomeRealtimeMixin<T extends StatefulWidget>
    on State<T>, HomeStateMixin<T> {
  void listenToTripUpdates(
    String _, {
    required VoidCallback onRatingRequired,
    required VoidCallback onReset,
  }) {}

  void startWatchingDriverLocation(String _) {}

  void stopWatchingDriverLocation() {
    tripSubscription?.cancel();
    tripSubscription = null;
    driverLocationSubscription?.cancel();
    driverLocationSubscription = null;
    if (mounted) {
      setState(() {
        activeTrip = null;
        activeTripStatus = null;
        distanceToDriver = null;
        driverLatLng = null;
        arrivalPolyline = [];
      });
    }
  }
}
