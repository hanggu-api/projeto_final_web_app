import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/api_service.dart';
import '../../widgets/user_avatar.dart';

class MedicalChatList extends StatefulWidget {
  const MedicalChatList({super.key});

  @override
  State<MedicalChatList> createState() => _MedicalChatListState();
}

class _MedicalChatListState extends State<MedicalChatList> {
  final _api = ApiService();
  List<dynamic> _services = [];
  bool _loading = true;
  int? _myUserId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _myUserId = prefs.getInt('user_id');

      // Fallback if not in prefs
      if (_myUserId == null) {
        try {
          _myUserId = await _api.getMyUserId();
        } catch (_) {}
      }

      final list = await _api.getMyServices();
      final filtered = list.where((s) {
        final status = (s['status'] ?? '').toString();
        // Medical professionals act as providers
        return status == 'accepted' || status == 'in_progress';
      }).toList();

      if (mounted) {
        setState(() {
          _services = filtered;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_services.isEmpty) {
      return const Center(child: Text('Nenhuma conversa ativa'));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemBuilder: (context, index) {
        final s = _services[index];
        final status = (s['status'] ?? '').toString();
        final isActive = status == 'accepted' || status == 'in_progress';

        // Medical professional is always the provider in this context
        // So we show the Client

        String otherName =
            s['client_name']?.toString() ??
            s['user_name']?.toString() ??
            (s['client'] is Map ? s['client']['name']?.toString() : null) ??
            'Cliente';

        String? otherAvatar =
            s['client_avatar']?.toString() ??
            s['user_avatar']?.toString() ??
            s['client_photo']?.toString() ??
            s['user_photo']?.toString() ??
            (s['client'] is Map
                ? (s['client']['avatar']?.toString() ??
                      s['client']['photo']?.toString() ??
                      s['client']['image']?.toString())
                : null);

        int? otherId;
        if (s['client_id'] != null) {
          otherId = s['client_id'] is int
              ? s['client_id']
              : int.tryParse(s['client_id'].toString());
        }
        if (otherId == null && s['client'] is Map) {
          final cId = s['client']['id'];
          if (cId != null) {
            otherId = cId is int ? cId : int.tryParse(cId.toString());
          }
        }

        return ListTile(
          leading: UserAvatar(
            avatar: otherAvatar,
            name: otherName,
            userId: otherId,
            radius: 24,
            showOnlineStatus: true,
          ),
          title: Text(otherName),
          subtitle: Text(
            (s['address'] ?? '').toString(),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            isActive ? Icons.chat_bubble : Icons.check_circle,
            color: isActive ? Colors.deepPurple : Colors.green,
          ),
          onTap: () {
            final id = s['id']?.toString();
            if (id != null) {
              context.go('/chat', extra: id);
            }
          },
        );
      },
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemCount: _services.length,
    );
  }
}
