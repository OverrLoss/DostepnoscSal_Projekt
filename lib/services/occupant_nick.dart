import 'package:shared_preferences/shared_preferences.dart';

/// Twoja nazwa (nick) zapisana na urządzeniu — podpisuje sale, które zajmujesz.
class OccupantNick {
  OccupantNick._();

  static const String _key = 'occupant_nick';

  static Future<String> load() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key) ?? '';
  }

  static Future<void> save(String nick) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, nick.trim());
  }
}
