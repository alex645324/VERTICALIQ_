// lib/screens/shift_schedule_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/storage_service.dart';

class ShiftScheduleScreen extends StatelessWidget {
  const ShiftScheduleScreen({super.key});

  @override
  Widget build(BuildContext context) {
    print('ShiftScheduleScreen: build called');
    final storage = context.watch<StorageService>();
    final start = storage.shiftStart;
    final end = storage.shiftEnd;
    print('ShiftScheduleScreen: shiftStart = [32m${start}[0m');
    print('ShiftScheduleScreen: shiftEnd = [32m${end}[0m');

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule Your Shift')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TimePickerField(
              label: 'Shift Start',
              initialValue: start,
              onTimeSelected: (value) {
                print('ShiftScheduleScreen: Shift Start selected: $value');
                storage.setShiftStart(value);
              },
            ),
            const SizedBox(height: 16),
            TimePickerField(
              label: 'Shift End',
              initialValue: end,
              onTimeSelected: (value) {
                print('ShiftScheduleScreen: Shift End selected: $value');
                storage.setShiftEnd(value);
              },
            ),
            const Spacer(),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      print('ShiftScheduleScreen: Save button pressed');
                      if (start != null && end != null) {
                        print('ShiftScheduleScreen: Schedule saved: start=$start, end=$end');
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Schedule Saved!')),
                        );
                      } else {
                        print('ShiftScheduleScreen: Save attempted with missing start or end');
                      }
                    },
                    child: const Text('Save'),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      print('ShiftScheduleScreen: Clear button pressed');
                      storage.clearSchedule();
                    },
                    child: const Text('Clear'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A simple widget that shows the current time string (HH:mm) and opens a picker.
class TimePickerField extends StatelessWidget {
  final String label;
  final String? initialValue;
  final ValueChanged<String> onTimeSelected;

  const TimePickerField({
    super.key,
    required this.label,
    required this.initialValue,
    required this.onTimeSelected,
  });

  Future<void> _pickTime(BuildContext context) async {
    print('TimePickerField: _pickTime called for label: $label');
    final now = TimeOfDay.now();
    final initial = initialValue != null
        ? TimeOfDay(
            hour: int.parse(initialValue!.split(':')[0]),
            minute: int.parse(initialValue!.split(':')[1]),
          )
        : now;
    print('TimePickerField: Initial time for picker: [34m${initial.format(context)}[0m');
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null) {
      final formatted = picked.format(context);
      print('TimePickerField: Time picked for $label: $formatted');
      onTimeSelected(picked.hour.toString().padLeft(2, '0') +
          ':' +
          picked.minute.toString().padLeft(2, '0'));
    } else {
      print('TimePickerField: Time picker cancelled for $label');
    }
  }

  @override
  Widget build(BuildContext context) {
    print('TimePickerField: build called for label: $label');
    return InkWell(
      onTap: () => _pickTime(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Text(initialValue ?? 'Not set'),
      ),
    );
  }
}
