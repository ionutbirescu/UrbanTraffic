import 'package:flutter/material.dart';
import 'weather_service.dart';

class WeatherScreen extends StatelessWidget {
  final WeatherData weather;

  const WeatherScreen({super.key, required this.weather});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Weather Details',
          style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2),
        ),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Colors.blue.shade700,
                    Colors.blue.shade900,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.blue.withValues(alpha: 0.3),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Image.network(
                    weather.conditionIcon,
                    width: 100,
                    height: 100,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.cloud_outlined,
                      size: 100,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${weather.temperature.toStringAsFixed(1)}°C',
                    style: const TextStyle(
                      fontSize: 64,
                      fontWeight: FontWeight.w300,
                      color: Colors.white,
                    ),
                  ),
                  Text(
                    weather.conditionText,
                    style: const TextStyle(
                      fontSize: 20,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Feels like ${weather.feelsLike.toStringAsFixed(1)}°C',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            const Text(
              'Details',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.white,
                letterSpacing: 1.0,
              ),
            ),
            const SizedBox(height: 16),

            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 12,
              crossAxisSpacing: 12,
              childAspectRatio: 1.4,
              children: [
                _WeatherDetailCard(
                  icon: Icons.water_drop_outlined,
                  label: 'Humidity',
                  value: '${weather.humidity}%',
                  color: Colors.cyanAccent,
                ),
                _WeatherDetailCard(
                  icon: Icons.air,
                  label: 'Wind',
                  value: '${weather.windKph.toStringAsFixed(1)} km/h',
                  subtitle: weather.windDirection,
                  color: Colors.lightGreenAccent,
                ),
                _WeatherDetailCard(
                  icon: Icons.cloud_outlined,
                  label: 'Cloud cover',
                  value: '${weather.cloudCover}%',
                  color: Colors.grey.shade300,
                ),
                _WeatherDetailCard(
                  icon: Icons.umbrella_outlined,
                  label: 'Precipitation',
                  value: '${weather.precipitationMm.toStringAsFixed(1)} mm',
                  color: Colors.blueAccent,
                ),
                _WeatherDetailCard(
                  icon: Icons.compress,
                  label: 'Pressure',
                  value: '${weather.pressureMb.toStringAsFixed(0)} mb',
                  color: Colors.purpleAccent,
                ),
                _WeatherDetailCard(
                  icon: Icons.visibility_outlined,
                  label: 'Visibility',
                  value: '${weather.visibilityKm.toStringAsFixed(1)} km',
                  color: Colors.orangeAccent,
                ),
                _WeatherDetailCard(
                  icon: Icons.wb_sunny_outlined,
                  label: 'UV Index',
                  value: weather.uvIndex.toStringAsFixed(1),
                  subtitle: _uvLabel(weather.uvIndex),
                  color: Colors.yellowAccent,
                ),
                _WeatherDetailCard(
                  icon: Icons.access_time,
                  label: 'Local time',
                  value: _formatTime(weather.localTime),
                  color: Colors.pinkAccent,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Info footer
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF334155),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Colors.grey.shade400,
                    size: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Data fetched at ${_formatFetchTime(weather.fetchedAt)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade400,
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

  String _uvLabel(double uv) {
    if (uv < 3) return 'Low';
    if (uv < 6) return 'Moderate';
    if (uv < 8) return 'High';
    if (uv < 11) return 'Very high';
    return 'Extreme';
  }

  String _formatTime(String localTime) {
    // localtime e ca "2026-05-13 14:30"
    final parts = localTime.split(' ');
    if (parts.length == 2) return parts[1];
    return localTime;
  }

  String _formatFetchTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}

class _WeatherDetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String? subtitle;
  final Color color;

  const _WeatherDetailCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(icon, color: color, size: 24),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: 2),
                Text(
                  subtitle!,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}