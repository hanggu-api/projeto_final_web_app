import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:service_101/features/shared/widgets/notification_item.dart';
import 'package:service_101/services/data_gateway.dart';
import 'package:go_router/go_router.dart';

class NotificationScreen extends StatefulWidget {
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  final DataGateway _gateway = DataGateway();
  final String? _uid = Supabase.instance.client.auth.currentUser?.id;

  @override
  Widget build(BuildContext context) {
    if (_uid == null) {
        return Scaffold(
            appBar: AppBar(title: const Text('Notificações')),
            body: const Center(child: Text('Não conectado')),
        );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificações'),
        centerTitle: true,
        // actions: [
        //   IconButton(
        //     icon: const Icon(Icons.done_all),
        //     tooltip: 'Marcar todas como lidas',
        //     onPressed: () {
        //         // TODO: Implement mark all read via batch
        //     },
        //   )
        // ],
      ),
      body: StreamBuilder<List<Map<String, dynamic>>>(
        stream: _gateway.watchNotifications(_uid),
        builder: (context, snapshot) {
            if (snapshot.hasError) {
                return Center(child: Text('Erro: ${snapshot.error}'));
            }

            if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
            }

            final notifications = snapshot.data ?? [];

            if (notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: const [
                      Icon(Icons.notifications_off_outlined, size: 64, color: Colors.grey),
                      SizedBox(height: 16),
                      Text('Nenhuma notificação encontrada.', style: TextStyle(color: Colors.grey)),
                    ],
                  ),
                );
            }

            return ListView.builder(
              itemCount: notifications.length,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemBuilder: (context, index) {
                final notification = notifications[index];
                return NotificationItem(
                  notification: notification,
                  onTap: () => _onNotificationTap(notification),
                );
              },
            );
        },
      ),
    );
  }

  void _onNotificationTap(Map<String, dynamic> notification) {
    if (_uid == null) return;

    final String id = notification['id'];
    // 1. Mark as Read
    if (notification['read'] != true) {
        _gateway.markNotificationRead(_uid, id);
    }

    // 2. Navigate based on data
    if (notification['data'] != null) {
        final data = notification['data'];
        // Handle nested mapValue structure from raw Firestore REST or simplified map
        // Our DataGateway normalizes it? Let's assume normalized map.
        // Wait, notifyUser saves: data: { mapValue: { fields: ... } }
        // Firestore SDK (client side) normalizes this automatically!
        // So data should be a simple Map<String, dynamic>
        
        // Debug
        debugPrint('Notification Data: $data');

        if (data['service_id'] != null) {
             context.push('/service-tracking/${data['service_id']}');
        } else if (data['id'] != null && (data['type'] == 'service.status' || data['type'] == 'service.updated')) {
             context.push('/service-tracking/${data['id']}');
        }
    }
  }
}
