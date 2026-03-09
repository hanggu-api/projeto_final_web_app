import 'dart:io' show Platform;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart'; // For defaultTargetPlatform

class NavigationHelper {
  /// Abre a navegação nativa do dispositivo para coordenadas específicas
  static Future<bool> openNavigation({
    required double latitude,
    required double longitude,
    String? label,
  }) async {
    final lat = latitude.toString();
    final lon = longitude.toString();

    // Android: Intent direto para modo de navegação no app nativo do Google Maps
    final androidUri = Uri.parse('google.navigation:q=$lat,$lon&mode=d');

    // iOS: Apple Maps modo direção
    final iosUri = Uri.parse('http://maps.apple.com/?daddr=$lat,$lon&dirflg=d');

    // Google Maps Web/App como fallback garantido
    final googleFallbackUri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon&travelmode=driving',
    );

    try {
      if (!kIsWeb) {
        if (Platform.isAndroid) {
          if (await canLaunchUrl(androidUri)) {
            return await launchUrl(
              androidUri,
              mode: LaunchMode.externalApplication,
            );
          }
        } else if (Platform.isIOS) {
          if (await canLaunchUrl(iosUri)) {
            return await launchUrl(
              iosUri,
              mode: LaunchMode.externalApplication,
            );
          }
        }
      }
      // Se não for Mobile Nativo ou o App Nativo não estiver instalado, usa Fallback Web
      return await launchUrl(
        googleFallbackUri,
        mode: LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Erro ao abrir mapas nativos: $e');
      // Tentativa final via web
      return await launchUrl(
        googleFallbackUri,
        mode: LaunchMode.externalApplication,
      );
    }
  }

  /// Abre navegação com endereço textual (busca)
  static Future<bool> openNavigationWithAddress({
    required String address,
  }) async {
    final encodedAddress = Uri.encodeComponent(address);
    final Uri uri;

    if (!kIsWeb && Platform.isAndroid) {
      uri = Uri.parse('geo:0,0?q=$encodedAddress');
    } else if (!kIsWeb && Platform.isIOS) {
      uri = Uri.parse('http://maps.apple.com/?q=$encodedAddress');
    } else {
      uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$encodedAddress',
      );
    }

    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      debugPrint('Erro ao abrir busca por endereço: $e');
      return false;
    }
  }
}
