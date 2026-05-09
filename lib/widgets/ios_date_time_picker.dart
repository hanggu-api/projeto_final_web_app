import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/theme/app_theme.dart';

class AppCupertinoPicker {
  static Future<DateTime?> showDatePicker({
    required BuildContext context,
    required DateTime initialDate,
    required DateTime firstDate,
    required DateTime lastDate,
    String title = 'Selecionar data',
  }) {
    final safeInitial = _clampDate(initialDate, firstDate, lastDate);
    return _showPickerSheet<DateTime>(
      context: context,
      title: title,
      initialValue: DateTime(
        safeInitial.year,
        safeInitial.month,
        safeInitial.day,
      ),
      builder: (sheetContext, value, setValue) {
        return CupertinoDatePicker(
          mode: CupertinoDatePickerMode.date,
          initialDateTime: value,
          minimumDate: firstDate,
          maximumDate: lastDate,
          use24hFormat: true,
          onDateTimeChanged: (newDate) {
            _playPickerFeedback();
            setValue(DateTime(newDate.year, newDate.month, newDate.day));
          },
        );
      },
      formatter: (value) => DateFormat('dd/MM/yyyy', 'pt_BR').format(value),
    );
  }

  static Future<TimeOfDay?> showTimePicker({
    required BuildContext context,
    required TimeOfDay initialTime,
    String title = 'Selecionar horário',
  }) {
    return _showPickerSheet<TimeOfDay>(
      context: context,
      title: title,
      initialValue: initialTime,
      builder: (sheetContext, value, setValue) {
        final effectiveDate = DateTime(2000, 1, 1, value.hour, value.minute);
        return CupertinoDatePicker(
          mode: CupertinoDatePickerMode.time,
          initialDateTime: effectiveDate,
          use24hFormat: true,
          minuteInterval: 1,
          onDateTimeChanged: (newDate) {
            _playPickerFeedback();
            setValue(TimeOfDay(hour: newDate.hour, minute: newDate.minute));
          },
        );
      },
      formatter: (value) =>
          '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}',
    );
  }

  static Future<T?> _showPickerSheet<T>({
    required BuildContext context,
    required String title,
    required T initialValue,
    required Widget Function(
      BuildContext context,
      T value,
      ValueChanged<T> setValue,
    )
    builder,
    required String Function(T value) formatter,
  }) async {
    T tempValue = initialValue;

    return showModalBottomSheet<T>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return SafeArea(
              top: false,
              child: Container(
                margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(28),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.12),
                      blurRadius: 28,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 52,
                      height: 5,
                      margin: const EdgeInsets.only(top: 10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
                      child: Row(
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(sheetContext).pop(),
                            child: const Text(
                              'Cancelar',
                              style: TextStyle(
                                color: Colors.black87,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Expanded(
                            child: Column(
                              children: [
                                Text(
                                  title,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.black87,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  formatter(tempValue),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.grey.shade700,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: () =>
                                Navigator.of(sheetContext).pop(tempValue),
                            child: Text(
                              'Confirmar',
                              style: TextStyle(
                                color: AppTheme.primaryBlue,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    SizedBox(
                      height: 260,
                      child: builder(
                        sheetContext,
                        tempValue,
                        (next) => setState(() => tempValue = next),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  static DateTime _clampDate(DateTime value, DateTime min, DateTime max) {
    if (value.isBefore(min)) return min;
    if (value.isAfter(max)) return max;
    return value;
  }

  static void _playPickerFeedback() {
    HapticFeedback.selectionClick();
    SystemSound.play(SystemSoundType.click);
  }
}
