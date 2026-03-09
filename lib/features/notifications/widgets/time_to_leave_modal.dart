import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:audioplayers/audioplayers.dart';
import '../../../core/utils/navigation_helper.dart';

import '../../../core/theme/app_theme.dart';

class TimeToLeaveModal extends StatefulWidget {
  final Map<String, dynamic> data;

  const TimeToLeaveModal({super.key, required this.data});

  @override
  State<TimeToLeaveModal> createState() => _TimeToLeaveModalState();
}

class _TimeToLeaveModalState extends State<TimeToLeaveModal>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  final AudioPlayer _audioPlayer = AudioPlayer();

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this);
    _playAlarm();
  }

  Future<void> _playAlarm() async {
    // Loop alarm sound (ensure you have a sound file or use a package)
    // For now, assume a standard notification sound or use a bundled asset
    // await _audioPlayer.setSource(AssetSource('sounds/alarm.mp3'));
    // await _audioPlayer.setReleaseMode(ReleaseMode.loop);
    // await _audioPlayer.resume();
    // FALLBACK for now if no asset: just vibrate or log
    debugPrint('Pseudo-Alarm playing...');
  }

  @override
  void dispose() {
    _controller.dispose();
    _audioPlayer.stop();
    _audioPlayer.dispose();
    super.dispose();
  }

  void _stopAlarm() {
    _audioPlayer.stop();
  }

  void _openMaps() async {
    _stopAlarm();
    final lat = widget.data['lat'];
    final lng = widget.data['lng'];
    if (lat != null && lng != null) {
      await NavigationHelper.openNavigation(
        latitude: double.tryParse(lat.toString()) ?? 0,
        longitude: double.tryParse(lng.toString()) ?? 0,
      );
    }
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(
            color: AppTheme.textBrown.withValues(alpha: 0.2),
            width: 2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon Header
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.primaryYellow.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.directions_car,
                size: 48,
                color: AppTheme.textBrown,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'HORA DE SAIR!',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppTheme.textBrown,
                letterSpacing: 1.1,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              'Para garantir seu atendimento com 3 min de antecedência, saia agora.',
              style: GoogleFonts.outfit(
                fontSize: 15,
                color: Colors.black87,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),

            // Action Buttons
            Row(
              children: [
                // Iniciar Navegação (Primary Action)
                Expanded(
                  flex: 2,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _openMaps,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppTheme.primaryYellow,
                        foregroundColor: Colors.black,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.navigation, size: 18),
                          const SizedBox(width: 8),
                          Text(
                            'MAPS',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Cheguei ao local (Secondary Action)
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () {
                        _stopAlarm();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue.shade700,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: Text(
                        'CHEGUEI AO LOCAL',
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Tertiary Action
            TextButton(
              onPressed: () {
                _stopAlarm();
                Navigator.of(context).pop();
                // Aqui poderia abrir o chat com o prestador
              },
              child: Text(
                'Vou me atrasar (Avisar)',
                style: GoogleFonts.outfit(
                  color: Colors.black45,
                  fontSize: 13,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
