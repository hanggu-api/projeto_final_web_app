import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../core/utils/input_formatters.dart';

class SelectServicesStep extends StatefulWidget {
  final List<Map<String, dynamic>> selectedServices;
  final Function(List<Map<String, dynamic>>) onChanged;
  final String professionId;
  final String? professionName;

  const SelectServicesStep({
    super.key,
    required this.selectedServices,
    required this.onChanged,
    required this.professionId,
    this.professionName,
  });

  @override
  State<SelectServicesStep> createState() => _SelectServicesStepState();
}

class _SelectServicesStepState extends State<SelectServicesStep> {
  List<dynamic> _availableTasks = [];
  bool _loading = true;

  // Design tokens para o estilo suave
  final Color _softBlue = const Color(0xFFE3F2FD);
  final Color _activeBlue = const Color(0xFF42A5F5);
  final Color _activeGreen = const Color(0xFF2E7D32);

  @override
  void initState() {
    super.initState();
    _loadTasks();
  }

  Future<void> _loadTasks() async {
    try {
      final tasks = await ApiService().getProfessionTasks(
        widget.professionId.toString(),
        professionName: widget.professionName,
      );
      if (mounted) {
        setState(() {
          _availableTasks = tasks;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao carregar serviços: $e')),
        );
      }
    }
  }

  void _toggleService(Map<String, dynamic> task) {
    final currentList = List<Map<String, dynamic>>.from(widget.selectedServices);
    final existingIndex = currentList.indexWhere((s) => s['name'] == task['name']);

    if (existingIndex >= 0) {
      currentList.removeAt(existingIndex);
    } else {
      currentList.add({
        'name': task['name'],
        'duration': _parseDuration(task['keywords']),
        'price': double.tryParse(task['unit_price']?.toString() ?? task['price']?.toString() ?? '0') ?? 0.0,
        'description': task['description'] ?? '',
      });
    }
    widget.onChanged(currentList);
  }

  void _toggleAll() {
    if (_availableTasks.isEmpty) return;
    final allSelected = _availableTasks.every((task) => widget.selectedServices.any((s) => s['name'] == task['name']));

    if (allSelected) {
      final newSelection = widget.selectedServices.where((s) => !_availableTasks.any((task) => task['name'] == s['name'])).toList();
      widget.onChanged(newSelection);
    } else {
      final newSelection = List<Map<String, dynamic>>.from(widget.selectedServices);
      for (final task in _availableTasks) {
        if (!newSelection.any((s) => s['name'] == task['name'])) {
          newSelection.add({
            'name': task['name'],
            'duration': _parseDuration(task['keywords']),
            'price': double.tryParse(task['unit_price']?.toString() ?? task['price']?.toString() ?? '0') ?? 0.0,
            'description': task['description'] ?? '',
          });
        }
      }
      widget.onChanged(newSelection);
    }
  }

  int _parseDuration(String? keywords) {
    if (keywords == null) return 30;
    int minutes = 0;
    final hoursRegex = RegExp(r'(\d+)\s*h');
    final hoursMatch = hoursRegex.firstMatch(keywords);
    if (hoursMatch != null) minutes += (int.tryParse(hoursMatch.group(1)!) ?? 0) * 60;
    final minRegex = RegExp(r'(\d+)\s*min');
    final minMatch = minRegex.firstMatch(keywords);
    if (minMatch != null) minutes += int.tryParse(minMatch.group(1)!) ?? 0;
    return minutes > 0 ? minutes : 30;
  }

  void _addCustomService() async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) => const _AddCustomServiceDialog(),
    );

    if (result != null) {
      final priceString = result['price']?.toString() ?? '0';
      final cleanPrice = priceString.replaceAll('R\$', '').replaceAll('.', '').replaceAll(',', '.').trim();
      final price = double.tryParse(cleanPrice) ?? 0.0;

      final cleanResult = Map<String, dynamic>.from(result);
      cleanResult['price'] = price;

      final currentList = List<Map<String, dynamic>>.from(widget.selectedServices);
      currentList.add(cleanResult);
      widget.onChanged(currentList);
    }
  }

  @override
  Widget build(BuildContext context) {
    final allSelected = _availableTasks.isNotEmpty && _availableTasks.every((task) => widget.selectedServices.any((s) => s['name'] == task['name']));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header redesenhado (Estilo Suave)
        Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _activeBlue.withOpacity(0.2), width: 1.5),
            boxShadow: [
              BoxShadow(
                color: _activeBlue.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              Text(
                'Selecione os procedimentos',
                style: GoogleFonts.manrope(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: AppTheme.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              if (widget.professionName != null) ...[
                const SizedBox(height: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: _softBlue,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    widget.professionName!,
                    style: GoogleFonts.manrope(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: _activeBlue,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'Toque para selecionar os serviços que você realiza. O valor e tempo padrão não são editáveis aqui.',
                style: GoogleFonts.manrope(
                  fontSize: 12,
                  color: Colors.grey[600],
                  fontWeight: FontWeight.w500,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),

        // Grid Redesenhado
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : LayoutBuilder(
                  builder: (context, constraints) {
                    final isCompact = constraints.maxWidth < 380;
                    final crossAxisSpacing = isCompact ? 10.0 : 12.0;
                    final mainAxisSpacing = isCompact ? 10.0 : 12.0;
                    final childAspectRatio = isCompact ? 0.92 : 0.98;

                    return GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 2,
                        childAspectRatio: childAspectRatio,
                        crossAxisSpacing: crossAxisSpacing,
                        mainAxisSpacing: mainAxisSpacing,
                      ),
                      itemCount: _availableTasks.length,
                      itemBuilder: (context, index) {
                        final task = _availableTasks[index];
                        final isSelected = widget.selectedServices.any(
                          (s) => s['name'] == task['name'],
                        );
                        final price =
                            double.tryParse(
                              task['unit_price']?.toString() ??
                                  task['price']?.toString() ??
                                  '0',
                            ) ??
                            0.0;
                        final duration = _parseDuration(task['keywords']);

                        return GestureDetector(
                          onTap: () => _toggleService(task),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? _softBlue.withOpacity(0.45)
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected
                                    ? _activeBlue
                                    : const Color(0xFFD9E6F5),
                                width: isSelected ? 2.4 : 1.4,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: isSelected
                                      ? _activeBlue.withOpacity(0.08)
                                      : Colors.black.withOpacity(0.025),
                                  blurRadius: isSelected ? 10 : 8,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            padding: EdgeInsets.fromLTRB(
                              isCompact ? 12 : 14,
                              isCompact ? 14 : 16,
                              isCompact ? 12 : 14,
                              isCompact ? 12 : 14,
                            ),
                            child: Stack(
                              children: [
                                if (isSelected)
                                  Positioned(
                                    top: 0,
                                    right: 0,
                                    child: Icon(
                                      Icons.check_circle,
                                      color: _activeBlue,
                                      size: isCompact ? 18 : 20,
                                    ),
                                  ),
                                Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Spacer(),
                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      child: Text(
                                        task['name'],
                                        style: GoogleFonts.manrope(
                                          fontWeight: FontWeight.w800,
                                          fontSize: isCompact ? 13.5 : 15,
                                          height: 1.25,
                                          color: isSelected
                                              ? _activeGreen
                                              : AppTheme.textDark,
                                        ),
                                        textAlign: TextAlign.center,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    SizedBox(height: isCompact ? 8 : 10),
                                    Text(
                                      '$duration min',
                                      style: GoogleFonts.manrope(
                                        color: Colors.grey[600],
                                        fontSize: isCompact ? 11 : 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    FittedBox(
                                      fit: BoxFit.scaleDown,
                                      child: Text(
                                        'R\$ ${price.toStringAsFixed(0)}',
                                        style: GoogleFonts.manrope(
                                          color: isSelected
                                              ? _activeGreen
                                              : AppTheme.textDark,
                                          fontWeight: FontWeight.w900,
                                          fontSize: isCompact ? 20 : 22,
                                          height: 1,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
        
        const SizedBox(height: 16),
        
        // Botão de Seleção Global
        if (_availableTasks.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: TextButton.icon(
              onPressed: _toggleAll,
              icon: Icon(
                allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                color: _activeBlue,
              ),
              label: Text(
                allSelected ? 'Desmarcar Todos' : 'Selecionar Todos',
                style: GoogleFonts.manrope(fontWeight: FontWeight.bold, color: _activeBlue),
              ),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                backgroundColor: _softBlue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

        // Botão Novo Serviço
        ElevatedButton.icon(
          onPressed: _addCustomService,
          icon: const Icon(Icons.add_circle_outline, color: Colors.white),
          label: Text(
            'Criar Novo Serviço',
            style: GoogleFonts.manrope(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          style: ElevatedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 14),
            backgroundColor: _activeBlue,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
        ),

        // Contador de Seleção
        if (widget.selectedServices.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16.0),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: _activeGreen.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${widget.selectedServices.length} serviços selecionados',
                  style: GoogleFonts.manrope(
                    fontWeight: FontWeight.w800,
                    color: _activeGreen,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _AddCustomServiceDialog extends StatefulWidget {
  const _AddCustomServiceDialog();

  @override
  State<_AddCustomServiceDialog> createState() =>
      _AddCustomServiceDialogState();
}

class _AddCustomServiceDialogState extends State<_AddCustomServiceDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _durationController = TextEditingController();
  final _priceController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      title: Text('Novo Serviço', style: GoogleFonts.manrope(fontWeight: FontWeight.w800)),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Nome do Serviço',
                  prefixIcon: const Icon(Icons.edit_note),
                  filled: true,
                  fillColor: Colors.grey[50],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
                validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _durationController,
                      decoration: InputDecoration(
                        labelText: 'Minutos',
                        prefixIcon: const Icon(Icons.timer_outlined),
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      keyboardType: TextInputType.number,
                      validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextFormField(
                      controller: _priceController,
                      decoration: InputDecoration(
                        labelText: 'Preço',
                        prefixIcon: const Icon(Icons.payments_outlined),
                        prefixText: r'R$ ',
                        filled: true,
                        fillColor: Colors.grey[50],
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        CurrencyInputFormatter(),
                      ],
                      validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text('Cancelar', style: GoogleFonts.manrope(color: Colors.grey)),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              Navigator.pop(context, {
                'name': _nameController.text,
                'keywords': 'Duração: ${_durationController.text} min',
                'price': _priceController.text,
                'unit_price': _priceController.text,
              });
            }
          },
          style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF42A5F5), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          child: const Text('Adicionar', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
