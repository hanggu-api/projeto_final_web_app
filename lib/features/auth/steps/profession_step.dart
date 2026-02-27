import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';

class ProfessionStep extends StatefulWidget {
  final Function(Map<String, dynamic>) onSelect;
  final Map<String, dynamic>? selectedProfession;

  const ProfessionStep({
    super.key,
    required this.onSelect,
    this.selectedProfession,
  });

  @override
  State<ProfessionStep> createState() => _ProfessionStepState();
}

class _ProfessionStepState extends State<ProfessionStep> {
  List<Map<String, dynamic>> _professions = [];
  List<Map<String, dynamic>> _filteredProfessions = [];
  bool _isLoading = true;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchProfessions();
    _searchController.addListener(_filterProfessions);
  }

  Future<void> _fetchProfessions() async {
    try {
      final professions = await ApiService().getProfessions();
      setState(() {
        _professions = List<Map<String, dynamic>>.from(professions);
        _filteredProfessions = []; // Start empty
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching professions: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  String _removeDiacritics(String str) {
    // New implementation:
    var map = {
      'À': 'A',
      'Á': 'A',
      'Â': 'A',
      'Ã': 'A',
      'Ä': 'A',
      'Å': 'A',
      'à': 'a',
      'á': 'a',
      'â': 'a',
      'ã': 'a',
      'ä': 'a',
      'å': 'a',
      'Ò': 'O',
      'Ó': 'O',
      'Ô': 'O',
      'Õ': 'O',
      'Ö': 'O',
      'Ø': 'O',
      'ò': 'o',
      'ó': 'o',
      'ô': 'o',
      'õ': 'o',
      'ö': 'o',
      'ø': 'o',
      'È': 'E',
      'É': 'E',
      'Ê': 'E',
      'Ë': 'E',
      'è': 'e',
      'é': 'e',
      'ê': 'e',
      'ë': 'e',
      'ð': 'd',
      'Ç': 'C',
      'ç': 'c',
      'Ð': 'D',
      'Ì': 'I',
      'Í': 'I',
      'Î': 'I',
      'Ï': 'I',
      'ì': 'i',
      'í': 'i',
      'î': 'i',
      'ï': 'i',
      'Ù': 'U',
      'Ú': 'U',
      'Û': 'U',
      'Ü': 'U',
      'ù': 'u',
      'ú': 'u',
      'û': 'u',
      'ü': 'u',
      'Ñ': 'N',
      'ñ': 'n',
      'Š': 'S',
      'š': 's',
      'Ÿ': 'Y',
      'ÿ': 'y',
      'ý': 'y',
      'Ž': 'Z',
      'ž': 'z',
    };

    StringBuffer sb = StringBuffer();
    for (int i = 0; i < str.length; i++) {
      sb.write(map[str[i]] ?? str[i]);
    }
    return sb.toString();
  }

  void _filterProfessions() {
    final query = _removeDiacritics(
      _searchController.text.toLowerCase().trim(),
    );
    setState(() {
      if (query.length < 3) {
        _filteredProfessions = [];
      } else {
        _filteredProfessions = _professions.where((p) {
          final name = _removeDiacritics(p['name'].toString().toLowerCase());
          final type = p['service_type']?.toString().toLowerCase() ?? '';

          // Match name OR match "medico" if type is medical
          // Handles "medico", "médico", "medica", "médica", "doutor"
          bool isMedicalQuery =
              query.contains('medic') || query.contains('doutor');

          if (isMedicalQuery && type == 'medical') {
            return true;
          }

          final keywords = _removeDiacritics(
            p['keywords']?.toString().toLowerCase() ?? '',
          );
          return name.contains(query) || keywords.contains(query);
        }).toList();
      }
    });
  }

  IconData _getProfessionIcon(String name, [String? keywords]) {
    final textToSearch = _removeDiacritics(
      '${name.toLowerCase()} ${keywords?.toLowerCase() ?? ''}',
    );

    // 1. SAÚDE E BEM-ESTAR
    if (textToSearch.contains('medico') || textToSearch.contains('doutor')) {
      return Icons.medical_services;
    }
    if (textToSearch.contains('dentista') || textToSearch.contains('odonto')) {
      return Icons.medical_information;
    }
    if (textToSearch.contains('enfermeir') ||
        textToSearch.contains('enfermagem')) {
      return Icons.local_hospital;
    }
    if (textToSearch.contains('psicologo') ||
        textToSearch.contains('terapeuta')) {
      return Icons.psychology;
    }
    if (textToSearch.contains('fisioterapeuta')) return Icons.accessibility_new;
    if (textToSearch.contains('nutricionista') ||
        textToSearch.contains('dieta')) {
      return Icons.apple;
    }
    if (textToSearch.contains('cuidador') || textToSearch.contains('idoso')) {
      return Icons.elderly;
    }
    if (textToSearch.contains('massagista') || textToSearch.contains('spa')) {
      return Icons.spa;
    }

    // 2. CONSTRUÇÃO E MANUTENÇÃO (REPAROS)
    if (textToSearch.contains('pedreiro') || textToSearch.contains('obra')) {
      return Icons.foundation;
    }
    if (textToSearch.contains('eletricista') ||
        textToSearch.contains('energia')) {
      return Icons.electrical_services;
    }
    if (textToSearch.contains('encanador') ||
        textToSearch.contains('hidraulica')) {
      return Icons.plumbing;
    }
    if (textToSearch.contains('pintor') || textToSearch.contains('pintura')) {
      return Icons.format_paint;
    }
    if (textToSearch.contains('carpinteiro') ||
        textToSearch.contains('marceneiro')) {
      return Icons.handyman;
    }
    if (textToSearch.contains('chaveiro')) return Icons.key;
    if (textToSearch.contains('refrigeracao') ||
        textToSearch.contains('ar condicionado')) {
      return Icons.ac_unit;
    }
    if (textToSearch.contains('vidraceiro') || textToSearch.contains('vidro')) {
      return Icons.window;
    }
    if (textToSearch.contains('serralheiro') ||
        textToSearch.contains('ferro')) {
      return Icons.reorder;
    }
    if (textToSearch.contains('mecanico') || textToSearch.contains('oficina')) {
      return Icons.build_circle;
    }
    if (textToSearch.contains('tecnico')) return Icons.build;

    // 3. ESTÉTICA E BELEZA
    if (textToSearch.contains('barbeiro') || textToSearch.contains('barba')) {
      return Icons.content_cut;
    }
    if (textToSearch.contains('cabeleireiro') ||
        textToSearch.contains('cabelo')) {
      return Icons.content_cut;
    }
    if (textToSearch.contains('manicure') || textToSearch.contains('unha')) {
      return Icons.brush;
    }
    if (textToSearch.contains('esteticista') ||
        textToSearch.contains('limpeza de pele')) {
      return Icons.face_retouching_natural;
    }
    if (textToSearch.contains('maquiadora') || textToSearch.contains('make')) {
      return Icons.face;
    }

    // 4. SERVIÇOS DOMÉSTICOS E GERAIS
    if (textToSearch.contains('diarista') ||
        textToSearch.contains('limpeza') ||
        textToSearch.contains('faxina')) {
      return Icons.cleaning_services;
    }
    if (textToSearch.contains('cozinheiro') ||
        textToSearch.contains('buffet')) {
      return Icons.restaurant;
    }
    if (textToSearch.contains('jardinagem') ||
        textToSearch.contains('jardineiro')) {
      return Icons.yard;
    }
    if (textToSearch.contains('baba') || textToSearch.contains('crianca')) {
      return Icons.child_care;
    }
    if (textToSearch.contains('motorista') || textToSearch.contains('frete')) {
      return Icons.local_shipping;
    }
    if (textToSearch.contains('seguranca') ||
        textToSearch.contains('vigilante')) {
      return Icons.security;
    }
    if (textToSearch.contains('fotografo')) return Icons.camera_alt;

    // 5. EDUCAÇÃO E CONSULTORIA
    if (textToSearch.contains('professor') || textToSearch.contains('aula')) {
      return Icons.school;
    }
    if (textToSearch.contains('advogado') ||
        textToSearch.contains('juridico')) {
      return Icons.gavel;
    }
    if (textToSearch.contains('contador') ||
        textToSearch.contains('contabil')) {
      return Icons.calculate;
    }

    return Icons.work; // Default
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Qual é a sua profissão?',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        TextField(
          key: const Key('profession_search_field'),
          controller: _searchController,
          decoration: AppTheme.inputDecoration('Buscar profissão...', Icons.search).copyWith(
            helperText: 'Digite pelo menos 3 letras para buscar',
          ),
        ),
        const SizedBox(height: 16),
        Expanded(
          child: _searchController.text.length < 3
              ? const Center(
                  child: Text(
                    'Digite o nome da sua profissão\npara começar a busca',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 16),
                  ),
                )
              : _filteredProfessions.isEmpty
              ? const Center(
                  child: Text(
                    'Nenhuma profissão encontrada',
                    style: TextStyle(color: Colors.grey),
                  ),
                )
              : ListView.separated(
                  itemCount: _filteredProfessions.length,
                  separatorBuilder: (_, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final profession = _filteredProfessions[index];
                    final isSelected =
                        widget.selectedProfession?['id'] == profession['id'];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: isSelected
                            ? Colors.purple
                            : Colors.grey[200],
                        child: Icon(
                          _getProfessionIcon(
                            profession['name'],
                            profession['keywords'],
                          ),
                          color: isSelected ? Colors.white : Colors.grey[600],
                        ),
                      ),
                      title: Text(
                        profession['name'],
                        style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Colors.purple)
                          : null,
                      onTap: () => widget.onSelect(profession),
                      selected: isSelected,
                      tileColor: isSelected
                          ? Colors.blue.withAlpha(20)
                          : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
