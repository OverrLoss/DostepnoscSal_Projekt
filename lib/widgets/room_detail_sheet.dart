import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/room_database_helper.dart';
import '../theme/app_theme.dart';

void showRoomDetailSheet({
  required BuildContext context,
  required Room room,
  required Future<void> Function(Room room) onToggleAvailability,
  required Future<void> Function(Room room) onToggleBreak,
  required VoidCallback onEdit,
  required VoidCallback onDelete,
  Future<void> Function(Room updatedRoom, int newLimitSeconds)? onLimitChanged,
}) {
  final isAvailable = room.isAvailable;
  final statusColor = room.isBreak ? AppColors.warning : (isAvailable ? AppColors.success : AppColors.danger);

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF141414),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(8)),
    ),
    builder: (ctx) {
      int currentLimitSec = room.defaultAlertLimitSeconds ?? (room.activeSession?.alertLimitSeconds ?? 900);
      bool isSavingLimit = false;

      return StatefulBuilder(
        builder: (context, setSheetState) {
          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Handle
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Room Number & Name
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: statusColor, width: 1.5),
                        ),
                        child: Text(
                          room.number,
                          style: TextStyle(
                            color: statusColor,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              room.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    room.floor,
                                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blueAccent.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    room.category,
                                    style: const TextStyle(color: AppColors.primary, fontSize: 11),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 16),

                  // Active Session & Alert Info Card
                  if (!isAvailable && room.durationFormatted.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: room.isAlertDue
                            ? Colors.red.withValues(alpha: 0.25)
                            : const Color(0xFF000000),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: room.isAlertDue ? AppColors.warning : AppColors.danger.withValues(alpha: 0.4),
                          width: room.isAlertDue ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (room.isAlertDue) ...[
                            const Row(
                              children: [
                                Icon(Icons.warning_amber_rounded, color: AppColors.warning, size: 18),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    'Przekroczono limit czasu sesji',
                                    style: TextStyle(
                                      color: AppColors.warning,
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                          ],
                          if (room.occupantName != null) ...[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Zajmuje:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                                const SizedBox(width: 12),
                                Flexible(
                                  child: Text(
                                    room.occupantName!,
                                    textAlign: TextAlign.right,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                          ],
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Czas trwania sesji:', style: TextStyle(color: Colors.white70, fontSize: 13)),
                              Text(
                                room.durationFormatted,
                                style: TextStyle(
                                  color: room.isAlertDue ? AppColors.warning : Colors.white,
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  fontFamily: 'monospace',
                                ),
                              ),
                            ],
                          ),
                          if (room.activeSession != null) ...[
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('Limit bieżącej sesji:', style: TextStyle(color: Colors.white54, fontSize: 11)),
                                Text(
                                  '${room.activeSession!.alertLimitSeconds ~/ 60} minut',
                                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // Time Limit Selector for this Room
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF000000),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Row(
                              children: [
                                Icon(Icons.timer_outlined, color: AppColors.warning, size: 18),
                                SizedBox(width: 8),
                                Text(
                                  'LIMIT CZASU DLA TEJ SALI',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 12,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppColors.warning.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: AppColors.warning.withValues(alpha: 0.6)),
                              ),
                              child: isSavingLimit
                                  ? const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.warning),
                                    )
                                  : Text(
                                      '${currentLimitSec ~/ 60} min',
                                      style: const TextStyle(
                                        color: AppColors.warning,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          'Wybierz limit alertu dla tej sali (zmienia także aktywną sesję):',
                          style: TextStyle(color: Colors.white60, fontSize: 11),
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final m in [15, 30, 45, 60, 90, 120]) ...[
                              _buildLimitChip(
                                label: '$m min',
                                selected: currentLimitSec == m * 60,
                                onTap: isSavingLimit
                                    ? null
                                    : () async {
                                        final newSec = m * 60;
                                        if (newSec == currentLimitSec) return;
                                        setSheetState(() {
                                          currentLimitSec = newSec;
                                          isSavingLimit = true;
                                        });
                                        await RoomDatabaseHelper.instance.updateRoomAlertLimit(room.number, newSec);
                                        final updatedRoom = room.copyWith(defaultAlertLimitSeconds: newSec);
                                        if (onLimitChanged != null) {
                                          await onLimitChanged(updatedRoom, newSec);
                                        }
                                        if (context.mounted) {
                                          setSheetState(() => isSavingLimit = false);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Ustawiono limit dla sali ${room.number}: $m min'),
                                              duration: const Duration(seconds: 2),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      },
                              ),
                            ],
                            // Custom Chip
                            InkWell(
                              onTap: isSavingLimit
                                  ? null
                                  : () async {
                                      final ctrl = TextEditingController(text: '${currentLimitSec ~/ 60}');
                                      final chosenMin = await showDialog<int>(
                                        context: context,
                                        builder: (dCtx) => AlertDialog(
                                          backgroundColor: const Color(0xFF141414),
                                          title: Text(
                                            'Własny limit czasu (sala ${room.number})',
                                            style: const TextStyle(color: Colors.white, fontSize: 16),
                                          ),
                                          content: TextField(
                                            controller: ctrl,
                                            keyboardType: TextInputType.number,
                                            autofocus: true,
                                            style: const TextStyle(color: Colors.white),
                                            decoration: const InputDecoration(
                                              labelText: 'Czas w minutach (1 - 480)',
                                              labelStyle: TextStyle(color: Colors.white70),
                                              suffixText: 'min',
                                              suffixStyle: TextStyle(color: Colors.white60),
                                              enabledBorder: UnderlineInputBorder(
                                                borderSide: BorderSide(color: AppColors.warning),
                                              ),
                                              focusedBorder: UnderlineInputBorder(
                                                borderSide: BorderSide(color: AppColors.warning, width: 2),
                                              ),
                                            ),
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () => Navigator.of(dCtx).pop(),
                                              child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
                                            ),
                                            ElevatedButton(
                                              onPressed: () {
                                                final val = int.tryParse(ctrl.text.trim());
                                                if (val != null && val >= 1 && val <= 480) {
                                                  Navigator.of(dCtx).pop(val);
                                                }
                                              },
                                              style: ElevatedButton.styleFrom(
                                                backgroundColor: AppColors.warning,
                                                foregroundColor: Colors.black87,
                                              ),
                                              child: const Text('Zapisz'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (chosenMin != null && chosenMin > 0) {
                                        final newSec = chosenMin * 60;
                                        setSheetState(() {
                                          currentLimitSec = newSec;
                                          isSavingLimit = true;
                                        });
                                        await RoomDatabaseHelper.instance.updateRoomAlertLimit(room.number, newSec);
                                        final updatedRoom = room.copyWith(defaultAlertLimitSeconds: newSec);
                                        if (onLimitChanged != null) {
                                          await onLimitChanged(updatedRoom, newSec);
                                        }
                                        if (context.mounted) {
                                          setSheetState(() => isSavingLimit = false);
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(
                                              content: Text('Ustawiono limit dla sali ${room.number}: $chosenMin min'),
                                              duration: const Duration(seconds: 2),
                                              backgroundColor: Colors.green,
                                            ),
                                          );
                                        }
                                      }
                                    },
                              borderRadius: BorderRadius.circular(5),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                decoration: BoxDecoration(
                                  color: ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec)
                                      ? AppColors.warning.withValues(alpha: 0.25)
                                      : Colors.white.withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(5),
                                  border: Border.all(
                                    color: ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec)
                                        ? AppColors.warning
                                        : Colors.white12,
                                    width: ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec) ? 1.5 : 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.edit_outlined,
                                      size: 13,
                                      color: ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec)
                                          ? AppColors.warning
                                          : Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec)
                                          ? '${currentLimitSec ~/ 60}m'
                                          : 'Własny...',
                                      style: TextStyle(
                                        color: ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec)
                                            ? AppColors.warning
                                            : Colors.white70,
                                        fontWeight: ![900, 1800, 2700, 3600, 5400, 7200].contains(currentLimitSec)
                                            ? FontWeight.bold
                                            : FontWeight.w500,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Big 1-Tap Toggle Button
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await onToggleAvailability(room);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isAvailable ? AppColors.danger : AppColors.success,
                        foregroundColor: Colors.black87,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                        elevation: 4,
                      ),
                      icon: Icon(
                        isAvailable ? Icons.event_busy : Icons.check_circle_outline,
                        color: Colors.black87,
                      ),
                      label: Text(
                        isAvailable ? 'OZNACZ JAKO ZAJĘTĄ' : 'OZNACZ JAKO WOLNĄ (DOSTĘPNĄ)',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Przerwa: niedostępna, ale bez licznika czasu.
                  SizedBox(
                    width: double.infinity,
                    height: 44,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await onToggleBreak(room);
                      },
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.warning),
                        foregroundColor: AppColors.warning,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      ),
                      icon: Icon(room.isBreak ? Icons.play_arrow_rounded : Icons.coffee_outlined, size: 18),
                      label: Text(
                        room.isBreak ? 'ZAKOŃCZ PRZERWĘ' : 'OZNACZ JAKO PRZERWĘ (BEZ TIMERA)',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                    ),
                  ),

                  const SizedBox(height: 20),
                  const Divider(color: Colors.white12),
                  const SizedBox(height: 10),

                  // Description / Details
                  if (room.description.isNotEmpty) ...[
                    const Text('OPIS / WYDARZENIE', style: TextStyle(color: Colors.white54, fontSize: 11, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(room.description, style: const TextStyle(color: Colors.white, fontSize: 14)),
                    const SizedBox(height: 14),
                  ],

                  if (room.capacity > 0) ...[
                    Row(
                      children: [
                        const Icon(Icons.people_alt_outlined, color: Colors.white60, size: 16),
                        const SizedBox(width: 8),
                        Text('Pojemność: ${room.capacity} osób', style: const TextStyle(color: Colors.white70, fontSize: 13)),
                      ],
                    ),
                    const SizedBox(height: 8),
                  ],

                  if (room.customNote.isNotEmpty) ...[
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.info_outline, color: AppColors.primary, size: 16),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text('Uwagi: ${room.customNote}', style: const TextStyle(color: AppColors.primary, fontSize: 13)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],

                  const SizedBox(height: 10),

                  // Action Buttons: Edit and Delete
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onDelete();
                        },
                        icon: const Icon(Icons.delete_outline, color: AppColors.danger, size: 18),
                        label: const Text('Usuń salę', style: TextStyle(color: AppColors.danger)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          onEdit();
                        },
                        icon: const Icon(Icons.edit_outlined, size: 18),
                        label: const Text('Edytuj dane'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF000000),
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white24),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

Widget _buildLimitChip({
  required String label,
  required bool selected,
  required VoidCallback? onTap,
}) {
  return InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(5),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? AppColors.warning.withValues(alpha: 0.25) : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: selected ? AppColors.warning : Colors.white12,
          width: selected ? 1.5 : 1,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: selected ? AppColors.warning : Colors.white70,
          fontWeight: selected ? FontWeight.bold : FontWeight.w500,
          fontSize: 12,
        ),
      ),
    ),
  );
}
