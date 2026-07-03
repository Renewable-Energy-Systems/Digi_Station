// lib/widgets/det_selector.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../socket_service.dart';

class DetSelector extends StatefulWidget {
  final String apiHost; // e.g. http://192.168.0.77:3000
  final ValueChanged<String?>? onChanged;
  final ValueChanged<Map<String, dynamic>?>? onSensorInfo;

  const DetSelector({
    super.key,
    required this.apiHost,
    this.onChanged,
    this.onSensorInfo,
  });

  @override
  State<DetSelector> createState() => _DetSelectorState();
}

class _DetSelectorState extends State<DetSelector> {
  static const String _prefKey = "selected_det_column";

  List<String> detColumns = [];
  String? selected;
  String status = 'loading';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => status = 'loading');
    try {
      final cols = await _fetchColumns();
      // Allow ALL columns (DETs and Workstation Names) to be selectable
      final dets = cols.toList();

      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefKey);

      String? initial = saved;
      // Safety check: avoid a crash if the saved value is no longer in the list.
      if (initial != null && !dets.contains(initial)) {
        initial = null;
      }

      setState(() {
        detColumns = dets;
        selected = initial;
        status = 'ready';
      });

      // IMPORTANT: opening / viewing the selector is NOT a configuration change.
      // Do not call onChanged and do not (re)subscribe here — that would reset
      // the Home screen's live subscription and flash it "offline". Only an
      // explicit pick in the dropdown (_onUserSelected) counts as a change.
      if (selected != null) {
        // Populate the form fields for display only.
        final map = await _fetchSensorInfo(selected!);
        widget.onSensorInfo?.call(map);
      }
    } catch (e, st) {
      debugPrint('DetSelector load error: $e\n$st');
      setState(() => status = 'error');
    }
  }

  Future<List<String>> _fetchColumns() async {
    final url = Uri.parse('${widget.apiHost}/api/columns');
    final resp = await http.get(url).timeout(const Duration(seconds: 6));
    if (resp.statusCode != 200) {
      throw Exception('Columns HTTP ${resp.statusCode}');
    }
    final j = json.decode(resp.body);
    if (j is Map && j['availableColumns'] is List) {
      return (j['availableColumns'] as List).map((e) => e.toString()).toList();
    }
    return [];
  }

  Future<Map<String, dynamic>?> _fetchSensorInfo(String col) async {
    try {
      // If server supports param query, client will call by col -> server can map to ParameterNo internally.
      final uri = Uri.parse(
        '${widget.apiHost}/api/sensorinfo',
      ).replace(queryParameters: {'col': col});
      final resp = await http.get(uri).timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final j = json.decode(resp.body);
        if (j is Map && j['found'] == true && j['sensor'] is Map) {
          return Map<String, dynamic>.from(j['sensor']);
        }
      }
    } catch (e) {
      debugPrint('fetchSensorInfo error: $e');
    }
    return null;
  }

  Future<void> _onUserSelected(String? newCol) async {
    if (newCol == null) return;
    final old = selected;
    final prefs = await SharedPreferences.getInstance();

    if (old != null) {
      _sendUnsubscribe(old);
    }

    await prefs.setString(_prefKey, newCol);
    setState(() => selected = newCol);

    SocketService().subscribeDewpoint(newCol);

    widget.onChanged?.call(newCol);

    final sensorMap = await _fetchSensorInfo(newCol);
    widget.onSensorInfo?.call(sensorMap);
  }

  void _sendUnsubscribe(String col) {
    SocketService().unsubscribeDewpoint(col);
  }

  @override
  Widget build(BuildContext context) {
    if (status == 'loading') {
      return const SizedBox(
        width: 260,
        height: 44,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (status == 'error') {
      return const Text(
        'Failed to load DETs',
        style: TextStyle(color: Colors.red),
      );
    }

    return SizedBox(
      width: 260,
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          isExpanded: true,
          value: selected,
          hint: const Text('Select DET'),
          items: detColumns
              .map(
                (c) => DropdownMenuItem(
                  value: c,
                  child: Text(c, overflow: TextOverflow.ellipsis),
                ),
              )
              .toList(),
          onChanged: _onUserSelected,
        ),
      ),
    );
  }
}
