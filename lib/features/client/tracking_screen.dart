import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../core/theme/app_theme.dart';

class TrackingScreen extends StatelessWidget {
  const TrackingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Column(
        children: [
          // Map Area (Mock)
          Expanded(
            flex: 3,
            child: Container(
              color: Colors.blue[50],
              child: Stack(
                children: [
                  // Mock Map Background
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFFDBEAFE), Color(0xFFD1FAE5)], // Blue-100 to Green-100
                        ),
                      ),
                    ),
                  ),
                  // Route Line (simplified)
                  Center(
                    child: Container(
                      width: 200,
                      height: 200,
                      decoration: BoxDecoration(
                        border: Border.all(color: AppTheme.primaryPurple, width: 3),
                        borderRadius: BorderRadius.circular(100),
                      ),
                    ),
                  ),
                  // Client Marker
                  Positioned(
                    bottom: 150,
                    left: 100,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
                          ),
                          child: const Text('Você', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 4),
                        const Icon(Icons.location_on, color: Colors.blue, size: 32),
                      ],
                    ),
                  ),
                  // Provider Marker
                  Positioned(
                    top: 150,
                    right: 100,
                    child: Column(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppTheme.successGreen,
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black12)],
                          ),
                          child: const Text('850m', style: TextStyle(fontSize: 10, color: Colors.white, fontWeight: FontWeight.bold)),
                        ),
                        const SizedBox(height: 4),
                        const CircleAvatar(
                          radius: 16,
                          backgroundColor: AppTheme.primaryPurple,
                          child: Text('CS', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  
                  // Back Button
                  Positioned(
                    top: 40,
                    left: 20,
                    child: CircleAvatar(
                      backgroundColor: Colors.white,
                      child: IconButton(
                        icon: const Icon(LucideIcons.chevronLeft, color: Colors.black),
                        onPressed: () => Navigator.pop(context),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          
          // Timeline & details
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
                boxShadow: [BoxShadow(blurRadius: 20, color: Colors.black12)],
              ),
              child: Column(
                children: [
                  // Timeline
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildTimelineItem('Pedido', true, true),
                      _buildTimelineLine(true),
                      _buildTimelineItem('Aceito', true, true),
                      _buildTimelineLine(true),
                      _buildTimelineItem('A caminho', true, false), // Current
                      _buildTimelineLine(false),
                      _buildTimelineItem('Chegou', false, false),
                    ],
                  ),
                  const SizedBox(height: 32),
                  
                  // Provider Card
                  Row(
                    children: [
                      const CircleAvatar(
                        radius: 28,
                        backgroundColor: AppTheme.primaryPurple,
                        child: Text('CS', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(width: 16),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Carlos Silva', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                            Text('Chegando em ~8 min', style: TextStyle(color: Colors.grey)),
                          ],
                        ),
                      ),
                      Container(
                        decoration: const BoxDecoration(
                          color: AppTheme.successGreen,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: const Icon(LucideIcons.phone, color: Colors.white),
                          onPressed: () {},
                        ),
                      )
                    ],
                  ),
                  
                  const Spacer(),
                  // Chat Input Placeholder
                  TextField(
                    decoration: InputDecoration(
                      hintText: 'Enviar mensagem...',
                      filled: true,
                      fillColor: Colors.grey[100],
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30),
                        borderSide: BorderSide.none,
                      ),
                      suffixIcon: Container(
                        margin: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppTheme.primaryPurple,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: const AppBottomNav(currentIndex: 0),
    );
  }

  Widget _buildTimelineItem(String label, bool active, bool completed) {
    return Column(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: completed ? AppTheme.primaryPurple : (active ? AppTheme.secondaryOrange : Colors.grey[200]),
            shape: BoxShape.circle,
          ),
          child: Icon(
            completed ? Icons.check : (active ? LucideIcons.clock : null), 
            color: Colors.white, 
            size: 14
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label, 
          style: TextStyle(
            fontSize: 10, 
            color: active || completed ? Colors.black87 : Colors.grey
          )
        ),
      ],
    );
  }

  Widget _buildTimelineLine(bool active) {
    return Expanded(
      child: Container(
        height: 2,
        color: active ? AppTheme.primaryPurple : Colors.grey[200],
      ),
    );
  }
}
