import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../services/data_gateway.dart';
import '../../../services/notification_service.dart';
import 'notification_item.dart';

class NotificationDropdownMenu extends StatelessWidget {
  const NotificationDropdownMenu({super.key});

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black26,
      builder: (dialogContext) {
        return const NotificationDropdownMenu();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    final topInset = MediaQuery.of(context).padding.top + 56;
    final availableWidth = MediaQuery.of(context).size.width - 32;

    return SafeArea(
      child: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: EdgeInsets.fromLTRB(16, topInset, 16, 16),
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: availableWidth > 360 ? 360 : availableWidth,
              constraints: const BoxConstraints(maxHeight: 460),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.16),
                    blurRadius: 28,
                    offset: const Offset(0, 14),
                  ),
                ],
              ),
              child: uid == null
                  ? const _NotificationDropdownEmptyState(
                      title: 'Notificações',
                      message: 'Você precisa estar conectado para ver alertas.',
                    )
                  : _NotificationDropdownBody(uid: uid),
            ),
          ),
        ),
      ),
    );
  }
}

class _NotificationDropdownBody extends StatelessWidget {
  final String uid;

  const _NotificationDropdownBody({required this.uid});

  @override
  Widget build(BuildContext context) {
    final gateway = DataGateway();

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: gateway.watchNotifications(uid),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _NotificationDropdownEmptyState(
            title: 'Notificações',
            message: 'Não foi possível carregar as notificações.',
          );
        }

        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(),
            ),
          );
        }

        final notifications = snapshot.data ?? const <Map<String, dynamic>>[];

        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 18, 14, 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Notificações',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            if (notifications.isEmpty)
              const Expanded(
                child: _NotificationDropdownEmptyState(
                  title: 'Tudo em dia',
                  message: 'Nenhuma notificação encontrada no momento.',
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  itemCount: notifications.length,
                  itemBuilder: (context, index) {
                    final notification = notifications[index];
                    return NotificationItem(
                      notification: notification,
                      onTap: () async {
                        final id = '${notification['id'] ?? ''}'.trim();
                        final isUnread =
                            notification['read'] != true &&
                            notification['is_read'] != true;
                        if (isUnread && id.isNotEmpty) {
                          await gateway.markNotificationRead(uid, id);
                        }
                        if (!context.mounted) return;
                        Navigator.of(context).pop();
                        final payload = _extractNotificationPayload(
                          notification,
                        );
                        if (payload.isNotEmpty) {
                          NotificationService().handleNotificationTap(payload);
                        }
                      },
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }

  Map<String, dynamic> _extractNotificationPayload(
    Map<String, dynamic> source,
  ) {
    final raw = source['data'];
    Map<String, dynamic> payload;

    if (raw is Map<String, dynamic>) {
      payload = Map<String, dynamic>.from(raw);
    } else if (raw is Map) {
      payload = raw.map((key, value) => MapEntry(key.toString(), value));
    } else if (raw is String && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          payload = Map<String, dynamic>.from(decoded);
        } else if (decoded is Map) {
          payload = decoded.map(
            (key, value) => MapEntry(key.toString(), value),
          );
        } else {
          payload = <String, dynamic>{};
        }
      } catch (_) {
        payload = <String, dynamic>{};
      }
    } else {
      payload = <String, dynamic>{};
    }

    payload.putIfAbsent('id', () => source['service_id'] ?? source['id']);
    payload.putIfAbsent('service_id', () => source['service_id']);
    payload.putIfAbsent('title', () => source['title']);
    payload.putIfAbsent('body', () => source['body']);
    payload.putIfAbsent('type', () => source['type']);
    return payload;
  }
}

class _NotificationDropdownEmptyState extends StatelessWidget {
  final String title;
  final String message;

  const _NotificationDropdownEmptyState({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.notifications_none_rounded,
              size: 42,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 14),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
