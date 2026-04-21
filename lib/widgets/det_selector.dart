// lib/widgets/det_selector.dart
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class DetSelector extends StatefulWidget {
  final String apiHost; // e.g. http://192.168.0.77:3000
  final WebSocketChannel? wsChannel;
  final ValueChanged<String?>? onChanged;
  final ValueChanged<Map<String, dynamic>?>? onSensorInfo;

  const DetSelector({
    super.key,
    required this.apiHost,
    this.wsChannel,
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
      // Safety check: Avoid Red Screen if saved value is no longer in the list
      if (initial != null && !dets.contains(initial)) {
        initial = null;
      }

      if (initial == null && dets.isNotEmpty) {
        initial = dets.first;
        await prefs.setString(_prefKey, initial);
      }

      setState(() {
        detColumns = dets;
        selected = initial;
        status = 'ready';
      });

      // notify parent about the initial selection (so parent sets selectedDet and UI becomes active)
      if (selected != null) {
        widget.onChanged?.call(selected);
      }

      if (selected != null && widget.wsChannel != null) {
        _sendSubscribe(selected!);
      }

      if (selected != null) {
        // optionally fetch sensor info and notify parent
        final map = await _fetchSensorInfo(selected!);
        widget.onSensorInfo?.call(map);
      }
    } catch (e, st) {
      print('DetSelector load error: $e\n$st');
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
      print('fetchSensorInfo error: $e');
    }
    return null;
  }

  Future<void> _onUserSelected(String? newCol) async {
    if (newCol == null) return;
    final old = selected;
    final prefs = await SharedPreferences.getInstance();

    if (old != null && widget.wsChannel != null) {
      _sendUnsubscribe(old);
    }

    await prefs.setString(_prefKey, newCol);
    setState(() => selected = newCol);

    if (widget.wsChannel != null) {
      _sendSubscribe(newCol);
    }

    widget.onChanged?.call(newCol);

    final sensorMap = await _fetchSensorInfo(newCol);
    widget.onSensorInfo?.call(sensorMap);
  }

  void _sendSubscribe(String col) {
    try {
      final msg = jsonEncode({'action': 'subscribe', 'col': col});
      widget.wsChannel?.sink.add(msg);
      print('DetSelector: subscribe $col');
    } catch (e) {
      print('DetSelector subscribe error: $e');
    }
  }

  void _sendUnsubscribe(String col) {
    try {
      final msg = jsonEncode({'action': 'unsubscribe', 'col': col});
      widget.wsChannel?.sink.add(msg);
      print('DetSelector: unsubscribe $col');
    } catch (e) {
      print('DetSelector unsubscribe error: $e');
    }
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
