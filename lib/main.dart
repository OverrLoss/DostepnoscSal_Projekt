import 'package:flutter/material.dart';
import 'screens/room_main_screen.dart';
import 'services/room_sync_service.dart';
import 'theme/app_theme.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await RoomSyncService.instance.init();
  runApp(const RoomAvailabilityApp());
}

class RoomAvailabilityApp extends StatelessWidget {
  const RoomAvailabilityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Dostępność Sal - Politechnika Rzeszowska',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.dark,
      home: const RoomMainScreen(),
    );
  }
}
