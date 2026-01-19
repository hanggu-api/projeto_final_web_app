import 'dart:async';
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import '../../../services/api_service.dart';

class DispatchTrackingTimeline extends StatefulWidget {
  final String serviceId;
  final VoidCallback onProviderFound;

  const DispatchTrackingTimeline({
    super.key, 
    required this.serviceId,
    required this.onProviderFound,
  });

  @override
  State<DispatchTrackingTimeline> createState() => _DispatchTrackingTimelineState();
}

class _DispatchTrackingTimelineState extends State<DispatchTrackingTimeline> {
  Timer? _timer;
  String _headline = "Iniciando busca...";
  List<dynamic> _timeline = [];
  bool _isLoading = true;
  final _api = ApiService();

  @override
  void initState() {
    super.initState();
    _fetchTracking();
    // Poll every 4 seconds
    _timer = Timer.periodic(const Duration(seconds: 4), (_) => _fetchTracking());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _fetchTracking() async {
    try {
      final response = await _api.get('/service/${widget.serviceId}/tracking');
      if (mounted) {
        setState(() {
          _headline = response['headline'] ?? "Processando...";
          _timeline = (response['timeline'] as List?) ?? [];
          _isLoading = false;
        });

        if (response['status'] == 'accepted') {
          _timer?.cancel();
          widget.onProviderFound();
        }
            }
    } catch (e) {
      debugPrint('Error fetching tracking: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Headline
          Row(
            children: [
              if (_isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                const Icon(LucideIcons.radar, color: Colors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _headline,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          
          // Timeline
          if (_timeline.isEmpty)
             const Padding(
               padding: EdgeInsets.only(left: 8.0),
               child: Text("Conectando aos satélites...", style: TextStyle(color: Colors.grey)),
             )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _timeline.length > 3 ? 3 : _timeline.length, // Show top 3 recent
              itemBuilder: (context, index) {
                final event = _timeline[index];
                final isLast = index == (_timeline.length > 3 ? 2 : _timeline.length - 1);
                
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Column(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: index == 0 ? Colors.green : Colors.grey.shade300,
                              shape: BoxShape.circle,
                            ),
                          ),
                          if (!isLast)
                            Container(
                              width: 2,
                              height: 20, // Vertical line
                              color: Colors.grey.shade200,
                            ),
                        ],
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event['message'] ?? '',
                              style: TextStyle(
                                fontSize: 14,
                                color: index == 0 ? Colors.black87 : Colors.grey,
                                fontWeight: index == 0 ? FontWeight.w500 : FontWeight.normal,
                              ),
                            ),
                            Text(
                              event['time'] ?? '',
                              style: TextStyle(
                                fontSize: 10,
                                color: Colors.grey.shade400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}
