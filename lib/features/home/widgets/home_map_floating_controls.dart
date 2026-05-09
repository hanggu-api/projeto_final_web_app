import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

class HomeMapFloatingControls extends StatelessWidget {
  final double bottomOffset;
  final bool isMapAnimating;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onCenterLocation;

  const HomeMapFloatingControls({
    super.key,
    required this.bottomOffset,
    required this.isMapAnimating,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onCenterLocation,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: bottomOffset,
      right: 20,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: isMapAnimating ? 0.0 : 1.0,
        child: Column(
          children: [
            _HomeMapControlButton(icon: Icons.add, onTap: onZoomIn),
            const SizedBox(height: 8),
            _HomeMapControlButton(icon: Icons.remove, onTap: onZoomOut),
            const SizedBox(height: 12),
            _HomeMapLocationButton(onTap: onCenterLocation),
          ],
        ),
      ),
    );
  }
}

class _HomeMapControlButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _HomeMapControlButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 10)],
        ),
        child: Icon(icon, color: AppTheme.textDark),
      ),
    );
  }
}

class _HomeMapLocationButton extends StatelessWidget {
  final VoidCallback onTap;

  const _HomeMapLocationButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: AppTheme.primaryBlue.withOpacity(0.2),
              blurRadius: 20,
            ),
          ],
        ),
        child: Icon(Icons.my_location, color: AppTheme.primaryBlue),
      ),
    );
  }
}
