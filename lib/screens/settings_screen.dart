import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../services/settings_service.dart';
import '../services/database_helper.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onDatabaseChanged;

  const SettingsScreen({super.key, this.onDatabaseChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  int _contactsCount = 0;
  bool _isLoadingDb = true;

  @override
  void initState() {
    super.initState();
    _loadDbStats();
  }

  Future<void> _loadDbStats() async {
    setState(() => _isLoadingDb = true);
    final count = await DatabaseHelper.instance.getContactsCount();
    if (mounted) {
      setState(() {
        _contactsCount = count;
        _isLoadingDb = false;
      });
    }
  }

  Future<void> _seedSampleContacts() async {
    await DatabaseHelper.instance.seedSampleContacts();
    await _loadDbStats();
    widget.onDatabaseChanged?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Dodano przykładowe kontakty do bazy SQLite!'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _clearAllContacts() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF22262D),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            SizedBox(width: 10),
            Text('Wyczyść bazę danych', style: TextStyle(color: Colors.white, fontSize: 18)),
          ],
        ),
        content: const Text(
          'Czy na pewno chcesz usunąć WSZYSTKIE kontakty z lokalnej bazy SQLite?\n\nTej operacji nie można cofnąć.',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Anuluj', style: TextStyle(color: Colors.white60)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.danger),
            child: const Text('Wyczyść wszystko', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await DatabaseHelper.instance.clearAllContacts();
      await _loadDbStats();
      widget.onDatabaseChanged?.call();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Wszystkie kontakty zostały usunięte z bazy danych.'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final accent = settings.accentColor;

        return Scaffold(
          backgroundColor: const Color(0xFF1A1D22),
          appBar: AppBar(
            backgroundColor: const Color(0xFF22262D),
            elevation: 0,
            title: Row(
              children: [
                Icon(Icons.settings_outlined, color: accent, size: 22),
                const SizedBox(width: 10),
                const Text(
                  'Ustawienia',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: Colors.white,
                    fontSize: 18,
                  ),
                ),
              ],
            ),
          ),
          body: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
            children: [
              // 1. WYGLĄD I MOTYW
              _buildSectionHeader('Wygląd i motyw', Icons.palette_outlined, accent),
              const SizedBox(height: 10),
              _buildCard([
                // Theme Mode
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Text(
                    'Motyw aplikacji',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.dark,
                        label: Text('Ciemny'),
                        icon: Icon(Icons.dark_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        label: Text('Jasny'),
                        icon: Icon(Icons.light_mode_outlined),
                      ),
                      ButtonSegment(
                        value: ThemeMode.system,
                        label: Text('System'),
                        icon: Icon(Icons.brightness_auto_outlined),
                      ),
                    ],
                    selected: {settings.themeMode},
                    style: ButtonStyle(
                      backgroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return accent.withValues(alpha: 0.25);
                        }
                        return Colors.transparent;
                      }),
                      foregroundColor: WidgetStateProperty.resolveWith((states) {
                        if (states.contains(WidgetState.selected)) {
                          return accent;
                        }
                        return Colors.white70;
                      }),
                    ),
                    onSelectionChanged: (newSelection) {
                      settings.setThemeMode(newSelection.first);
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white10, height: 1),

                // Accent Color
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Text(
                    'Kolor akcentu',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Row(
                    children: [
                      _buildColorDot('green', Colors.greenAccent, 'Szmaragd', settings),
                      const SizedBox(width: 12),
                      _buildColorDot('blue', AppColors.primary, 'Mosiądz', settings),
                      const SizedBox(width: 12),
                      _buildColorDot('purple', Colors.purpleAccent, 'Fiolet', settings),
                      const SizedBox(width: 12),
                      _buildColorDot('amber', Colors.amberAccent, 'Bursztyn', settings),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // 2. DOMYŚLNE USTAWIENIA KONTAKTÓW
              _buildSectionHeader('Preferencje kontaktów', Icons.contacts_outlined, accent),
              const SizedBox(height: 10),
              _buildCard([
                // Default Category
                ListTile(
                  title: const Text('Domyślna kategoria dla nowych', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    settings.defaultCategory,
                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  trailing: DropdownButton<String>(
                    value: settings.defaultCategory,
                    dropdownColor: const Color(0xFF22262D),
                    underline: const SizedBox(),
                    icon: Icon(Icons.arrow_drop_down, color: accent),
                    items: ['Prywatny', 'Praca', 'Rodzina', 'Inne'].map((c) {
                      return DropdownMenuItem(
                        value: c,
                        child: Text(c, style: const TextStyle(color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (newVal) {
                      if (newVal != null) settings.setDefaultCategory(newVal);
                    },
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),

                // Default Sort
                ListTile(
                  title: const Text('Domyślne sortowanie listy', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text(
                    _getSortLabel(settings.defaultSort),
                    style: TextStyle(color: accent, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  trailing: DropdownButton<String>(
                    value: settings.defaultSort,
                    dropdownColor: const Color(0xFF22262D),
                    underline: const SizedBox(),
                    icon: Icon(Icons.arrow_drop_down, color: accent),
                    items: const [
                      DropdownMenuItem(value: 'lastName_asc', child: Text('Nazwisko A-Z', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'lastName_desc', child: Text('Nazwisko Z-A', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'firstName_asc', child: Text('Imię A-Z', style: TextStyle(color: Colors.white))),
                      DropdownMenuItem(value: 'newest', child: Text('Najnowsze', style: TextStyle(color: Colors.white))),
                    ],
                    onChanged: (newVal) {
                      if (newVal != null) {
                        settings.setDefaultSort(newVal);
                        widget.onDatabaseChanged?.call();
                      }
                    },
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // 3. BAZA DANYCH SQLITE
              _buildSectionHeader('Baza danych SQLite', Icons.storage_outlined, accent),
              const SizedBox(height: 10),
              _buildCard([
                ListTile(
                  leading: CircleAvatar(
                    backgroundColor: accent.withValues(alpha: 0.2),
                    child: Icon(Icons.dns, color: accent, size: 20),
                  ),
                  title: const Text('Plik bazy: address_book.db', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    _isLoadingDb
                        ? 'Wczytywanie statystyk...'
                        : 'Łącznie zapisanych kontaktów: $_contactsCount',
                    style: const TextStyle(color: Colors.white60, fontSize: 12),
                  ),
                ),
                const Divider(color: Colors.white10, height: 1),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _seedSampleContacts,
                          icon: const Icon(Icons.auto_awesome, size: 16),
                          label: const Text('Dodaj przykłady', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.white70,
                            side: const BorderSide(color: Colors.white24),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _contactsCount > 0 ? _clearAllContacts : null,
                          icon: const Icon(Icons.delete_sweep_outlined, size: 16),
                          label: const Text('Wyczyść bazę', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                            disabledForegroundColor: Colors.white24,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ]),

              const SizedBox(height: 24),

              // 4. INFORMACJE O APLIKACJI
              _buildSectionHeader('Informacje o aplikacji', Icons.info_outline, accent),
              const SizedBox(height: 10),
              _buildCard([
                const ListTile(
                  leading: Icon(Icons.phone_android, color: Colors.white70),
                  title: Text('Książka Adresowa SQLite', style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                  subtitle: Text('Wersja 1.0.0 (Kompilacja natywna)', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
                const Divider(color: Colors.white10, height: 1),
                const ListTile(
                  leading: Icon(Icons.security_outlined, color: Colors.white70),
                  title: Text('Bezpieczeństwo danych', style: TextStyle(color: Colors.white, fontSize: 14)),
                  subtitle: Text('Wszystkie kontakty przechowywane są wyłącznie lokalnie w bazie SQLite w pamięci Twojego urządzenia.', style: TextStyle(color: Colors.white60, fontSize: 12)),
                ),
              ]),

              const SizedBox(height: 40),
            ],
          ),
        );
      },
    );
  }

  String _getSortLabel(String sortKey) {
    switch (sortKey) {
      case 'lastName_desc':
        return 'Nazwisko Z-A';
      case 'firstName_asc':
        return 'Imię A-Z';
      case 'newest':
        return 'Najnowsze';
      case 'lastName_asc':
      default:
        return 'Nazwisko A-Z';
    }
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color) {
    return Row(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
          ),
        ),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF22262D),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildColorDot(String name, Color color, String label, SettingsService settings) {
    final isSelected = settings.accentColorName == name;

    return InkWell(
      onTap: () => settings.setAccentColorName(name),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? color.withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? color : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? color : Colors.white70,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
