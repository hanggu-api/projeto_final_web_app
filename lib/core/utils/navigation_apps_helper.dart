import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

class NavigationAppOption {
  final String id;
  final String label;
  final IconData icon;
  final Uri Function(double lat, double lon) uriBuilder;
  final Uri? availabilityUri;
  final bool isFallback;

  const NavigationAppOption({
    required this.id,
    required this.label,
    required this.icon,
    required this.uriBuilder,
    this.availabilityUri,
    this.isFallback = false,
  });
}

class NavigationSelectionResult {
  final NavigationAppOption option;
  final bool savePreference;

  const NavigationSelectionResult({
    required this.option,
    required this.savePreference,
  });
}

class NavigationAppsHelper {
  static const String preferenceKey = 'preferred_navigation_app';
  static bool get _isIos =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  static List<NavigationAppOption> get options => [
    NavigationAppOption(
      id: 'google_maps',
      label: 'Google Maps',
      icon: LucideIcons.map,
      uriBuilder: (lat, lon) {
        if (kIsWeb) {
          return Uri.parse(
            'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
          );
        }
        if (_isIos) {
          return Uri.parse(
            'comgooglemaps://?daddr=$lat,$lon&directionsmode=driving',
          );
        }
        return Uri.parse('google.navigation:q=$lat,$lon');
      },
      availabilityUri: kIsWeb
          ? null
          : (_isIos
                ? Uri.parse('comgooglemaps://')
                : Uri.parse('google.navigation:?q=0,0')),
    ),
    NavigationAppOption(
      id: 'waze',
      label: 'Waze',
      icon: LucideIcons.navigation,
      uriBuilder: (lat, lon) => Uri.parse('waze://?ll=$lat,$lon&navigate=yes'),
      availabilityUri: kIsWeb ? null : Uri.parse('waze://'),
    ),
    NavigationAppOption(
      id: 'apple_maps',
      label: 'Apple Maps',
      icon: LucideIcons.mapPin,
      uriBuilder: (lat, lon) => _isIos
          ? Uri.parse('maps://?daddr=$lat,$lon&dirflg=d')
          : Uri.parse('https://maps.apple.com/?daddr=$lat,$lon&dirflg=d'),
      availabilityUri: kIsWeb ? null : (_isIos ? Uri.parse('maps://') : null),
    ),
    NavigationAppOption(
      id: 'browser_maps',
      label: 'Navegador',
      icon: LucideIcons.globe,
      uriBuilder: (lat, lon) => Uri.parse(
        'https://www.google.com/maps/dir/?api=1&destination=$lat,$lon',
      ),
      isFallback: true,
    ),
  ];

  static Future<List<NavigationAppOption>> detectAvailableApps() async {
    final List<NavigationAppOption> available = [];

    for (final option in options) {
      if (option.isFallback || option.availabilityUri == null) continue;
      try {
        if (await canLaunchUrl(option.availabilityUri!)) {
          available.add(option);
        }
      } catch (_) {}
    }

    final fallback = options.firstWhere((option) => option.isFallback);
    if (available.isEmpty) {
      available.add(fallback);
    } else if (!available.any((option) => option.id == fallback.id)) {
      available.add(fallback);
    }

    return available;
  }

  static Future<String?> getPreferredAppId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(preferenceKey);
  }

  static Future<void> setPreferredAppId(String id) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(preferenceKey, id);
  }

  static Future<NavigationAppOption?> getPreferredAvailableApp() async {
    final preferredId = await getPreferredAppId();
    if (preferredId == null) return null;

    final availableApps = await detectAvailableApps();
    for (final option in availableApps) {
      if (option.id == preferredId) return option;
    }
    return null;
  }

  static Future<NavigationSelectionResult?> showNavigationAppPicker(
    BuildContext context, {
    String title = 'Escolher aplicativo de navegação',
    String actionLabel = 'Usar este aplicativo',
    bool allowSavePreference = true,
  }) async {
    final availableApps = await detectAvailableApps();
    final preferredId = await getPreferredAppId();
    if (!context.mounted) return null;

    return showModalBottomSheet<NavigationSelectionResult>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        NavigationAppOption selected = availableApps.firstWhere(
          (option) => option.id == preferredId,
          orElse: () => availableApps.first,
        );
        bool savePreference = allowSavePreference;

        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                ),
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 52,
                        height: 5,
                        decoration: BoxDecoration(
                          color: Colors.black12,
                          borderRadius: BorderRadius.circular(99),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Selecione o GPS que você quer usar neste dispositivo.',
                    ),
                    const SizedBox(height: 16),
                    ...availableApps.map((option) {
                      final isSelected = selected.id == option.id;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(18),
                          onTap: () => setModalState(() => selected = option),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFFFF4B8)
                                  : Colors.grey.shade50,
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFE0B400)
                                    : Colors.black12,
                                width: isSelected ? 1.6 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(option.icon),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    option.label,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  const Icon(Icons.check_circle, size: 20),
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                    if (allowSavePreference) ...[
                      const SizedBox(height: 8),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: savePreference,
                        onChanged: (value) =>
                            setModalState(() => savePreference = value),
                        title: const Text('Salvar como aplicativo padrão'),
                      ),
                    ],
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: () {
                          Navigator.of(sheetContext).pop(
                            NavigationSelectionResult(
                              option: selected,
                              savePreference: savePreference,
                            ),
                          );
                        },
                        child: Text(actionLabel),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static Future<bool> launchNavigation(
    NavigationAppOption option,
    double lat,
    double lon,
  ) async {
    final uri = option.uriBuilder(lat, lon);
    return launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  static Future<bool> openNavigation(
    BuildContext context, {
    required double lat,
    required double lon,
    bool forceChooser = false,
  }) async {
    try {
      NavigationAppOption? option;
      bool savePreference = false;

      if (!forceChooser) {
        option = await getPreferredAvailableApp();
      }

      if (option == null) {
        if (!context.mounted) return false;
        final result = await showNavigationAppPicker(
          context,
          actionLabel: 'Abrir com este GPS',
        );
        if (result == null) return false;
        option = result.option;
        savePreference = result.savePreference;
      }

      if (savePreference) {
        await setPreferredAppId(option.id);
      }

      return await launchNavigation(option, lat, lon);
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Erro ao abrir GPS: $e')));
      }
      return false;
    }
  }

  static Future<void> choosePreferredNavigationApp(BuildContext context) async {
    final result = await showNavigationAppPicker(
      context,
      actionLabel: 'Salvar preferência',
      allowSavePreference: true,
    );
    if (result == null) return;

    await setPreferredAppId(result.option.id);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${result.option.label} definido como GPS padrão'),
        ),
      );
    }
  }
}
