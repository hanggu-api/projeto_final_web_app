import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../core/theme/app_theme.dart';
import '../../services/api_service.dart';

class ProfessionsListScreen extends StatefulWidget {
  final String serviceType; // 'at_provider' | 'on_site'
  const ProfessionsListScreen({super.key, required this.serviceType});

  @override
  State<ProfessionsListScreen> createState() => _ProfessionsListScreenState();
}

class _ProfessionsListScreenState extends State<ProfessionsListScreen> {
  final _api = ApiService();
  final _search = TextEditingController();
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final rows = await _api.fetchProfessionsByServiceType(widget.serviceType);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final title =
        widget.serviceType == 'at_provider' ? 'Serviços Fixos' : 'Serviços Móveis';
    final q = _search.text.trim().toLowerCase();
    final filtered = q.isEmpty
        ? _items
        : _items
            .where((p) => (p['name'] ?? '').toString().toLowerCase().contains(q))
            .toList();

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title,
          style: GoogleFonts.manrope(fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
            child: TextField(
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar...',
                prefixIcon: const Icon(LucideIcons.search, size: 18),
                filled: true,
                fillColor: AppTheme.backgroundLight.withOpacity(0.6),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView.separated(
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) =>
                        Divider(height: 1, color: Colors.grey.shade200),
                    itemBuilder: (context, index) {
                      final p = filtered[index];
                      final name = (p['name'] ?? 'Profissão').toString();
                      return ListTile(
                        title: Text(
                          name,
                          style:
                              GoogleFonts.manrope(fontWeight: FontWeight.w800),
                        ),
                        trailing: const Icon(LucideIcons.chevronRight, size: 18),
                        onTap: () {
                          Navigator.pop(context, name);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

