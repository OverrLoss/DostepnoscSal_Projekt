import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/weather_model.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;

    try {
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinSettings = DarwinInitializationSettings();
      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: darwinSettings,
        macOS: darwinSettings,
      );

      await _notificationsPlugin.initialize(initSettings);

      // Request Android 13+ Notification Permission
      final androidImpl = _notificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.requestNotificationsPermission();
      }
    } catch (_) {
      // Platform channel not available in unit test environment
    }

    _initialized = true;
  }

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
  }) async {
    await init();

    const androidDetails = AndroidNotificationDetails(
      'storm_alerts_channel',
      'Ostrzeżenia Pogodowe i Burzowe',
      channelDescription: 'Powiadomienia o nadchodzących burzach i złej jakości powietrza',
      importance: Importance.high,
      priority: Priority.high,
      ticker: 'Ostrzeżenie pogodowe',
      icon: '@mipmap/ic_launcher',
    );

    const darwinDetails = DarwinNotificationDetails();
    const notificationDetails = NotificationDetails(
      android: androidDetails,
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    await _notificationsPlugin.show(id, title, body, notificationDetails);
  }

  Future<void> checkAndNotifySevereWeather(CityLocation city, WeatherData weather, AirQualityData aqi) async {
    // Storm Alert (Codes 95, 96, 99)
    if (weather.weatherCode == 95 || weather.weatherCode == 96 || weather.weatherCode == 99) {
      await showNotification(
        id: city.name.hashCode,
        title: '⚡ OSTRZEŻENIE PRZED BURZĄ: ${city.name}!',
        body: 'W lokalizacji ${city.name} wykryto aktywną burzę z piorunami. Zachowaj ostrożność!',
      );
    }
    // Heavy Rain / Downpour Alert (Codes 65, 82)
    else if (weather.weatherCode == 65 || weather.weatherCode == 82) {
      await showNotification(
        id: city.name.hashCode + 1,
        title: '🌧️ OSTRZEŻENIE O ULEWNYM DESZCZU: ${city.name}!',
        body: 'W lokalizacji ${city.name} występują ulewne opady deszczu.',
      );
    }

    // High Air Pollution / Bad AQI Alert
    if (aqi.aqiScore > 60) {
      await showNotification(
        id: city.name.hashCode + 2,
        title: '😷 OSTRZEŻENIE O SMOGU: ${city.name}!',
        body: 'Jakość powietrza w ${city.name} wynosi ${aqi.aqiScore} (${aqi.statusLabel}). Zalecane ograniczenie przebywania na zewnątrz.',
      );
    }
  }
}
