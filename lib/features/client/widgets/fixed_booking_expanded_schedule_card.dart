import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';

class FixedBookingExpandedScheduleCard extends StatelessWidget {
  final bool isPixReadyForProvider;
  final bool isSelectedProvider;
  final DateTime? selectedDate;
  final String? selectedTimeSlot;
  final List<Map<String, dynamic>> realSlots;
  final bool loadingSlots;
  final bool preparingInlinePix;
  final bool changingPendingSchedule;
  final String pendingPixPayload;
  final String pendingPixImage;
  final double pendingPixFee;
  final Key? pendingPixSectionKey;
  final VoidCallback onConfirmSchedule;
  final VoidCallback onChangePendingSchedule;
  final ValueChanged<DateTime> onDateSelected;
  final ValueChanged<String?> onTimeSlotSelected;

  const FixedBookingExpandedScheduleCard({
    super.key,
    required this.isPixReadyForProvider,
    required this.isSelectedProvider,
    required this.selectedDate,
    required this.selectedTimeSlot,
    required this.realSlots,
    required this.loadingSlots,
    required this.preparingInlinePix,
    required this.changingPendingSchedule,
    required this.pendingPixPayload,
    required this.pendingPixImage,
    required this.pendingPixFee,
    this.pendingPixSectionKey,
    required this.onConfirmSchedule,
    required this.onChangePendingSchedule,
    required this.onDateSelected,
    required this.onTimeSlotSelected,
  });

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final days = List<DateTime>.generate(7, (index) {
      return DateTime(now.year, now.month, now.day).add(Duration(days: index));
    });

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isPixReadyForProvider ? Colors.transparent : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        border: isPixReadyForProvider
            ? null
            : Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isPixReadyForProvider) ...[
            Text(
              'Escolha o horário',
              style: TextStyle(
                color: AppTheme.darkBlueText,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 72,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: days.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final day = days[index];
                  final isSelected =
                      selectedDate != null &&
                      selectedDate!.year == day.year &&
                      selectedDate!.month == day.month &&
                      selectedDate!.day == day.day;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => onDateSelected(day),
                    child: Container(
                      width: 70,
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected ? AppTheme.primaryBlue : Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryBlue
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            DateFormat('EEE', 'pt_BR').format(day),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade700,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            DateFormat('dd/MM').format(day),
                            style: TextStyle(
                              color: isSelected
                                  ? Colors.white
                                  : AppTheme.darkBlueText,
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 12),
            if (loadingSlots)
              const Center(child: CircularProgressIndicator())
            else if (realSlots.isEmpty)
              Text(
                'Nenhum horário livre para este dia.',
                style: TextStyle(
                  color: Colors.orange.shade700,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              )
            else
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  childAspectRatio: 2.4,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: realSlots.length,
                itemBuilder: (context, index) {
                  final slot = realSlots[index];
                  final bool isSelectable = slot['is_selectable'] == true;
                  final bool isBusy = slot['status'] != 'free' || !isSelectable;
                  final String startStr = slot['start_time'].toString();
                  final String timeStr = startStr.contains('T')
                      ? startStr.split('T')[1].substring(0, 5)
                      : "${DateTime.parse(startStr).hour.toString().padLeft(2, '0')}:${DateTime.parse(startStr).minute.toString().padLeft(2, '0')}";
                  final isSelected = selectedTimeSlot == timeStr;

                  return InkWell(
                    onTap: isBusy
                        ? null
                        : () => onTimeSlotSelected(isSelected ? null : timeStr),
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primaryBlue
                            : (isBusy ? Colors.grey[100] : Colors.white),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primaryBlue
                              : Colors.grey.shade300,
                        ),
                      ),
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          color: isBusy
                              ? Colors.grey
                              : (isSelected ? Colors.white : Colors.black87),
                          fontWeight: isSelected
                              ? FontWeight.w800
                              : FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed:
                    (isSelectedProvider &&
                        selectedDate != null &&
                        selectedTimeSlot != null)
                    ? onConfirmSchedule
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.black,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: preparingInlinePix && isSelectedProvider
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Confirmar horário'),
              ),
            ),
          ] else ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.only(bottom: 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          'Horário escolhido',
                          style: TextStyle(
                            color: AppTheme.darkBlueText,
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      TextButton.icon(
                        onPressed: changingPendingSchedule
                            ? null
                            : onChangePendingSchedule,
                        icon: changingPendingSchedule
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(
                                Icons.edit_calendar_outlined,
                                size: 18,
                              ),
                        label: const Text('Alterar'),
                        style: TextButton.styleFrom(
                          foregroundColor: AppTheme.primaryBlue,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _ScheduleSummaryChip(
                        icon: Icons.event_outlined,
                        label: selectedDate != null
                            ? DateFormat(
                                'EEE, dd/MM',
                                'pt_BR',
                              ).format(selectedDate!)
                            : '--',
                      ),
                      _ScheduleSummaryChip(
                        icon: Icons.schedule,
                        label: selectedTimeSlot ?? '--:--',
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _buildInlinePixSection(context),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _copyPixCode(BuildContext context) async {
    final payload = pendingPixPayload.trim();
    if (payload.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: payload));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Código Pix copiado.')),
      );
    }
  }

  Uint8List? _decodePixBytes() {
    var raw = pendingPixImage.trim();
    if (raw.isEmpty || raw.startsWith('http')) return null;
    if (raw.startsWith('data:image')) {
      final idx = raw.indexOf(',');
      if (idx >= 0) raw = raw.substring(idx + 1).trim();
    }
    try {
      return base64Decode(raw);
    } catch (_) {
      return null;
    }
  }

  Widget _buildInlinePixSection(BuildContext context) {
    final bytes = _decodePixBytes();
    final imageSource = pendingPixImage.trim();
    final hasImage =
        bytes != null ||
        imageSource.startsWith('http') ||
        imageSource.startsWith('data:image');

    return Container(
      key: pendingPixSectionKey,
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.orange.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.orange.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pagamento pendente',
            style: TextStyle(
              color: Colors.orange.shade900,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Conclua o Pix da taxa aqui mesmo para confirmar este horário sem sair do card.',
            style: TextStyle(
              color: Colors.orange.shade900,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          if (pendingPixFee > 0) ...[
            const SizedBox(height: 10),
            Text(
              'Taxa de agendamento: R\$ ${pendingPixFee.toStringAsFixed(2)}',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
          if (hasImage) ...[
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 190,
                height: 190,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: bytes != null
                    ? Image.memory(bytes, fit: BoxFit.contain)
                    : Image.network(imageSource, fit: BoxFit.contain),
              ),
            ),
          ],
          if (pendingPixPayload.trim().isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Código copia e cola',
              style: TextStyle(
                color: Colors.orange.shade900,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade100),
              ),
              child: SelectableText(
                pendingPixPayload,
                style: TextStyle(
                  color: Colors.grey.shade800,
                  fontSize: 12,
                  height: 1.35,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _copyPixCode(context),
                icon: const Icon(Icons.copy_rounded, size: 18),
                label: const Text('Copiar código Pix'),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _ScheduleSummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _ScheduleSummaryChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: Colors.grey.shade700),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: AppTheme.darkBlueText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
