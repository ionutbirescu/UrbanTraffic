// History screen: shows this device's past recordings as a List and a Map.
// Two tabs sharing the same data, fetched once on load and on pull-to-refresh.

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:intl/intl.dart';

import 'recording_model.dart';
import 'api_service.dart';
import 'category_style.dart';
import 'detail_screen.dart';

class HistoryScreen extends StatefulWidget {
  final String deviceId;
  const HistoryScreen({super.key, required this.deviceId});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final ApiService _api = ApiService();
  List<Recording> _recordings = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _api.listRecordings(widget.deviceId);
      if (mounted) {
        setState(() {
          _recordings = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not load recordings';
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(
            'History',
            style: TextStyle(fontWeight: FontWeight.w600, letterSpacing: 1.2),
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
          bottom: const TabBar(
            indicatorColor: Colors.blueAccent,
            tabs: [
              Tab(icon: Icon(Icons.list), text: 'List'),
              Tab(icon: Icon(Icons.map), text: 'Map'),
            ],
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _load,
            ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _buildError()
                : TabBarView(
                    children: [
                      _buildList(),
                      _buildMap(),
                    ],
                  ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(_error!, style: const TextStyle(color: Colors.grey)),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: _load, child: const Text('Retry')),
        ],
      ),
    );
  }

  Widget _buildList() {
    if (_recordings.isEmpty) {
      return const Center(
        child: Text('No recordings yet', style: TextStyle(color: Colors.grey)),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _recordings.length,
        itemBuilder: (context, i) => _RecordingCard(
          recording: _recordings[i],
          onTap: () => _openDetail(_recordings[i]),
        ),
      ),
    );
  }

  Widget _buildMap() {
    // Only recordings that actually have coordinates.
    final located = _recordings.where((r) => r.lat != null && r.lon != null).toList();

    if (located.isEmpty) {
      return const Center(
        child: Text('No located recordings', style: TextStyle(color: Colors.grey)),
      );
    }

    // Center the map on the most recent located recording.
    final center = LatLng(located.first.lat!, located.first.lon!);

    return FlutterMap(
      options: MapOptions(
        initialCenter: center,
        initialZoom: 13.0,
        minZoom: 3.0,
        maxZoom: 18.0,
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.example.noise_mapper',
        ),
        MarkerLayer(
          markers: located.map((r) {
            final color = CategoryStyle.colorFor(r.dominantClass);
            return Marker(
              point: LatLng(r.lat!, r.lon!),
              width: 44,
              height: 44,
              child: GestureDetector(
                onTap: () => _openDetail(r),
                child: Icon(
                  Icons.location_on,
                  color: r.isDone && r.hasScores ? color : Colors.grey,
                  size: 40,
                  shadows: const [
                    Shadow(color: Colors.black54, blurRadius: 4, offset: Offset(0, 2)),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _openDetail(Recording r) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => DetailScreen(recordingId: r.recordingId),
      ),
    ).then((_) => _load()); // refresh in case it was deleted
  }
}

// A single recording row in the list.
class _RecordingCard extends StatelessWidget {
  final Recording recording;
  final VoidCallback onTap;

  const _RecordingCard({required this.recording, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final dominant = recording.dominantClass;
    final color = CategoryStyle.colorFor(dominant);

    String dateLabel = recording.timestamp;
    try {
      final dt = DateTime.parse(recording.timestamp).toLocal();
      dateLabel = DateFormat('EEE d MMM, HH:mm').format(dt);
    } catch (_) {}

    return Card(
      color: const Color(0xFF334155),
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              // Category icon badge
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (recording.isDone && recording.hasScores)
                      ? color.withValues(alpha: 0.2)
                      : Colors.grey.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  (recording.isDone && recording.hasScores)
                      ? CategoryStyle.iconFor(dominant)
                      : Icons.hourglass_empty,
                  color: (recording.isDone && recording.hasScores) ? color : Colors.grey,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dateLabel,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    _statusLine(),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statusLine() {
    if (recording.isPending) {
      return Row(
        children: [
          const SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 8),
          Text('Processing...', style: TextStyle(fontSize: 12, color: Colors.grey.shade400)),
        ],
      );
    }
    if (recording.isError) {
      return const Text('Classification failed',
          style: TextStyle(fontSize: 12, color: Colors.redAccent));
    }
    if (!recording.hasScores) {
      return Text('Mostly silence / no clear sound',
          style: TextStyle(fontSize: 12, color: Colors.grey.shade400));
    }
    final dominant = recording.dominantClass;
    final pct = recording.scores[dominant] ?? 0;
    return Text(
      '$dominant ${pct.toStringAsFixed(0)}%',
      style: TextStyle(
        fontSize: 12,
        color: CategoryStyle.colorFor(dominant),
        fontWeight: FontWeight.w600,
      ),
    );
  }
}
