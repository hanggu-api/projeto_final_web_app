import 'package:flutter/material.dart';

import '../../core/network/backend_api_client.dart';
import '../../widgets/user_avatar.dart';

class RecentSignupsScreen extends StatefulWidget {
  const RecentSignupsScreen({super.key});

  @override
  State<RecentSignupsScreen> createState() => _RecentSignupsScreenState();
}

class _RecentSignupsScreenState extends State<RecentSignupsScreen> {
  final _client = const BackendApiClient();
  List<Map<String, dynamic>> _users = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final now = DateTime.now();
      final yesterday = DateTime(now.year, now.month, now.day - 1);
      final since = yesterday.toIso8601String();

      final res = await _client.getJson(
        '/api/v1/users?created_at_gte=${Uri.encodeQueryComponent(since)}'
        '&order=created_at.desc&limit=200',
      );

      final data = res?['data'];
      final list = data is List
          ? data.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList()
          : <Map<String, dynamic>>[];

      setState(() => _users = list);
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _loading = false);
    }
  }

  String _label(Map<String, dynamic> user) {
    final raw = user['created_at']?.toString() ?? '';
    if (raw.isEmpty) return '';
    final dt = DateTime.tryParse(raw)?.toLocal();
    if (dt == null) return '';
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(dt.year, dt.month, dt.day);
    if (day == today) return 'Hoje';
    if (day == today.subtract(const Duration(days: 1))) return 'Ontem';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Novos cadastros'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text('Erro: $_error'))
              : _users.isEmpty
                  ? const Center(child: Text('Nenhum cadastro ontem ou hoje.'))
                  : ListView.builder(
                      itemCount: _users.length,
                      itemBuilder: (context, i) {
                        final user = _users[i];
                        final name = (user['full_name'] ?? user['name'] ?? '').toString();
                        final avatar = user['avatar_url']?.toString();
                        final role = (user['role'] ?? '').toString();
                        final label = _label(user);
                        return ListTile(
                          leading: UserAvatar(
                            avatar: avatar,
                            name: name,
                            userId: user['id']?.toString(),
                            radius: 22,
                          ),
                          title: Text(name.isNotEmpty ? name : 'Sem nome'),
                          subtitle: Text(role),
                          trailing: label.isNotEmpty
                              ? Chip(
                                  label: Text(label),
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                )
                              : null,
                        );
                      },
                    ),
    );
  }
}
