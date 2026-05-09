import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';

import '../../../core/theme/app_theme.dart';

class FixedBookingScheduleStep extends StatelessWidget {
  final String providerName;
  final String? providerAvatarUrl;
  final String providerAddress;
  final String? providerRatingLabel;
  final int reviewsCount;
  final String? distanceLabel;
  final String? etaLabel;
  final DateTime? selectedDate;
  final String? selectedTimeSlot;
  final List<Map<String, dynamic>> realSlots;
  final bool loadingSlots;
  final VoidCallback onConfirm;
  final ValueChanged<DateTime> onDateChanged;
  final ValueChanged<String?> onTimeSlotSelected;

  const FixedBookingScheduleStep({
    super.key,
    required this.providerName,
    required this.providerAvatarUrl,
    required this.providerAddress,
    required this.providerRatingLabel,
    required this.reviewsCount,
    required this.distanceLabel,
    required this.etaLabel,
    required this.selectedDate,
    required this.selectedTimeSlot,
    required this.realSlots,
    required this.loadingSlots,
    required this.onConfirm,
    required this.onDateChanged,
    required this.onTimeSlotSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Agendamento no salão',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          const Text(
            'Escolha data e horário',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade200),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.grey[200],
                    borderRadius: BorderRadius.circular(12),
                    image: providerAvatarUrl != null
                        ? DecorationImage(
                            image: NetworkImage(providerAvatarUrl!),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: providerAvatarUrl == null
                      ? const Icon(Icons.person, color: Colors.grey, size: 30)
                      : null,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        providerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      if (providerRatingLabel != null)
                        Row(
                          children: [
                            const Icon(
                              Icons.star,
                              size: 14,
                              color: Colors.amber,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              providerRatingLabel!,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '($reviewsCount avaliações)',
                              style: TextStyle(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on,
                            size: 14,
                            color: Colors.grey,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              providerAddress,
                              style: const TextStyle(
                                color: Colors.grey,
                                fontSize: 12,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      if (distanceLabel != null && etaLabel != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              LucideIcons.mapPin,
                              size: 14,
                              color: AppTheme.primaryPurple,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              distanceLabel!,
                              style: TextStyle(
                                color: AppTheme.primaryPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(
                              LucideIcons.clock,
                              size: 14,
                              color: AppTheme.primaryPurple,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              etaLabel!,
                              style: TextStyle(
                                color: AppTheme.primaryPurple,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(
              colorScheme: Theme.of(context).colorScheme.copyWith(
                primary: AppTheme.primaryBlue,
                onPrimary: Colors.white,
              ),
            ),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200),
              ),
              child: CalendarDatePicker(
                initialDate: selectedDate ?? DateTime.now(),
                firstDate: DateTime.now(),
                lastDate: DateTime.now().add(const Duration(days: 60)),
                onDateChanged: onDateChanged,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text(
            'Horários',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          const SizedBox(height: 12),
          if (loadingSlots)
            const Center(child: CircularProgressIndicator())
          else if (realSlots.isEmpty)
            const Text(
              'Nenhum horário livre.',
              style: TextStyle(color: Colors.orange),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(4),
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  childAspectRatio: 1.8,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
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
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
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
                      alignment: Alignment.center,
                      child: Text(
                        timeStr,
                        style: TextStyle(
                          fontWeight: isSelected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: isBusy
                              ? Colors.grey
                              : (isSelected ? Colors.white : Colors.black87),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          const SizedBox(height: 32),
          SizedBox(
            width: double.infinity,
            height: 56,
            child: ElevatedButton(
              onPressed: (selectedDate != null && selectedTimeSlot != null)
                  ? onConfirm
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.black,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
              child: const Text('Confirmar Horário'),
            ),
          ),
        ],
      ),
    );
  }
}
