import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/api_service.dart';
import '../../../core/utils/input_formatters.dart';

  class SelectServicesStep extends StatefulWidget {
    final List<Map<String, dynamic>> selectedServices;
    final Function(List<Map<String, dynamic>>) onChanged;
    final int professionId;
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

    @override
    void initState() {
      super.initState();
      _loadTasks();
    }

    Future<void> _loadTasks() async {
      try {
        final tasks = await ApiService().getProfessionTasks(widget.professionId);
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
      final currentList = List<Map<String, dynamic>>.from(
        widget.selectedServices,
      );

      // Check if already selected by name (assuming name is unique enough for this context)
      final existingIndex = currentList.indexWhere(
        (s) => s['name'] == task['name'],
      );

      if (existingIndex >= 0) {
        currentList.removeAt(existingIndex);
      } else {
        // Add formatted service
        currentList.add({
          'name': task['name'],
          'duration': _parseDuration(task['keywords']),
          'price':
              double.tryParse(
                task['unit_price']?.toString() ??
                    task['price']?.toString() ??
                    '0',
              ) ??
              0.0,
          'description': task['description'] ?? '',
        });
      }
      widget.onChanged(currentList);
    }

    void _toggleAll() {
      if (_availableTasks.isEmpty) return;

      final allStandardSelected = _availableTasks.every(
        (task) => widget.selectedServices.any((s) => s['name'] == task['name']),
      );

      if (allStandardSelected) {
        // Deselect all standard tasks, keep custom ones
        final newSelection = widget.selectedServices.where((s) {
          return !_availableTasks.any((task) => task['name'] == s['name']);
        }).toList();
        widget.onChanged(newSelection);
      } else {
        // Select all standard tasks
        final newSelection = List<Map<String, dynamic>>.from(
          widget.selectedServices,
        );

        for (final task in _availableTasks) {
          if (!newSelection.any((s) => s['name'] == task['name'])) {
            newSelection.add({
              'name': task['name'],
              'duration': _parseDuration(task['keywords']),
              'price':
                  double.tryParse(
                    task['unit_price']?.toString() ??
                        task['price']?.toString() ??
                        '0',
                  ) ??
                  0.0,
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
      bool found = false;

      // Look for hours (e.g. 1h, 2h)
      final hoursRegex = RegExp(r'(\d+)\s*h');
      final hoursMatch = hoursRegex.firstMatch(keywords);
      if (hoursMatch != null) {
        minutes += (int.tryParse(hoursMatch.group(1)!) ?? 0) * 60;
        found = true;
      }

      // Look for minutes (e.g. 30min, 30 min)
      final minRegex = RegExp(r'(\d+)\s*min');
      final minMatch = minRegex.firstMatch(keywords);
      if (minMatch != null) {
        minutes += int.tryParse(minMatch.group(1)!) ?? 0;
        found = true;
      }

      return found ? minutes : 30;
    }

    void _addCustomService() async {
      final result = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (context) => const _AddCustomServiceDialog(),
      );

      if (result != null) {
        // Parse price considering currency mask
        final priceString = result['price']?.toString() ?? '0';
        // Remove currency symbol and formatting if present
        final cleanPrice = priceString
            .replaceAll('R\$', '')
            .replaceAll('.', '') // Remove thousand separator
            .replaceAll(',', '.') // Replace decimal separator
            .trim();

        final price = double.tryParse(cleanPrice) ?? 0.0;

        // Update result with clean price
        final cleanResult = Map<String, dynamic>.from(result);
        cleanResult['price'] = price;

        final currentList = List<Map<String, dynamic>>.from(
          widget.selectedServices,
        );
        currentList.add(cleanResult);
        widget.onChanged(currentList);
      }
    }

    @override
    Widget build(BuildContext context) {
      // Check if all standard tasks are selected
      final allSelected =
          _availableTasks.isNotEmpty &&
          _availableTasks.every(
            (task) =>
                widget.selectedServices.any((s) => s['name'] == task['name']),
          );

      // Ensure we don't display a count if nothing is selected, though the parent widget handles validation.
      // The issue reported is "even without any service selected shows 10 services selected".
      // This implies widget.selectedServices might be initialized with items or _availableTasks is being used incorrectly.
      // Let's debug by ensuring we only show the count if > 0.

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.only(bottom: 16),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.black,
              borderRadius: BorderRadius.circular(24),
            ),
            child: Column(
              children: [
                const Text(
                  'Selecione os procedimentos',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                  textAlign: TextAlign.center,
                ),
                if (widget.professionName != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.professionName!,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white, // Contrast accent changed from yellow
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                const Text(
                  'Toque para selecionar os serviços que você realiza. O valor e tempo padrão não são editáveis aqui.',
                  style: TextStyle(fontSize: 12, color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : GridView.builder(
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      childAspectRatio: 1.2,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _availableTasks.length,
                    itemBuilder: (context, index) {
                      final task = _availableTasks[index];
                      final isSelected = widget.selectedServices.any(
                        (s) => s['name'] == task['name'],
                      );

                      // Pre-calculate display values
                      var price =
                          double.tryParse(
                            task['unit_price']?.toString() ??
                                task['price']?.toString() ??
                                '0',
                          ) ??
                          0.0;

                      // Show 10% less for provider
                      // REMOVED: Backend seed already has the 10% commission applied (Median * 0.9)
                      // price = price * 0.9;

                      final duration = _parseDuration(task['keywords']);

                      return InkWell(
                        onTap: () => _toggleService(task),
                        child: Container(
                          decoration: BoxDecoration(
                            color: isSelected ? Colors.black : Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.black
                                  : Colors.grey.shade300,
                              width: 2,
                            ),
                            boxShadow: [
                              if (!isSelected)
                                BoxShadow(
                                  color: Colors.grey.withValues(alpha: 0.1),
                                  blurRadius: 4,
                                  offset: const Offset(0, 2),
                                ),
                            ],
                          ),
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                task['name'],
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: isSelected ? Colors.white : Colors.black,
                                ),
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                '$duration min',
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white70
                                      : Colors.grey,
                                  fontSize: 14,
                                ),
                              ),
                              Text(
                                'R\$ ${price.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : Colors.black,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 22,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          const SizedBox(height: 16),
          if (_availableTasks.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 12.0),
              child: OutlinedButton.icon(
                onPressed: _toggleAll,
                icon: Icon(
                  allSelected ? Icons.check_box : Icons.check_box_outline_blank,
                ),
                label: Text(allSelected ? 'Desmarcar Todos' : 'Selecionar Todos'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  foregroundColor: Colors.black,
                  side: const BorderSide(color: Colors.black),
                ),
              ),
            ),
          ElevatedButton.icon(
            onPressed: _addCustomService,
            icon: const Icon(Icons.add, color: Colors.white),
            label: const Text(
              'Criar Novo Serviço',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              backgroundColor: Colors.black,
              foregroundColor: Colors.white,
              elevation: 4,
            ),
          ),
          if (widget.selectedServices.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Only show count if services are actually selected
            if (widget.selectedServices.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16.0),
                child: Center(
                  child: Text(
                    '${widget.selectedServices.length} serviços selecionados',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
          ],
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
        title: const Text('Novo Serviço Personalizado'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: AppTheme.inputDecoration('Nome do Serviço', Icons.cleaning_services),
                  validator: (v) => v?.isEmpty == true ? 'Obrigatório' : null,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: _durationController,
                        decoration: AppTheme.inputDecoration('Duração (min)', Icons.timer),
                        keyboardType: TextInputType.number,
                        validator: (v) =>
                            v?.isEmpty == true ? 'Obrigatório' : null,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextFormField(
                        controller: _priceController,
                        decoration: AppTheme.inputDecoration('Preço', Icons.attach_money).copyWith(
                          prefixText: r'R$ ',
                        ),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          CurrencyInputFormatter(),
                        ],
                        validator: (v) =>
                            v?.isEmpty == true ? 'Obrigatório' : null,
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
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                Navigator.pop(context, {
                  'name': _nameController.text,
                  'keywords': 'Duração: ${_durationController.text} min',
                  'price': _priceController.text,
                  'unit_price': _priceController.text, // For compatibility
                });
              }
            },
            child: const Text('Adicionar'),
          ),
        ],
      );
    }
  }
