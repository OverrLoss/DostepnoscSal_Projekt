import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart' as fc;
import '../models/contact_model.dart';
import '../services/database_helper.dart';
import '../services/contacts_import_service.dart';
import '../services/settings_service.dart';
import '../widgets/contact_avatar.dart';
import 'add_edit_contact_screen.dart';
import '../theme/app_theme.dart';

class AddressBookScreen extends StatefulWidget {
  const AddressBookScreen({super.key});

  @override
  State<AddressBookScreen> createState() => AddressBookScreenState();
}

class AddressBookScreenState extends State<AddressBookScreen> {
  final TextEditingController _searchController = TextEditingController();
  List<AddressContact> _contacts = [];
  bool _isLoading = true;
  String _selectedCategory = 'Wszystkie';

  final List<String> _categories = [
    'Wszystkie',
    'Prywatny',
    'Praca',
    'Rodzina',
    'Inne',
  ];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void reloadContacts() => _loadContacts();

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final contacts = await DatabaseHelper.instance.getContacts(
      searchQuery: _searchController.text,
      category: _selectedCategory,
      orderBy: SettingsService.instance.sqlOrderBy,
    );
    if (mounted) {
      setState(() {
        _contacts = contacts;
        _isLoading = false;
      });
    }
  }

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

  void _onCategorySelected(String category) {
    setState(() {
      _selectedCategory = category;
    });
    _loadContacts();
  }

  Future<void> _navigateToAddContact() async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => const AddEditContactScreen(),
      ),
    );
    if (result == true) {
      _loadContacts();
    }
  }

  Future<void> _navigateToEditContact(AddressContact contact) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (ctx) => AddEditContactScreen(contact: contact),
      ),
    );
    if (result == true) {
      _loadContacts();
    }
  }

  Future<void> _deleteContact(AddressContact contact) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF141414),
        title: const Text('Usuń kontakt', style: TextStyle(color: Colors.white)),
        content: Text(
          'Czy na pewno chcesz usunąć "${contact.fullName}" z bazy SQLite?',
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

    if (confirmed == true && contact.id != null) {
      await DatabaseHelper.instance.deleteContact(contact.id!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Usunięto kontakt: ${contact.fullName}'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
      _loadContacts();
    }
  }

  Future<void> _startImportContacts() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: const Color(0xFF141414),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white12),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppColors.primary),
              SizedBox(width: 20),
              Text(
                'Wczytywanie kontaktów z telefonu...',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ],
          ),
        ),
      ),
    );

    List<fc.Contact> deviceContacts = [];
    try {
      deviceContacts = await ContactsImportService.instance.getDeviceContacts();
    } catch (_) {}

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pop(); // dismiss loading dialog

    if (deviceContacts.isEmpty) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: const Color(0xFF141414),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: AppColors.warning),
              SizedBox(width: 10),
              Text('Brak kontaktów', style: TextStyle(color: Colors.white, fontSize: 18)),
            ],
          ),
          content: const Text(
            'Nie udało się pobrać kontaktów z pamięci telefonu.\n\nUpewnij się, że przyznano uprawnienia do kontaktów w ustawieniach telefonu oraz że posiadasz zapisane kontakty.',
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.black87,
              ),
              child: const Text('ROZUMIEM'),
            ),
          ],
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _ContactsImportSheet(
        deviceContacts: deviceContacts,
        onImport: (selectedContacts, category) async {
          final count = await ContactsImportService.instance.importContacts(
            selectedContacts,
            defaultCategory: category,
          );
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Pomyślnie zaimportowano $count kontaktów do bazy SQLite!',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                backgroundColor: Colors.green,
                duration: const Duration(seconds: 4),
              ),
            );
            _loadContacts();
          }
        },
      ),
    );
  }

  void _showContactDetails(AddressContact contact) {
    final catColor = _getCategoryColor(contact.category);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF141414),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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

              // Header with Avatar and Name
              Row(
                children: [
                  ContactAvatar.fromContact(
                    contact: contact,
                    categoryColor: catColor,
                    radius: 32,
                    showEditBadge: true,
                    onTap: () async {
                      final newAvatar = await showAvatarPickerSheet(
                        context: context,
                        currentAvatar: contact.avatar,
                      );
                      if (newAvatar != null) {
                        final updated = contact.copyWith(
                          avatar: newAvatar.isEmpty ? null : newAvatar,
                          clearAvatar: newAvatar.isEmpty,
                        );
                        await DatabaseHelper.instance.updateContact(updated);
                        if (ctx.mounted) {
                          Navigator.of(ctx).pop();
                        }
                        _loadContacts();
                      }
                    },
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.fullName,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: catColor.withValues(alpha: 0.5)),
                          ),
                          child: Text(
                            contact.category,
                            style: TextStyle(
                              color: catColor,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Divider(color: Colors.white12),
              const SizedBox(height: 12),

              // Phone detail
              if (contact.phone.isNotEmpty)
                _buildDetailRow(Icons.phone, 'Telefon', contact.phone),

              // Email detail
              if (contact.email.isNotEmpty)
                _buildDetailRow(Icons.email, 'E-mail', contact.email),

              // Address detail
              if (contact.fullAddress.isNotEmpty)
                _buildDetailRow(Icons.location_on, 'Adres', contact.fullAddress),

              // Notes detail
              if (contact.notes.isNotEmpty)
                _buildDetailRow(Icons.notes, 'Notatki', contact.notes),

              const SizedBox(height: 20),

              // Bottom Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _deleteContact(contact);
                    },
                    icon: const Icon(Icons.delete_outline, color: AppColors.danger),
                    label: const Text('Usuń', style: TextStyle(color: AppColors.danger)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _navigateToEditContact(contact);
                    },
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('Edytuj'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black87,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF000000),
      appBar: AppBar(
        backgroundColor: const Color(0xFF141414),
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.contacts, color: AppColors.primary, size: 22),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Książka Adresowa',
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.5,
                  color: Colors.white,
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.download_for_offline_outlined, color: AppColors.primary),
            tooltip: 'Importuj kontakty z telefonu',
            onPressed: _startImportContacts,
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.primary.withValues(alpha: 0.4)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.storage, color: AppColors.primary, size: 12),
                SizedBox(width: 4),
                Text(
                  'SQLite',
                  style: TextStyle(
                    color: AppColors.primary,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Search Input
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF141414),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _searchController,
                  style: const TextStyle(color: Colors.white),
                  onChanged: (_) => _loadContacts(),
                  decoration: InputDecoration(
                    hintText: 'Szukaj po nazwisku, telefonie, mieście...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.5)),
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary),
                    suffixIcon: _searchController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white70),
                            onPressed: () {
                              _searchController.clear();
                              _loadContacts();
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                ),
              ),
            ),

            // Category Filter Row
            SizedBox(
              height: 48,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                itemCount: _categories.length,
                itemBuilder: (context, index) {
                  final cat = _categories[index];
                  final isSelected = _selectedCategory == cat;
                  final color = cat == 'Wszystkie' ? AppColors.primary : _getCategoryColor(cat);

                  return Padding(
                    padding: const EdgeInsets.only(right: 8.0),
                    child: ChoiceChip(
                      label: Text(cat),
                      selected: isSelected,
                      selectedColor: color.withValues(alpha: 0.25),
                      backgroundColor: const Color(0xFF141414),
                      labelStyle: TextStyle(
                        color: isSelected ? color : Colors.white70,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20),
                        side: BorderSide(
                          color: isSelected ? color : Colors.white12,
                        ),
                      ),
                      onSelected: (_) => _onCategorySelected(cat),
                    ),
                  );
                },
              ),
            ),

            // Counter Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18.0, vertical: 6.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'ZAPISANE KONTAKTY (${_contacts.length})',
                    style: const TextStyle(
                      color: Colors.white54,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1,
                    ),
                  ),
                  Text(
                    _selectedCategory == 'Wszystkie'
                        ? 'Wszystkie kategorie'
                        : 'Filtr: $_selectedCategory',
                    style: TextStyle(
                      color: AppColors.primary.withValues(alpha: 0.8),
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

            // Contacts List / Empty State
            Expanded(
              child: _isLoading
                  ? const Center(
                      child: CircularProgressIndicator(color: AppColors.primary),
                    )
                  : _contacts.isEmpty
                      ? _buildEmptyState()
                      : RefreshIndicator(
                          onRefresh: _loadContacts,
                          color: AppColors.primary,
                          backgroundColor: const Color(0xFF141414),
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 80),
                            itemCount: _contacts.length,
                            itemBuilder: (context, index) {
                              final contact = _contacts[index];
                              return _buildContactCard(contact);
                            },
                          ),
                        ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _navigateToAddContact,
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.black87,
        icon: const Icon(Icons.person_add),
        label: const Text(
          'NOWY KONTAKT',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final hasSearch = _searchController.text.trim().isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              hasSearch ? Icons.search_off : Icons.contact_phone_outlined,
              size: 72,
              color: Colors.white24,
            ),
            const SizedBox(height: 16),
            Text(
              hasSearch ? 'Brak wyników wyszukiwania' : 'Baza kontaktów jest pusta',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              hasSearch
                  ? 'Nie znaleziono kontaktów pasujących do "${_searchController.text}"'
                  : 'Kliknij przycisk poniżej, aby dodać swój pierwszy wpis do lokalnej bazy SQLite.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (!hasSearch)
              Wrap(
                spacing: 12,
                runSpacing: 10,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    onPressed: _navigateToAddContact,
                    icon: const Icon(Icons.add),
                    label: const Text('DODAJ KONTAKT'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.black87,
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _startImportContacts,
                    icon: const Icon(Icons.download_rounded, color: AppColors.primary),
                    label: const Text(
                      'IMPORTUJ Z TELEFONU',
                      style: TextStyle(color: AppColors.primary, fontWeight: FontWeight.bold),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContactCard(AddressContact contact) {
    final catColor = _getCategoryColor(contact.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF141414),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: InkWell(
        onTap: () => _showContactDetails(contact),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14.0),
          child: Row(
            children: [
              // Avatar
              ContactAvatar.fromContact(
                contact: contact,
                categoryColor: catColor,
                radius: 26,
              ),
              const SizedBox(width: 14),

              // Contact Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            contact.fullName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: catColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: catColor.withValues(alpha: 0.4)),
                          ),
                          child: Text(
                            contact.category,
                            style: TextStyle(
                              color: catColor,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // Phone row
                    if (contact.phone.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 2.0),
                        child: Row(
                          children: [
                            Icon(Icons.phone, size: 14, color: Colors.white.withValues(alpha: 0.6)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                contact.phone,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white70, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Address row
                    if (contact.fullAddress.isNotEmpty)
                      Row(
                        children: [
                          Icon(Icons.location_on_outlined,
                              size: 14, color: Colors.white.withValues(alpha: 0.6)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              contact.fullAddress,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.white60, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 8),

              // Action buttons (Edit & Delete popup)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, color: Colors.white54),
                color: const Color(0xFF2A2A2A),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                onSelected: (val) {
                  if (val == 'edit') {
                    _navigateToEditContact(contact);
                  } else if (val == 'delete') {
                    _deleteContact(contact);
                  }
                },
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'edit',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 18, color: AppColors.primary),
                        SizedBox(width: 10),
                        Text('Edytuj', style: TextStyle(color: Colors.white)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Row(
                      children: [
                        Icon(Icons.delete, size: 18, color: AppColors.danger),
                        SizedBox(width: 10),
                        Text('Usuń', style: TextStyle(color: AppColors.danger)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactsImportSheet extends StatefulWidget {
  final List<fc.Contact> deviceContacts;
  final Future<void> Function(List<fc.Contact> selected, String category) onImport;

  const _ContactsImportSheet({
    required this.deviceContacts,
    required this.onImport,
  });

  @override
  State<_ContactsImportSheet> createState() => _ContactsImportSheetState();
}

class _ContactsImportSheetState extends State<_ContactsImportSheet> {
  late Set<fc.Contact> _selectedContacts;
  final TextEditingController _filterController = TextEditingController();
  String _selectedCategory = 'Prywatny';
  bool _isImporting = false;

  final List<String> _importCategories = [
    'Prywatny',
    'Praca',
    'Rodzina',
    'Inne',
  ];

  @override
  void initState() {
    super.initState();
    _selectedContacts = widget.deviceContacts.toSet();
  }

  @override
  void dispose() {
    _filterController.dispose();
    super.dispose();
  }

  List<fc.Contact> get _filteredContacts {
    final query = _filterController.text.trim().toLowerCase();
    if (query.isEmpty) return widget.deviceContacts;
    return widget.deviceContacts.where((c) {
      final name = c.displayName.toLowerCase();
      final phone = c.phones.isNotEmpty ? c.phones.first.number.toLowerCase() : '';
      return name.contains(query) || phone.contains(query);
    }).toList();
  }

  void _toggleSelectAll() {
    setState(() {
      if (_selectedContacts.length == widget.deviceContacts.length) {
        _selectedContacts.clear();
      } else {
        _selectedContacts = widget.deviceContacts.toSet();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredContacts;
    final allSelected = widget.deviceContacts.isNotEmpty &&
        _selectedContacts.length == widget.deviceContacts.length;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Color(0xFF141414),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            // Drag Handle
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 12, bottom: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            // Header Row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.import_contacts_rounded, color: AppColors.primary, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Importuj z telefonu',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Zaznaczono ${_selectedContacts.length} z ${widget.deviceContacts.length}',
                          style: const TextStyle(color: Colors.white60, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white60),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            // Category selector & Select All toggle
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Kategoria dla importowanych:',
                        style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.bold),
                      ),
                      TextButton.icon(
                        style: TextButton.styleFrom(
                          padding: EdgeInsets.zero,
                          minimumSize: const Size(50, 30),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        onPressed: _toggleSelectAll,
                        icon: Icon(
                          allSelected ? Icons.deselect : Icons.select_all,
                          size: 16,
                          color: AppColors.primary,
                        ),
                        label: Text(
                          allSelected ? 'Odznacz wszystkie' : 'Zaznacz wszystkie',
                          style: const TextStyle(color: AppColors.primary, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: _importCategories.map((cat) {
                        final isSel = _selectedCategory == cat;
                        return Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: ChoiceChip(
                            label: Text(cat),
                            selected: isSel,
                            selectedColor: AppColors.primary.withValues(alpha: 0.25),
                            backgroundColor: const Color(0xFF000000),
                            labelStyle: TextStyle(
                              color: isSel ? AppColors.primary : Colors.white70,
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              fontSize: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                              side: BorderSide(
                                color: isSel ? AppColors.primary : Colors.white12,
                              ),
                            ),
                            onSelected: (_) {
                              setState(() => _selectedCategory = cat);
                            },
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 6),

            // Search in device contacts
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF000000),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
                ),
                child: TextField(
                  controller: _filterController,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Szukaj kontaktu do importu...',
                    hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                    prefixIcon: const Icon(Icons.search, color: AppColors.primary, size: 20),
                    suffixIcon: _filterController.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.white60, size: 18),
                            onPressed: () {
                              _filterController.clear();
                              setState(() {});
                            },
                          )
                        : null,
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                ),
              ),
            ),

            const Divider(color: Colors.white12, height: 16),

            // Contact list
            Expanded(
              child: filtered.isEmpty
                  ? const Center(
                      child: Text(
                        'Brak kontaktów spełniających kryteria',
                        style: TextStyle(color: Colors.white54),
                      ),
                    )
                  : ListView.builder(
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final contact = filtered[index];
                        final isSelected = _selectedContacts.contains(contact);
                        final name = contact.displayName.isNotEmpty
                            ? contact.displayName
                            : '${contact.name.first} ${contact.name.last}'.trim();
                        final phone = contact.phones.isNotEmpty
                            ? contact.phones.first.number
                            : (contact.emails.isNotEmpty ? contact.emails.first.address : 'Brak telefonu/email');

                        return CheckboxListTile(
                          value: isSelected,
                          activeColor: AppColors.primary,
                          checkColor: Colors.black,
                          dense: true,
                          secondary: CircleAvatar(
                            radius: 18,
                            backgroundColor: AppColors.primary.withValues(alpha: 0.2),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: const TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          title: Text(
                            name.isNotEmpty ? name : 'Bez nazwy',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          subtitle: Text(
                            phone,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: Colors.white54, fontSize: 12),
                          ),
                          onChanged: (bool? val) {
                            setState(() {
                              if (val == true) {
                                _selectedContacts.add(contact);
                              } else {
                                _selectedContacts.remove(contact);
                              }
                            });
                          },
                        );
                      },
                    ),
            ),

            // Bottom action buttons
            Container(
              padding: const EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Color(0xFF141414),
                border: Border(top: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isImporting ? null : () => Navigator.of(context).pop(),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: Colors.white24),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('ANULUJ'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: (_selectedContacts.isEmpty || _isImporting)
                          ? null
                          : () async {
                              setState(() => _isImporting = true);
                              await widget.onImport(
                                _selectedContacts.toList(),
                                _selectedCategory,
                              );
                              if (context.mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.black87,
                        disabledBackgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: _isImporting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black87),
                            )
                          : const Icon(Icons.download_rounded),
                      label: Text(
                        _isImporting
                            ? 'IMPORTOWANIE...'
                            : 'IMPORTUJ (${_selectedContacts.length})',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
