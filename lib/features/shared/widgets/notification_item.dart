import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class NotificationItem extends StatelessWidget {
  final Map<String, dynamic> notification;
  final VoidCallback onTap;

  const NotificationItem({
    super.key,
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    // Firestore uses 'read' (boolean) and 'created_at' (ISO String)
    final bool isRead = notification['read'] == true || notification['is_read'] == true;
    final String title = notification['title'] ?? 'Notificação';
    final String body = notification['body'] ?? '';
    final String timeStr = notification['created_at'] ?? notification['sent_at'] ?? '';
    
    DateTime? sentAt;
    try {
      if (timeStr.isNotEmpty) {
          sentAt = DateTime.parse(timeStr).toLocal();
      }
    } catch (_) {}

    return Card(
      elevation: isRead ? 0 : 2,
      color: isRead ? Colors.white : Colors.blue.shade50,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Icon Indicator
              CircleAvatar(
                radius: 20,
                backgroundColor: isRead ? Colors.grey.shade200 : Colors.blue.shade100,
                child: Icon(
                  isRead ? Icons.notifications_none : Icons.notifications_active,
                  color: isRead ? Colors.grey : Colors.blue,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                            Expanded(child: Text(
                              title,
                              style: TextStyle(
                                fontWeight: isRead ? FontWeight.normal : FontWeight.bold,
                                fontSize: 15,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )),
                             if (sentAt != null) 
                                Text(
                                    DateFormat('dd/MM HH:mm').format(sentAt),
                                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                                ),
                        ]
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: TextStyle(
                          color: Colors.grey.shade800,
                          fontSize: 13
                      ),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (!isRead)
                Padding(
                  padding: const EdgeInsets.only(left: 8, top: 15),
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.blue,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
