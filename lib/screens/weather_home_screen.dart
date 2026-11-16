import 'package:flutter/material.dart';
import '../models/weather_model.dart';
import '../services/weather_service.dart';
import '../services/favorites_service.dart';
import '../services/notification_service.dart';
import '../services/widget_service.dart';

class WeatherHomeScreen extends StatefulWidget {
  const WeatherHomeScreen({super.key});

  @override
  State<WeatherHomeScreen> createState() => _WeatherHomeScreenState();
}

class _WeatherHomeScreenState extends State<WeatherHomeScreen> {
  final WeatherService _weatherService = WeatherService();
  final FavoritesService _favoritesService = FavoritesService();
  final NotificationService _notificationService = NotificationService();

  CityLocation _selectedCity = WeatherService.defaultCities.first;
  WeatherDataBundle? _bundle;
  bool _isLoading = true;
  bool _isFahrenheit = false;
  bool _isFavorite = false;
  bool _isGpsActive = false;

  List<CityLocation> _favoriteCities = [];

  final TextEditingController _searchController = TextEditingController();
  List<CityLocation> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _initApp();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _initApp() async {
    await _notificationService.init();
    await _loadFavorites();

    // 1. Try to fetch GPS Current Location on Startup
    final gpsLocation = await _weatherService.getCurrentDeviceLocation();
    if (gpsLocation != null) {
      _isGpsActive = true;
      await _loadWeatherData(gpsLocation);
    } else {
      await _loadWeatherData(_selectedCity);
    }

    // 2. Check Severe Weather Notifications for Favorite Cities in background
    _checkFavoritesSevereWeather();
  }

  Future<void> _loadFavorites() async {
    final favs = await _favoritesService.getFavorites();
    if (mounted) {
      setState(() {
        _favoriteCities = favs;
      });
    }
  }

  Future<void> _loadWeatherData(CityLocation city) async {
    setState(() {
      _selectedCity = city;
      _isLoading = true;
    });

    final bundle = await _weatherService.getWeatherData(city);
    final isFav = await _favoritesService.isFavorite(city);

    if (mounted) {
      setState(() {
        _bundle = bundle;
        _isFavorite = isFav;
        _isLoading = false;
      });

      // Check notification triggers for active city
      await _notificationService.checkAndNotifySevereWeather(
        city,
        bundle.weather,
        bundle.airQuality,
      );

      // Update Native Android Home Screen Widget
      await WidgetService.updateHomeWidget(
        city: city,
        weather: bundle.weather,
        aqi: bundle.airQuality,
        isFahrenheit: _isFahrenheit,
      );
    }
  }

  Future<void> _checkFavoritesSevereWeather() async {
    for (final city in _favoriteCities) {
      if (city.name.toLowerCase() != _selectedCity.name.toLowerCase()) {
        final bundle = await _weatherService.getWeatherData(city);
        await _notificationService.checkAndNotifySevereWeather(
          city,
          bundle.weather,
          bundle.airQuality,
        );
      }
    }
  }

  Future<void> _toggleFavorite() async {
    final newFavs = await _favoritesService.toggleFavorite(_selectedCity);
    final isFav = await _favoritesService.isFavorite(_selectedCity);
    if (mounted) {
      setState(() {
        _favoriteCities = newFavs;
        _isFavorite = isFav;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isFav
                ? 'Dodano ${_selectedCity.name} do Ulubionych ❤️'
                : 'Usunięto ${_selectedCity.name} z Ulubionych',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: isFav ? Colors.redAccent : Colors.grey[800],
        ),
      );
    }
  }

  Future<void> _onGpsButtonPressed() async {
    setState(() {
      _isLoading = true;
    });

    final gpsLocation = await _weatherService.getCurrentDeviceLocation();
    if (gpsLocation != null) {
      _isGpsActive = true;
      await _loadWeatherData(gpsLocation);
    } else {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Nie udało się pobrać lokalizacji GPS. Sprawdź uprawnienia.'),
            backgroundColor: Colors.orangeAccent,
          ),
        );
      }
    }
  }

  Future<void> _onSearchChanged(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _searchResults = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    final results = await _weatherService.searchCities(query);

    if (mounted) {
      setState(() {
        _searchResults = results;
        _isSearching = false;
      });
    }
  }

  double _displayTemp(double celsius) {
    if (_isFahrenheit) {
      return (celsius * 9 / 5) + 32;
    }
    return celsius;
  }

  String get _tempUnit => _isFahrenheit ? '°F' : '°C';

  List<Color> _getBackgroundGradient(WeatherData? weather) {
    if (weather == null) {
      return [const Color(0xFF1A1D22), const Color(0xFF22262D)];
    }

    if (!weather.isDay) {
      return [const Color(0xFF0F2027), const Color(0xFF203A43), const Color(0xFF2C5364)];
    }

    switch (weather.weatherCode) {
      case 0:
      case 1:
        return [const Color(0xFF1E3C72), const Color(0xFF2A5298)]; // Sunny Blue
      case 2:
      case 3:
        return [const Color(0xFF3A6073), const Color(0xFF3A7BD5)]; // Cloudy
      case 51:
      case 53:
      case 61:
      case 63:
      case 65:
      case 80:
        return [const Color(0xFF2C3E50), const Color(0xFF4CA1AF)]; // Rainy
      case 71:
      case 73:
      case 75:
        return [const Color(0xFF83A4D4), const Color(0xFFB6FBFF)]; // Snowy
      case 95:
      case 96:
      case 99:
        return [const Color(0xFF141E30), const Color(0xFF243B55)]; // Stormy
      default:
        return [const Color(0xFF1F1C2C), const Color(0xFF928DAB)];
    }
  }

  @override
  Widget build(BuildContext context) {
    final weather = _bundle?.weather;
    final gradientColors = _getBackgroundGradient(weather);

    return Scaffold(
      body: AnimatedContainer(
        duration: const Duration(milliseconds: 800),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Search & Top Actions Bar
              _buildSearchBar(),

              // If searching, show search results list
              if (_searchController.text.isNotEmpty)
                Expanded(child: _buildSearchResultsList())
              else if (_isLoading)
                const Expanded(
                  child: Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  ),
                )
              else
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () => _loadWeatherData(_selectedCity),
                    color: Colors.white,
                    backgroundColor: const Color(0xFF22262D),
                    child: SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // GPS & Favorites Chips Row
                          _buildQuickCitiesRow(),
                          const SizedBox(height: 12),

                          // Severe Weather Warning Banner (If active)
                          _buildSevereWeatherBanner(),

                          // Hero Main Weather Card
                          _buildHeroWeatherCard(),
                          const SizedBox(height: 16),

                          // Air Quality (AQI) Card
                          _buildAirQualityCard(),
                          const SizedBox(height: 16),

                          // Weather Metrics Grid (Humidity, Wind, Pressure, UV)
                          _buildMetricsGrid(),
                          const SizedBox(height: 16),

                          // Hourly Forecast Carousel
                          _buildHourlyForecastSection(),
                          const SizedBox(height: 16),

                          // 7-Day Forecast Section
                          _buildDailyForecastSection(),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
      child: Row(
        children: [
          Expanded(
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: TextField(
                controller: _searchController,
                style: const TextStyle(color: Colors.white),
                onChanged: _onSearchChanged,
                decoration: InputDecoration(
                  hintText: 'Szukaj miasta na świecie...',
                  hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                  prefixIcon: const Icon(Icons.search, color: Colors.white),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.white),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged('');
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // GPS Button
          IconButton.filledTonal(
            onPressed: _onGpsButtonPressed,
            icon: const Icon(Icons.my_location, color: Colors.cyanAccent),
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              padding: const EdgeInsets.all(12),
            ),
            tooltip: 'Moja lokalizacja GPS',
          ),
          const SizedBox(width: 4),

          // °C / °F Unit Toggle Button
          InkWell(
            onTap: () {
              setState(() {
                _isFahrenheit = !_isFahrenheit;
              });
            },
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
              ),
              child: Text(
                _isFahrenheit ? '°F' : '°C',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchResultsList() {
    if (_isSearching) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.white),
      );
    }

    if (_searchResults.isEmpty) {
      return const Center(
        child: Text(
          'Brak wyników wyszukiwania',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      );
    }

    return ListView.builder(
      itemCount: _searchResults.length,
      padding: const EdgeInsets.all(16),
      itemBuilder: (context, index) {
        final city = _searchResults[index];
        return Card(
          color: Colors.black.withValues(alpha: 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          child: ListTile(
            leading: const Icon(Icons.location_city, color: Colors.white70),
            title: Text(
              city.name,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              city.regionSubtitle,
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
            trailing: const Icon(Icons.arrow_forward_ios, size: 16, color: Colors.white54),
            onTap: () {
              _searchController.clear();
              setState(() {
                _searchResults = [];
              });
              _loadWeatherData(city);
            },
          ),
        );
      },
    );
  }

  Widget _buildQuickCitiesRow() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Favorites Section
        if (_favoriteCities.isNotEmpty) ...[
          const Padding(
            padding: EdgeInsets.only(bottom: 6.0),
            child: Text(
              'ULUBIONE MIASTA ❤️',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 11,
                fontWeight: FontWeight.bold,
                letterSpacing: 1,
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: _favoriteCities.map((city) {
                final isSelected = city.name.toLowerCase() == _selectedCity.name.toLowerCase();
                return Padding(
                  padding: const EdgeInsets.only(right: 8.0),
                  child: ChoiceChip(
                    avatar: const Icon(Icons.favorite, size: 14, color: Colors.redAccent),
                    label: Text(city.name),
                    selected: isSelected,
                    selectedColor: Colors.redAccent.withValues(alpha: 0.4),
                    backgroundColor: Colors.black.withValues(alpha: 0.3),
                    labelStyle: TextStyle(
                      color: Colors.white,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: BorderSide(
                        color: isSelected ? Colors.redAccent : Colors.white24,
                      ),
                    ),
                    onSelected: (selected) {
                      if (selected) {
                        _loadWeatherData(city);
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Default Popular Cities Section
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: WeatherService.defaultCities.map((city) {
              final isSelected = city.name.toLowerCase() == _selectedCity.name.toLowerCase();
              return Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: ChoiceChip(
                  label: Text(city.name),
                  selected: isSelected,
                  selectedColor: Colors.white.withValues(alpha: 0.35),
                  backgroundColor: Colors.black.withValues(alpha: 0.2),
                  labelStyle: TextStyle(
                    color: Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected ? Colors.white : Colors.white24,
                    ),
                  ),
                  onSelected: (selected) {
                    if (selected) {
                      _loadWeatherData(city);
                    }
                  },
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildSevereWeatherBanner() {
    final weather = _bundle?.weather;
    if (weather == null) return const SizedBox();

    bool isStorm = weather.weatherCode == 95 || weather.weatherCode == 96 || weather.weatherCode == 99;
    bool isHeavyRain = weather.weatherCode == 65 || weather.weatherCode == 82;

    if (!isStorm && !isHeavyRain) return const SizedBox();

    final title = isStorm ? '⛈️ OSTRZEŻENIE PRZED BURZĄ' : '🌧️ OSTRZEŻENIE O ULEWIE';
    final desc = isStorm
        ? 'W tej lokalizacji wykryto aktywną burzę z piorunami! Unikaj otwartych przestrzeni.'
        : 'Występują ulewne opady deszczu. Możliwe lokalne podtopienia.';

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.redAccent.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(color: Colors.red, blurRadius: 8, spreadRadius: 1),
        ],
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, size: 36, color: Colors.amberAccent),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHeroWeatherCard() {
    final weather = _bundle?.weather;
    if (weather == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.2),
            blurRadius: 16,
            offset: const Offset(0, 8),
          )
        ],
      ),
      child: Column(
        children: [
          // City Name & Favorite Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const SizedBox(width: 40), // Spacer for center alignment
              Expanded(
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isGpsActive)
                          const Padding(
                            padding: EdgeInsets.only(right: 6.0),
                            child: Icon(Icons.my_location, color: Colors.cyanAccent, size: 20),
                          ),
                        Flexible(
                          child: Text(
                            _selectedCity.name.toUpperCase(),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.5,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_selectedCity.regionSubtitle.isNotEmpty)
                      Text(
                        _selectedCity.regionSubtitle,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 12,
                        ),
                        textAlign: TextAlign.center,
                      ),
                  ],
                ),
              ),
              IconButton(
                onPressed: _toggleFavorite,
                icon: Icon(
                  _isFavorite ? Icons.favorite : Icons.favorite_border,
                  color: _isFavorite ? Colors.redAccent : Colors.white60,
                  size: 28,
                ),
                tooltip: _isFavorite ? 'Usuń z Ulubionych' : 'Dodaj do Ulubionych',
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Weather Icon & Temperature
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  weather.conditionIcon,
                  size: 72,
                  color: Colors.amberAccent,
                ),
                const SizedBox(width: 16),
                Text(
                  '${_displayTemp(weather.temperature).round()}$_tempUnit',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 56,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Condition Text (e.g. Słonecznie)
          Text(
            weather.conditionText,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 12),

          // High / Low / Feels Like (Wrap prevents horizontal overflow)
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 10,
            runSpacing: 4,
            children: [
              Text(
                'Odczuwalna: ${_displayTemp(weather.feelsLike).round()}$_tempUnit',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              Text(
                '•  Max: ${_displayTemp(weather.tempMax).round()}$_tempUnit',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
              Text(
                '•  Min: ${_displayTemp(weather.tempMin).round()}$_tempUnit',
                style: TextStyle(color: Colors.white.withValues(alpha: 0.8), fontSize: 13),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildAirQualityCard() {
    final aqi = _bundle?.airQuality;
    if (aqi == null) return const SizedBox();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: aqi.statusColor.withValues(alpha: 0.5), width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Row(
                  children: [
                    Icon(Icons.air, color: Colors.cyanAccent),
                    SizedBox(width: 8),
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerLeft,
                        child: Text(
                          'JAKOŚĆ POWIETRZA (AQI)',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                decoration: BoxDecoration(
                  color: aqi.statusColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: aqi.statusColor),
                ),
                child: Text(
                  aqi.statusLabel,
                  style: TextStyle(
                    color: aqi.statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // AQI Score & PM2.5 / PM10 metrics
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildAqiMetricTile('Indeks AQI', '${aqi.aqiScore}', aqi.statusColor),
              _buildAqiMetricTile('PM2.5', '${aqi.pm2_5.toStringAsFixed(1)} µg/m³', Colors.white),
              _buildAqiMetricTile('PM10', '${aqi.pm10.toStringAsFixed(1)} µg/m³', Colors.white),
              _buildAqiMetricTile('NO2', '${aqi.no2.toStringAsFixed(1)} µg/m³', Colors.white),
            ],
          ),
          const SizedBox(height: 14),

          // Health recommendation box
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Icon(Icons.info_outline, color: Colors.white70, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    aqi.healthRecommendation,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAqiMetricTile(String label, String value, Color valueColor) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          const SizedBox(height: 4),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              style: TextStyle(
                color: valueColor,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid() {
    final weather = _bundle?.weather;
    if (weather == null) return const SizedBox();

    return GridView.count(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      crossAxisCount: 2,
      childAspectRatio: 2.2,
      crossAxisSpacing: 12,
      mainAxisSpacing: 12,
      children: [
        _buildMetricCard(
          icon: Icons.water_drop,
          title: 'Wilgotność',
          value: '${weather.humidity}%',
          iconColor: Colors.blueAccent,
        ),
        _buildMetricCard(
          icon: Icons.air,
          title: 'Wiatr',
          value: '${weather.windSpeed.round()} km/h',
          iconColor: Colors.cyanAccent,
        ),
        _buildMetricCard(
          icon: Icons.compress,
          title: 'Ciśnienie',
          value: '${weather.pressure} hPa',
          iconColor: Colors.orangeAccent,
        ),
        _buildMetricCard(
          icon: Icons.wb_sunny_outlined,
          title: 'Indeks UV',
          value: weather.uvIndex.toStringAsFixed(1),
          iconColor: Colors.amberAccent,
        ),
      ],
    );
  }

  Widget _buildMetricCard({
    required IconData icon,
    required String title,
    required String value,
    required Color iconColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 26),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white60, fontSize: 11),
                ),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ),
    );
  }

  Widget _buildHourlyForecastSection() {
    final hourly = _bundle?.hourlyForecast ?? [];
    if (hourly.isEmpty) return const SizedBox();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PROGNOZA GODZINOWA (24H)',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 115,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: hourly.length,
            itemBuilder: (context, index) {
              final item = hourly[index];
              final hourStr = '${item.time.hour.toString().padLeft(2, '0')}:00';
              return Container(
                width: 75,
                margin: const EdgeInsets.only(right: 10),
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      hourStr,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                    Icon(item.icon, color: Colors.amberAccent, size: 28),
                    Text(
                      '${_displayTemp(item.temp).round()}$_tempUnit',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildDailyForecastSection() {
    final daily = _bundle?.dailyForecast ?? [];
    if (daily.isEmpty) return const SizedBox();

    final List<String> dayNames = [
      'Poniedziałek',
      'Wtorek',
      'Środa',
      'Czwartek',
      'Piątek',
      'Sobota',
      'Niedziela'
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'PROGNOZA NA 7 DNI',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.2,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
          ),
          child: Column(
            children: List.generate(daily.length, (index) {
              final item = daily[index];
              String dayText = dayNames[(item.date.weekday - 1) % 7];
              if (index == 0) dayText = 'Dzisiaj';
              if (index == 1) dayText = 'Jutro';

              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        dayText,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                          fontSize: 14,
                        ),
                      ),
                    ),
                    Icon(item.icon, color: Colors.amberAccent, size: 24),
                    Row(
                      children: [
                        Text(
                          '${_displayTemp(item.tempMax).round()}$_tempUnit',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${_displayTemp(item.tempMin).round()}$_tempUnit',
                          style: const TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
          ),
        ),
      ],
    );
  }
}
