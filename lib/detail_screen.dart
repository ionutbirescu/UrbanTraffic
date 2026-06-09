// Detail screen for a single recording: fetches the full record (with weather +
// wrapped classification), shows the 4-class breakdown, weather, GPS, and timestamp.
// Polls for status if the recording is still PENDING.

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import 'recording_model.dart';
import 'api_service.dart';
import 'category_style.dart';

class DetailScreen extends StatefulWidget {
  final String recordingId;
  const DetailScreen({super.key, required this.recordingId});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  final ApiService _api = ApiService();
  Recording? _recording;
  bool _loading = true;
  String? _error;
  Timer? _pollTimer;
  int _pollCount = 0;
<<<<<<< HEAD
=======
  bool _showRaw = false; // expand/collapse the raw YAMNet panel
>>>>>>> 0120550 (Update recording handling)

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final rec = await _api.getRecording(widget.recordingId);
      if (!mounted) return;
      setState(() {
        _recording = rec;
        _loading = false;
      });
      // If still processing, start polling for the result.
      if (rec.isPending) _startPolling();
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load recording';
          _loading = false;
        });
      }
    }
  }

  void _startPolling() {
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (t) async {
      _pollCount++;
      if (_pollCount > 12) {
        // ~1 minute of polling, give up gracefully
        t.cancel();
        return;
      }
      try {
        final rec = await _api.getRecording(widget.recordingId);
        if (!mounted) return;
        if (!rec.isPending) {
          setState(() => _recording = rec);
          t.cancel();
        }
      } catch (_) {
        // ignore transient errors, keep polling
      }
    });
  }

  Future<void> _delete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete recording?'),
        content: const Text('This permanently removes the recording and its data.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await _api.deleteRecording(widget.recordingId);
        if (mounted) Navigator.pop(context);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Delete failed')),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recording Detail',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          if (_recording != null)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: Colors.redAccent),
              onPressed: _delete,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
<<<<<<< HEAD
          ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
          : _buildContent(),
=======
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.grey)))
              : _buildContent(),
>>>>>>> 0120550 (Update recording handling)
    );
  }

  Widget _buildContent() {
    final r = _recording!;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _timestampHeader(r),
          const SizedBox(height: 20),
          _classificationCard(r),
          const SizedBox(height: 16),
          if (r.weather != null) _weatherCard(r.weather!),
          const SizedBox(height: 16),
          _locationCard(r),
        ],
      ),
    );
  }

  Widget _timestampHeader(Recording r) {
    String label = r.timestamp;
    try {
      final dt = DateTime.parse(r.timestamp).toLocal();
      label = DateFormat('EEEE d MMMM yyyy, HH:mm').format(dt);
    } catch (_) {}
    return Text(
      label,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
    );
  }

  Widget _classificationCard(Recording r) {
    return _card(
      title: 'Classification',
      child: r.isPending
          ? const Padding(
<<<<<<< HEAD
        padding: EdgeInsets.symmetric(vertical: 12),
        child: Row(children: [
          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
          SizedBox(width: 12),
          Text('Processing on AWS...', style: TextStyle(color: Colors.grey)),
        ]),
      )
          : r.isError
          ? const Text('Classification failed for this recording.',
          style: TextStyle(color: Colors.redAccent))
          : !r.hasScores
          ? const Text('No clear sound detected (mostly silence).',
          style: TextStyle(color: Colors.grey))
          : Column(
        children: ['Traffic', 'Nature', 'Human', 'Construction']
            .map((cat) => _scoreBar(cat, r.scores[cat] ?? 0))
            .toList(),
      ),
=======
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Row(children: [
                SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                SizedBox(width: 12),
                Text('Processing on AWS...', style: TextStyle(color: Colors.grey)),
              ]),
            )
          : r.isError
              ? const Text('Classification failed for this recording.',
                  style: TextStyle(color: Colors.redAccent))
              : !r.hasScores
                  ? const Text('No clear sound detected (mostly silence).',
                      style: TextStyle(color: Colors.grey))
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ...['Traffic', 'Nature', 'Human', 'Construction']
                            .map((cat) => _scoreBar(cat, r.scores[cat] ?? 0)),
                        if (r.rawGuesses.isNotEmpty) _rawPanel(r),
                      ],
                    ),
    );
  }

  // Expandable panel showing the top raw YAMNet detections.
  Widget _rawPanel(Recording r) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        const Divider(color: Colors.white24, height: 1),
        InkWell(
          onTap: () => setState(() => _showRaw = !_showRaw),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  _showRaw ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: Colors.lightBlueAccent,
                ),
                const SizedBox(width: 6),
                const Text(
                  'What the AI heard (raw)',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.lightBlueAccent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showRaw)
          ...r.rawGuesses.map((g) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        g.label,
                        style: const TextStyle(fontSize: 13, color: Colors.white70),
                      ),
                    ),
                    Text(
                      '${g.score.toStringAsFixed(1)}%',
                      style: const TextStyle(
                        fontSize: 13,
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              )),
      ],
>>>>>>> 0120550 (Update recording handling)
    );
  }

  Widget _scoreBar(String category, double pct) {
    final color = CategoryStyle.colorFor(category);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(CategoryStyle.iconFor(category), size: 16, color: color),
              const SizedBox(width: 8),
              Text(category, style: const TextStyle(fontSize: 13, color: Colors.white)),
              const Spacer(),
              Text('${pct.toStringAsFixed(0)}%',
                  style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: pct / 100,
              minHeight: 8,
              backgroundColor: Colors.white.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation(color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _weatherCard(WeatherInfo w) {
    return _card(
      title: 'Weather at recording time',
      child: Column(
        children: [
<<<<<<< HEAD
          if (w.tempC != null) _weatherRow(Icons.thermostat, 'Temperature', '${w.tempC!.toStringAsFixed(1)}Â°C'),
=======
          if (w.tempC != null) _weatherRow(Icons.thermostat, 'Temperature', '${w.tempC!.toStringAsFixed(1)}°C'),
>>>>>>> 0120550 (Update recording handling)
          if (w.condition != null) _weatherRow(Icons.wb_cloudy, 'Condition', w.condition!),
          if (w.windKph != null) _weatherRow(Icons.air, 'Wind', '${w.windKph!.toStringAsFixed(1)} km/h ${w.windDir ?? ''}'),
          if (w.precipMm != null) _weatherRow(Icons.water_drop, 'Precipitation', '${w.precipMm!.toStringAsFixed(1)} mm'),
          if (w.humidity != null) _weatherRow(Icons.opacity, 'Humidity', '${w.humidity}%'),
        ],
      ),
    );
  }

  Widget _weatherRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          Icon(icon, size: 18, color: Colors.blueAccent),
          const SizedBox(width: 10),
          Text(label, style: TextStyle(fontSize: 13, color: Colors.grey.shade400)),
          const Spacer(),
          Text(value, style: const TextStyle(fontSize: 13, color: Colors.white, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _locationCard(Recording r) {
    final hasLoc = r.lat != null && r.lon != null;
    return _card(
      title: 'Location',
      child: hasLoc
          ? InkWell(
<<<<<<< HEAD
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => _SingleRecordingMap(
                lat: r.lat!,
                lon: r.lon!,
                category: r.dominantClass,
                hasScores: r.isDone && r.hasScores,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              const Icon(Icons.map, size: 18, color: Colors.lightBlueAccent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '${r.lat!.toStringAsFixed(6)}, ${r.lon!.toStringAsFixed(6)}',
                  style: const TextStyle(
                    fontSize: 14,
                    color: Colors.lightBlueAccent,
                    decoration: TextDecoration.underline,
                    decorationColor: Colors.lightBlueAccent,
                  ),
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
            ],
          ),
        ),
      )
=======
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => _SingleRecordingMap(
                      lat: r.lat!,
                      lon: r.lon!,
                      category: r.dominantClass,
                      hasScores: r.isDone && r.hasScores,
                    ),
                  ),
                );
              },
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    const Icon(Icons.map, size: 18, color: Colors.lightBlueAccent),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '${r.lat!.toStringAsFixed(6)}, ${r.lon!.toStringAsFixed(6)}',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.lightBlueAccent,
                          decoration: TextDecoration.underline,
                          decorationColor: Colors.lightBlueAccent,
                        ),
                      ),
                    ),
                    const Icon(Icons.chevron_right, color: Colors.grey, size: 18),
                  ],
                ),
              ),
            )
>>>>>>> 0120550 (Update recording handling)
          : const Text('No location data', style: TextStyle(color: Colors.grey)),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF334155),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.grey.shade400,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.8)),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}


// A small full-screen map showing a single recording's location.
class _SingleRecordingMap extends StatelessWidget {
  final double lat;
  final double lon;
  final String category;
  final bool hasScores;

  const _SingleRecordingMap({
    required this.lat,
    required this.lon,
    required this.category,
    required this.hasScores,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(lat, lon);
    final color = hasScores ? CategoryStyle.colorFor(category) : Colors.grey;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Recording Location',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2)),
        centerTitle: true,
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: FlutterMap(
        options: MapOptions(
          initialCenter: point,
          initialZoom: 16.0,
          minZoom: 3.0,
          maxZoom: 18.0,
        ),
        children: [
          TileLayer(
            urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'com.example.noise_mapper',
          ),
          MarkerLayer(
            markers: [
              Marker(
                point: point,
                width: 60,
                height: 60,
                alignment: Alignment.topCenter,
                child: Icon(
                  Icons.location_on,
                  color: color,
                  size: 50,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}