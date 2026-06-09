<<<<<<< HEAD
=======
// Shared visual styling for the 4 noise categories so the list, map pins,
// and detail screen all use the same colors and icons.
>>>>>>> 0120550 (Update recording handling)

import 'package:flutter/material.dart';

class CategoryStyle {
  static const Map<String, Color> colors = {
<<<<<<< HEAD
    'Traffic': Color(0xFFEF4444),
    'Nature': Color(0xFF22C55E),
    'Human': Color(0xFF3B82F6),
    'Construction': Color(0xFFF59E0B),
    'Unknown': Color(0xFF94A3B8),
=======
    'Traffic': Color(0xFFEF4444),      // red
    'Nature': Color(0xFF22C55E),       // green
    'Human': Color(0xFF3B82F6),        // blue
    'Construction': Color(0xFFF59E0B), // amber
    'Unknown': Color(0xFF94A3B8),      // slate grey
>>>>>>> 0120550 (Update recording handling)
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
