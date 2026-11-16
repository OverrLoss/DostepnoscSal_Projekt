import 'package:flutter/material.dart';
import '../models/room_model.dart';
import '../services/room_database_helper.dart';
import '../theme/app_theme.dart';

class AddEditRoomScreen extends StatefulWidget {
  final Room? room;
  final String? defaultFloor;

  const AddEditRoomScreen({super.key, this.room, this.defaultFloor});

  @override
  State<AddEditRoomScreen> createState() => _AddEditRoomScreenState();
}

class _AddEditRoomScreenState extends State<AddEditRoomScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _numberController;
  late TextEditingController _nameController;
  late TextEditingController _descriptionController;
  late TextEditingController _capacityController;
  late TextEditingController _notesController;

  late String _selectedFloor;
  late String _selectedCategory;
  late bool _isAvailable;
  late int _selectedAlertLimitMinutes;
  bool _isSaving = false;

  final List<String> _floors = ['Piętro', 'Parter', 'Garaż podziemny'];
  final List<String> _categories = [
    'Laboratorium',
    'Wykładowa',
    'EXTRAS',
    'Warsztat',
    'Wystawa',
    'Inne',
  ];

  @override
  void initState() {
    super.initState();
    final r = widget.room;
    _numberController = TextEditingController(text: r?.number ?? '');
    _nameController = TextEditingController(text: r?.name ?? '');
    _descriptionController = TextEditingController(text: r?.description ?? '');
    _capacityController = TextEditingController(text: r != null ? r.capacity.toString() : '25');
    _notesController = TextEditingController(text: r?.customNote ?? '');

    _selectedFloor = r?.floor ?? widget.defaultFloor ?? 'Piętro';
    if (!_floors.contains(_selectedFloor)) {
      _selectedFloor = 'Piętro';
    }

    _selectedCategory = r?.category ?? 'Laboratorium';
    if (!_categories.contains(_selectedCategory)) {
      _selectedCategory = 'Laboratorium';
    }

    _isAvailable = r?.isAvailable ?? true;

    final limitSec = r?.defaultAlertLimitSeconds;
    if (limitSec != null && limitSec > 0) {
      _selectedAlertLimitMinutes = limitSec ~/ 60;
    } else {
      _selectedAlertLimitMinutes = 15;
    }
  }

  @override
  void dispose() {
    _numberController.dispose();
    _nameController.dispose();
    _descriptionController.dispose();
    _capacityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.room != null;

  Future<void> _saveRoom() async {
    if (!_formKey.currentState!.validate()) return;

    final number = _numberController.text.trim();
    final name = _nameController.text.trim();
    final capacity = int.tryParse(_capacityController.text.trim()) ?? 20;
    final limitSeconds = _selectedAlertLimitMinutes * 60;

    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        final updated = widget.room!.copyWith(
          number: number,
          name: name,
          floor: _selectedFloor,
          isAvailable: _isAvailable,
          category: _selectedCategory,
          description: _descriptionController.text.trim(),
          capacity: capacity,
          customNote: _notesController.text.trim(),
          defaultAlertLimitSeconds: limitSeconds,
        );
        await RoomDatabaseHelper.instance.updateRoom(updated);
        await RoomDatabaseHelper.instance.updateRoomAlertLimit(number, limitSeconds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Zaktualizowano salę $number ($name)'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        final newRoom = Room(
          number: number,
          name: name,
          floor: _selectedFloor,
          isAvailable: _isAvailable,
          category: _selectedCategory,
          description: _descriptionController.text.trim(),
          capacity: capacity,
          customNote: _notesController.text.trim(),
          defaultAlertLimitSeconds: limitSeconds,
        );
        await RoomDatabaseHelper.instance.insertRoom(newRoom);
        await RoomDatabaseHelper.instance.updateRoomAlertLimit(number, limitSeconds);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dodano nową salę: $number ($name)'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Błąd zapisu sali w bazie: $e'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _deleteRoom() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF22262D),
        title: const Text('Usuń salę', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz usunąć salę "${widget.room!.displayName}" z bazy danych?',
          style: const TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Usuń', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm == true && widget.room?.id != null) {
      await RoomDatabaseHelper.instance.deleteRoom(widget.room!.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usunięto salę: ${widget.room!.displayName}'),
            backgroundColor: AppColors.danger,
          ),
        );
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A1D22),
      appBar: AppBar(
        backgroundColor: const Color(0xFF22262D),
        elevation: 0,
        title: Text(
          _isEditing ? 'Edycja Sali' : 'Nowa Sala',
          style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              tooltip: 'Usuń salę',
              onPressed: _isSaving ? null : _deleteRoom,
            ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, color: AppColors.success),
            tooltip: 'Zapisz',
            onPressed: _isSaving ? null : _saveRoom,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Availability Toggle Card
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _isAvailable
                      ? Colors.green.withValues(alpha: 0.15)
                      : Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isAvailable ? AppColors.success : AppColors.danger,
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _isAvailable ? Icons.check_circle : Icons.cancel,
                      color: _isAvailable ? AppColors.success : AppColors.danger,
                      size: 28,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _isAvailable ? 'SALA DOSTĘPNA (WOLNA)' : 'SALA NIEDOSTĘPNA (ZAJĘTA)',
                            style: TextStyle(
                              color: _isAvailable ? AppColors.success : AppColors.danger,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Zmień suwakiem stan dostępności',
                            style: TextStyle(color: Colors.white60, fontSize: 11),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: _isAvailable,
                      activeThumbColor: AppColors.success,
                      inactiveThumbColor: AppColors.danger,
                      onChanged: (val) {
                        setState(() => _isAvailable = val);
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
              _buildSectionTitle('Podstawowe informacje'),
              const SizedBox(height: 10),

              Row(
                children: [
                  // Number Field
                  SizedBox(
                    width: 120,
                    child: _buildTextField(
                      controller: _numberController,
                      label: 'Nr sali',
                      hint: 'np. 112, AULA',
                      icon: Icons.numbers,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Wymagany';
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Name Field
                  Expanded(
                    child: _buildTextField(
                      controller: _nameController,
                      label: 'Nazwa / Funkcja',
                      hint: 'np. Druk 3D, Wykładowa',
                      icon: Icons.meeting_room_outlined,
                      validator: (val) {
                        if (val == null || val.trim().isEmpty) return 'Podaj nazwę';
                        return null;
                      },
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Floor Selector
              _buildSectionTitle('Piętro / Kondygnacja'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _floors.map((fl) {
                  final isSelected = _selectedFloor == fl;
                  return ChoiceChip(
                    label: Text(fl),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.25),
                    backgroundColor: const Color(0xFF22262D),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primary : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isSelected ? AppColors.primary : Colors.white12),
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedFloor = fl);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Category Selector
              _buildSectionTitle('Typ sali / Kategoria'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: AppColors.primary.withValues(alpha: 0.25),
                    backgroundColor: const Color(0xFF22262D),
                    labelStyle: TextStyle(
                      color: isSelected ? AppColors.primary : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(color: isSelected ? AppColors.primary : Colors.white12),
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _selectedCategory = cat);
                    },
                  );
                }).toList(),
              ),

              const SizedBox(height: 16),

              // Room Time Limit Selector
              _buildSectionTitle('Limit czasu sesji (Alert dla sali)'),
              const SizedBox(height: 4),
              const Text(
                'Czas, po którym włącza się ostrzeżenie o przekroczeniu limitu zajętości:',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final m in [15, 30, 45, 60, 90, 120])
                    ChoiceChip(
                      label: Text('$m min'),
                      selected: _selectedAlertLimitMinutes == m,
                      selectedColor: AppColors.warning.withValues(alpha: 0.25),
                      backgroundColor: const Color(0xFF22262D),
                      labelStyle: TextStyle(
                        color: _selectedAlertLimitMinutes == m ? AppColors.warning : Colors.white70,
                        fontWeight: _selectedAlertLimitMinutes == m ? FontWeight.bold : FontWeight.normal,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                        side: BorderSide(
                          color: _selectedAlertLimitMinutes == m ? AppColors.warning : Colors.white12,
                        ),
                      ),
                      onSelected: (selected) {
                        if (selected) setState(() => _selectedAlertLimitMinutes = m);
                      },
                    ),
                  ActionChip(
                    avatar: const Icon(Icons.edit_outlined, size: 14, color: Colors.white70),
                    label: Text(
                      ![15, 30, 45, 60, 90, 120].contains(_selectedAlertLimitMinutes)
                          ? 'Własny: $_selectedAlertLimitMinutes min'
                          : 'Własny...',
                    ),
                    backgroundColor: ![15, 30, 45, 60, 90, 120].contains(_selectedAlertLimitMinutes)
                        ? AppColors.warning.withValues(alpha: 0.25)
                        : const Color(0xFF22262D),
                    labelStyle: TextStyle(
                      color: ![15, 30, 45, 60, 90, 120].contains(_selectedAlertLimitMinutes)
                          ? AppColors.warning
                          : Colors.white70,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                      side: BorderSide(
                        color: ![15, 30, 45, 60, 90, 120].contains(_selectedAlertLimitMinutes)
                            ? AppColors.warning
                            : Colors.white12,
                      ),
                    ),
                    onPressed: () async {
                      final ctrl = TextEditingController(text: '$_selectedAlertLimitMinutes');
                      final val = await showDialog<int>(
                        context: context,
                        builder: (dCtx) => AlertDialog(
                          backgroundColor: const Color(0xFF22262D),
                          title: const Text('Własny limit czasu', style: TextStyle(color: Colors.white, fontSize: 16)),
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
                            ),
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(dCtx).pop(),
                              child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                final v = int.tryParse(ctrl.text.trim());
                                if (v != null && v >= 1 && v <= 480) {
                                  Navigator.of(dCtx).pop(v);
                                }
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.warning,
                                foregroundColor: Colors.black87,
                              ),
                              child: const Text('Zatwierdź'),
                            ),
                          ],
                        ),
                      );
                      if (val != null) {
                        setState(() => _selectedAlertLimitMinutes = val);
                      }
                    },
                  ),
                ],
              ),

              const SizedBox(height: 16),
              _buildSectionTitle('Dodatkowe szczegóły'),
              const SizedBox(height: 10),

              _buildTextField(
                controller: _capacityController,
                label: 'Pojemność sali (osób)',
                hint: 'np. 30',
                icon: Icons.people_outline,
                keyboardType: TextInputType.number,
              ),

              const SizedBox(height: 12),

              _buildTextField(
                controller: _descriptionController,
                label: 'Opis / Wydarzenie / Sprzęt',
                hint: 'np. Warsztaty druku przyrostowego 3D',
                icon: Icons.notes_outlined,
                maxLines: 3,
              ),

              const SizedBox(height: 12),

              _buildTextField(
                controller: _notesController,
                label: 'Uwagi rezerwacyjne',
                hint: 'np. Wymagana wcześniejsza rejestracja',
                icon: Icons.info_outline,
                maxLines: 2,
              ),

              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveRoom,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.success,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _isEditing ? 'ZAPISZ ZMIANY' : 'DODAJ SALĘ DO BAZY',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white54,
        fontSize: 11,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.1,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    String? hint,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    String? Function(String?)? validator,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF22262D),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        validator: validator,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13),
          labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: AppColors.primary.withValues(alpha: 0.7)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
