
import 'package:flutter/material.dart';

class CategoryStyle {
  static const Map<String, Color> colors = {
    'Traffic': Color(0xFFEF4444),
    'Nature': Color(0xFF22C55E),
    'Human': Color(0xFF3B82F6),
    'Construction': Color(0xFFF59E0B),
    'Unknown': Color(0xFF94A3B8),
  };

  static const Map<String, IconData> icons = {
    'Traffic': Icons.directions_car,
    'Nature': Icons.park,
    'Human': Icons.record_voice_over,
    'Construction': Icons.construction,
    'Unknown': Icons.help_outline,
  };

  static Color colorFor(String category) =>
      colors[category] ?? colors['Unknown']!;

  static IconData iconFor(String category) =>
      icons[category] ?? icons['Unknown']!;
}
