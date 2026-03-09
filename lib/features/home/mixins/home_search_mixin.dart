import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../home_state.dart';
import '../../../services/api_service.dart';
import '../../../services/remote_config_service.dart';
import '../../../services/theme_service.dart';

mixin HomeSearchMixin<T extends StatefulWidget> on State<T>, HomeStateMixin<T> {
  final ApiService _api = ApiService();
  final Map<String, List<dynamic>> _autocompleteCache = {};

  void onSearchChanged(String query, bool isPickup) {
    if (debouncer?.isActive ?? false) debouncer!.cancel();
    debouncer = Timer(const Duration(milliseconds: 600), () async {
      if (!isSearchExpanded &&
          !pickupFocus.hasFocus &&
          !destinationFocus.hasFocus) {
        return;
      }

      final trimmedQuery = query.trim();
      if (trimmedQuery.length < 3) {
        if (mounted) setState(() => searchResults = []);
        return;
      }

      if (_autocompleteCache.containsKey(trimmedQuery)) {
        if (mounted) {
          setState(() => searchResults = _autocompleteCache[trimmedQuery]!);
        }
        return;
      }

      if (mounted) setState(() => isSearching = true);

      try {
        final maxRadiusKm = RemoteConfigService.searchRadiusKm;
        final results = await _api.searchAddress(
          trimmedQuery,
          lat: currentPosition.latitude,
          lon: currentPosition.longitude,
          radiusKm: maxRadiusKm,
        );

        if (responseSuccess(results)) {
          final enrichedResults = await _enrichResults(results);
          if (mounted) {
            if (!isSearchExpanded &&
                !pickupFocus.hasFocus &&
                !destinationFocus.hasFocus) {
              setState(() => isSearching = false);
              return;
            }
            setState(() {
              searchResults = enrichedResults;
              _autocompleteCache[trimmedQuery] = enrichedResults;
            });
          }
        }
      } catch (e) {
        debugPrint('Erro na busca: $e');
        if (mounted) setState(() => searchResults = []);
      } finally {
        if (mounted) setState(() => isSearching = false);
      }
    });
  }

  bool responseSuccess(dynamic results) => results != null;

  Future<List<Map<String, dynamic>>> _enrichResults(List<dynamic> data) async {
    final rawResults = data.map<Map<String, dynamic>>((item) {
      return {
        'address': item['address'] ?? {},
        'poi': item['poi'],
        'lat': item['position']?['lat'],
        'lon': item['position']?['lon'],
        'dist': item['dist'],
      };
    }).toList();

    return Future.wait(
      rawResults.map((raw) async {
        final address = raw['address'];
        final poi = raw['poi'];
        String? bairro =
            address['municipalitySubdivision'] ??
            address['neighborhood'] ??
            address['subDivision'];

        if ((bairro == null || bairro.isEmpty) &&
            raw['lat'] != null &&
            raw['lon'] != null) {
          try {
            final reverseResp = await _api.reverseGeocode(
              raw['lat'],
              raw['lon'],
            );
            final revAddress = reverseResp['address'] as Map<String, dynamic>?;
            bairro =
                revAddress?['suburb'] ??
                revAddress?['neighbourhood'] ??
                revAddress?['city_district'];
          } catch (_) {}
        }

        String mainTitle = poi != null
            ? poi['name']
            : (address['streetName'] ?? "Endereço desconhecido");
        if (poi == null && address['freeformAddress'] != null) {
          mainTitle = address['freeformAddress'].split(',')[0];
        }

        List<String> parts = [];
        if (address['streetName'] != null) {
          String street = address['streetName'];
          if (address['streetNumber'] != null) {
            street += ", ${address['streetNumber']}";
          }
          parts.add(street);
        }
        if (bairro != null) parts.add(bairro);
        parts.add(address['municipality'] ?? 'Imperatriz');

        String subtitle = parts.isNotEmpty
            ? parts.join(' - ')
            : (address['freeformAddress'] ?? '');

        String categoryStr = '';
        if (poi != null) {
          categoryStr =
              '${(poi['categories'] as List?)?.join(' ') ?? ''} ${poi['classifications']?.toString() ?? ''}'
                  .toLowerCase();
        }

        return {
          'main_text': mainTitle,
          'secondary_text': subtitle,
          'is_poi': poi != null,
          'display_name': '$mainTitle - $subtitle',
          'lat': raw['lat'],
          'lon': raw['lon'],
          'dist': raw['dist'],
          'category': categoryStr,
          'street': address['streetName'],
          'number': address['streetNumber'],
          'neighborhood': bairro,
          'city': address['municipality'],
          'state': address['countrySubdivisionCode'],
          'poi_name': poi != null ? poi['name'] : null,
        };
      }),
    );
  }

  Future<void> selectSearchResult(dynamic result, bool isPickup) async {
    if (debouncer?.isActive ?? false) debouncer!.cancel();
    final display = result['display_name'] ?? result['address'] ?? '';
    final lat = double.tryParse(result['lat']?.toString() ?? '');
    final lon = double.tryParse(result['lon']?.toString() ?? '');

    if (lat != null && lon != null) {
      _api.registerAddressInRegistry(
        fullAddress: display,
        streetName: result['street'],
        streetNumber: result['number'],
        neighborhood: result['neighborhood'],
        city: result['city'],
        stateCode: result['state'],
        poiName: result['poi_name'],
        lat: lat,
        lon: lon,
        category: result['category'],
      );

      final targetPos = LatLng(lat, lon);
      setState(() {
        if (isPickup) {
          pickupLocation = targetPos;
          pickupController.text = display;
        } else {
          dropoffLocation = targetPos;
          destinationController.text = display;
          isSearchExpanded = false;
          isInTripMode = true;
          ThemeService().setNavBarVisible(false);

          if (pickupLocation == null) {
            pickupLocation = currentPosition;
            pickupController.text = 'Meu Local';
          }
        }
        searchResults = [];
        FocusScope.of(context).unfocus();

        if (pickupLocation != null && dropoffLocation != null) {
          routePolyline = [pickupLocation!, dropoffLocation!];
          final bounds = LatLngBounds(pickupLocation!, dropoffLocation!);
          mapController.fitCamera(
            CameraFit.bounds(
              bounds: bounds,
              padding: const EdgeInsets.only(
                top: 150,
                bottom: 540,
                left: 60,
                right: 60,
              ),
            ),
          );
        }
      });
    }
  }
}
