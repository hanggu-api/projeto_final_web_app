import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

class MapControls extends StatelessWidget {
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onRecenter;
  final bool isTracking;

  const MapControls({
    super.key,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onRecenter,
    required this.isTracking,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.4,
      child: Column(
        children: [
          _buildControlButton(
            icon: LucideIcons.plus,
            onTap: onZoomIn,
          ),
          const SizedBox(height: 8),
          _buildControlButton(
            icon: LucideIcons.minus,
            onTap: onZoomOut,
          ),
          const SizedBox(height: 16),
          _buildControlButton(
            icon: LucideIcons.navigation,
            onTap: onRecenter,
            isActive: isTracking,
            activeColor: Colors.blueAccent,
          ),
        ],
      ),
    );
  }

  Widget _buildControlButton({
    required IconData icon,
    required VoidCallback onTap,
    bool isActive = false,
    Color? activeColor,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: isActive ? (activeColor ?? Colors.black) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          icon,
          color: isActive ? Colors.white : Colors.black87,
          size: 20,
        ),
      ),
    );
  }
}
