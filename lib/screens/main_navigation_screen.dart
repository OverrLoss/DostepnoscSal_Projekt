import 'package:flutter/material.dart';
import '../services/settings_service.dart';
import '../theme/app_theme.dart';
import 'address_book_screen.dart';
import 'settings_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({super.key});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  int _currentIndex = 0;
  final GlobalKey<AddressBookScreenState> _addressBookKey = GlobalKey<AddressBookScreenState>();

  @override
  Widget build(BuildContext context) {
    final settings = SettingsService.instance;

    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final accent = settings.accentColor;

        return Scaffold(
          body: IndexedStack(
            index: _currentIndex,
            children: [
              AddressBookScreen(key: _addressBookKey),
              SettingsScreen(
                onDatabaseChanged: () {
                  _addressBookKey.currentState?.reloadContacts();
                },
              ),
            ],
          ),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.stroke)),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              backgroundColor: Colors.transparent,
              indicatorColor: accent.withValues(alpha: 0.16),
              elevation: 0,
              onDestinationSelected: (index) {
                setState(() => _currentIndex = index);
                if (index == 0) {
                  _addressBookKey.currentState?.reloadContacts();
                }
              },
              destinations: [
                NavigationDestination(
                  icon: const Icon(Icons.contacts_outlined, color: AppColors.textSecondary),
                  selectedIcon: Icon(Icons.contacts, color: accent),
                  label: 'Kontakty',
                ),
                NavigationDestination(
                  icon: const Icon(Icons.settings_outlined, color: AppColors.textSecondary),
                  selectedIcon: Icon(Icons.settings, color: accent),
                  label: 'Ustawienia',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
