import 'package:flutter/material.dart';
import '../models/contact_model.dart';
import '../services/database_helper.dart';
import '../services/settings_service.dart';
import '../widgets/contact_avatar.dart';
import '../theme/app_theme.dart';

class AddEditContactScreen extends StatefulWidget {
  final AddressContact? contact;

  const AddEditContactScreen({super.key, this.contact});

  @override
  State<AddEditContactScreen> createState() => _AddEditContactScreenState();
}

class _AddEditContactScreenState extends State<AddEditContactScreen> {
  final _formKey = GlobalKey<FormState>();

  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  late TextEditingController _emailController;
  late TextEditingController _streetController;
  late TextEditingController _postalCodeController;
  late TextEditingController _cityController;
  late TextEditingController _notesController;

  late String _selectedCategory;
  String? _avatar;
  bool _isSaving = false;

  final List<String> _categories = ['Prywatny', 'Praca', 'Rodzina', 'Inne'];

  @override
  void initState() {
    super.initState();
    final c = widget.contact;
    _firstNameController = TextEditingController(text: c?.firstName ?? '');
    _lastNameController = TextEditingController(text: c?.lastName ?? '');
    _phoneController = TextEditingController(text: c?.phone ?? '');
    _emailController = TextEditingController(text: c?.email ?? '');
    _streetController = TextEditingController(text: c?.street ?? '');
    _postalCodeController = TextEditingController(text: c?.postalCode ?? '');
    _cityController = TextEditingController(text: c?.city ?? '');
    _notesController = TextEditingController(text: c?.notes ?? '');
    _avatar = c?.avatar;

    _selectedCategory = c?.category ?? SettingsService.instance.defaultCategory;
    if (!_categories.contains(_selectedCategory)) {
      _selectedCategory = 'Prywatny';
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    _streetController.dispose();
    _postalCodeController.dispose();
    _cityController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.contact != null;

  Color _getCategoryColor(String category) {
    switch (category) {
      case 'Praca':
        return AppColors.warning;
      case 'Rodzina':
        return AppColors.primary;
      case 'Prywatny':
        return AppColors.primary;
      case 'Inne':
      default:
        return Colors.purpleAccent;
    }
  }

  Future<void> _pickAvatar() async {
    final result = await showAvatarPickerSheet(
      context: context,
      currentAvatar: _avatar,
    );
    if (result != null) {
      setState(() {
        _avatar = result.isEmpty ? null : result;
      });
    }
  }

  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) return;

    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();

    if (first.isEmpty && last.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Podaj przynajmniej imię lub nazwisko kontaktu!'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      if (_isEditing) {
        final updated = widget.contact!.copyWith(
          firstName: first,
          lastName: last,
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          street: _streetController.text.trim(),
          postalCode: _postalCodeController.text.trim(),
          city: _cityController.text.trim(),
          category: _selectedCategory,
          notes: _notesController.text.trim(),
          avatar: _avatar,
          clearAvatar: _avatar == null,
        );
        await DatabaseHelper.instance.updateContact(updated);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Zaktualizowano kontakt: ${updated.fullName}'),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        final newContact = AddressContact(
          firstName: first,
          lastName: last,
          phone: _phoneController.text.trim(),
          email: _emailController.text.trim(),
          street: _streetController.text.trim(),
          postalCode: _postalCodeController.text.trim(),
          city: _cityController.text.trim(),
          category: _selectedCategory,
          notes: _notesController.text.trim(),
          avatar: _avatar,
        );
        await DatabaseHelper.instance.insertContact(newContact);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Dodano nowy kontakt: ${newContact.fullName}'),
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
            content: Text('Błąd zapisu w bazie danych SQLite: $e'),
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

  Future<void> _confirmDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF121A31),
        title: const Text('Usuń kontakt', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz usunąć kontakt "${widget.contact!.fullName}" z bazy SQLite?',
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

    if (confirm == true && widget.contact?.id != null) {
      await DatabaseHelper.instance.deleteContact(widget.contact!.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usunięto kontakt: ${widget.contact!.fullName}'),
            backgroundColor: AppColors.danger,
          ),
        );
        Navigator.of(context).pop(true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = _getCategoryColor(_selectedCategory);

    return Scaffold(
      backgroundColor: const Color(0xFF0A1020),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121A31),
        elevation: 0,
        title: Text(
          _isEditing ? 'Edytuj Kontakt' : 'Nowy Kontakt',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            letterSpacing: 0.5,
            color: Colors.white,
          ),
        ),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.danger),
              tooltip: 'Usuń kontakt',
              onPressed: _isSaving ? null : _confirmDelete,
            ),
          IconButton(
            icon: _isSaving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.check, color: AppColors.primary),
            tooltip: 'Zapisz',
            onPressed: _isSaving ? null : _saveContact,
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
              // Avatar header preview & picker
              Center(
                child: Column(
                  children: [
                    ContactAvatar(
                      avatar: _avatar,
                      initials: _getInitialsPreview(),
                      categoryColor: themeColor,
                      radius: 46,
                      showEditBadge: true,
                      onTap: _pickAvatar,
                    ),
                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: _pickAvatar,
                      icon: const Icon(Icons.edit, size: 16, color: AppColors.primary),
                      label: Text(
                        _avatar != null ? 'Zmień awatar' : 'Dodaj awatar',
                        style: const TextStyle(color: AppColors.primary, fontSize: 13, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              // Category Selector Chips
              _buildSectionTitle('Kategoria'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: _categories.map((cat) {
                  final isSelected = _selectedCategory == cat;
                  final catColor = _getCategoryColor(cat);
                  return ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: catColor.withValues(alpha: 0.25),
                    backgroundColor: const Color(0xFF121A31),
                    labelStyle: TextStyle(
                      color: isSelected ? catColor : Colors.white70,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? catColor : Colors.white24,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        setState(() => _selectedCategory = cat);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),

              // Personal Information Section
              _buildSectionTitle('Dane osobowe'),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _buildTextField(
                      controller: _firstNameController,
                      label: 'Imię',
                      icon: Icons.person_outline,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _lastNameController,
                      label: 'Nazwisko',
                      icon: Icons.person,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _phoneController,
                label: 'Numer telefonu',
                icon: Icons.phone_outlined,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _emailController,
                label: 'Adres e-mail',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 24),

              // Address Section
              _buildSectionTitle('Adres zamieszkania / siedziby'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _streetController,
                label: 'Ulica i numer domu/lokalu',
                icon: Icons.home_outlined,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  SizedBox(
                    width: 130,
                    child: _buildTextField(
                      controller: _postalCodeController,
                      label: 'Kod pocztowy',
                      icon: Icons.markunread_mailbox_outlined,
                      keyboardType: TextInputType.text,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _buildTextField(
                      controller: _cityController,
                      label: 'Miejscowość / Miasto',
                      icon: Icons.location_city_outlined,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Notes Section
              _buildSectionTitle('Dodatkowe notatki'),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _notesController,
                label: 'Notatki (np. godziny kontaktu, opis)',
                icon: Icons.note_outlined,
                maxLines: 3,
              ),
              const SizedBox(height: 32),

              // Submit Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveContact,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                        )
                      : const Icon(Icons.save_outlined),
                  label: Text(
                    _isEditing ? 'ZAPISZ ZMIANY' : 'DODAJ DO BAZY DANYCH',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black87,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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

  String _getInitialsPreview() {
    final first = _firstNameController.text.trim();
    final last = _lastNameController.text.trim();
    String f = first.isNotEmpty ? first[0].toUpperCase() : '';
    String l = last.isNotEmpty ? last[0].toUpperCase() : '';
    if (f.isEmpty && l.isEmpty) return '+';
    return '$f$l';
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title.toUpperCase(),
      style: const TextStyle(
        color: Colors.white60,
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF121A31),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        maxLines: maxLines,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60),
          prefixIcon: Icon(icon, color: AppColors.primary.withValues(alpha: 0.7)),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
      ),
    );
  }
}
