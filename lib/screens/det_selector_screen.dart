import 'dart:convert';
import 'package:flutter/material.dart';
import '../widgets/det_selector.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

int? detToParamNumber(String detName) {
  // use case-insensitive flag via the RegExp constructor
  final re = RegExp(r'det\s*0*(\d+)', caseSensitive: false);
  final m = re.firstMatch(detName);
  if (m == null) return null;
  return int.tryParse(m.group(1)!);
}

Future<Map<String, dynamic>?> fetchSensorInfoFromServerByParam(
  String apiHost,
  int param,
) async {
  try {
    final uri = Uri.parse(
      '$apiHost/api/sensorinfo',
    ).replace(queryParameters: {'param': param.toString()});
    final resp = await http.get(uri).timeout(const Duration(seconds: 6));
    if (resp.statusCode == 200) {
      final j = json.decode(resp.body);
      print('[DEBUG] DetSelector response: $j'); // Added debug log
      if (j is Map && j['found'] == true && j['sensor'] is Map) {
        return Map<String, dynamic>.from(j['sensor']);
      }
    }
  } catch (e) {
    print('fetchSensorInfoFromServerByParam error: $e');
  }
  return null;
}

Future<Map<String, String>?> loadLocalSensorInfo(int param) async {
  final prefs = await SharedPreferences.getInstance();
  final k = 'sensor_local_$param';
  final s = prefs.getString(k);
  if (s == null) return null;
  final j = json.decode(s) as Map<String, dynamic>;
  return j.map((k, v) => MapEntry(k, v?.toString() ?? ''));
}

Future<void> saveLocalSensorInfo(int param, Map<String, String> info) async {
  final prefs = await SharedPreferences.getInstance();
  final k = 'sensor_local_$param';
  await prefs.setString(k, json.encode(info));
}

class DetSelectorScreen extends StatefulWidget {
  final String apiHost;
  final VoidCallback? onDetChanged; // Added callback

  const DetSelectorScreen({
    super.key,
    required this.apiHost,
    this.onDetChanged, // Added to constructor
  });

  @override
  State<DetSelectorScreen> createState() => _DetSelectorScreenState();
}

class _DetSelectorScreenState extends State<DetSelectorScreen> {
  String? selectedDet;
  bool loadingSensor = false;
  bool saving = false;

  // ... (controllers remain same)

  // ...

  void _onDetChanged(String? col) async {
    // Made async
    setState(() => selectedDet = col);

    // Save immediately to prefs
    if (col != null) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('selected_det_column', col);

      // Notify parent to refresh Home Screen
      widget.onDetChanged?.call();
    }

    _loadSensorInfoFor(col);
  }

  final _workstationCtrl = TextEditingController();
  final _probeCtrl = TextEditingController();
  final _calDateCtrl = TextEditingController();
  final _calDueCtrl = TextEditingController();
  final _minCtrl = TextEditingController();
  final _maxCtrl = TextEditingController();

  @override
  void dispose() {
    _workstationCtrl.dispose();
    _probeCtrl.dispose();
    _calDateCtrl.dispose();
    _calDueCtrl.dispose();
    _minCtrl.dispose();
    _maxCtrl.dispose();
    super.dispose();
  }

  // helper: format DateTime -> "YYYY-MM-DD"
  String _formatDateOnly(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '$y-$m-$dd';
  }

  // show date picker and write ISO date (YYYY-MM-DD) into controller
  Future<void> _pickDate(TextEditingController ctrl) async {
    DateTime initial;
    try {
      // try parse existing yyyy-mm-dd or fallback to today
      final current = ctrl.text.trim();
      if (current.isNotEmpty) {
        initial = DateTime.parse(current);
      } else {
        initial = DateTime.now();
      }
    } catch (_) {
      initial = DateTime.now();
    }

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (picked != null) {
      ctrl.text = _formatDateOnly(picked);
    }
  }

  Future<void> _loadSensorInfoFor(String? col) async {
    if (col == null) return;
    setState(() => loadingSensor = true);
    try {
      final param = detToParamNumber(col);
      Map<String, dynamic>? master;
      if (param != null) {
        master = await fetchSensorInfoFromServerByParam(widget.apiHost, param);
      }

      Map<String, String>? local;
      if (param != null) {
        local = await loadLocalSensorInfo(param);
      }

      if (local != null) {
        _workstationCtrl.text = local['workstation'] ?? '';
        _probeCtrl.text = local['probeId'] ?? '';
        _calDateCtrl.text = local['calibrationDate'] ?? '';
        _calDueCtrl.text = local['calibrationDue'] ?? '';
        _minCtrl.text = local['min'] ?? '';
        _maxCtrl.text = local['max'] ?? '';
      } else if (master != null) {
        _workstationCtrl.text = master['ChannelName']?.toString() ?? '';
        _probeCtrl.text = master['SenID']?.toString() ?? '';

        String stripDate(dynamic v) {
          if (v == null) return '';
          final s = v.toString();
          final idx = s.indexOf('T');
          return idx > 0 ? s.substring(0, idx) : s;
        }

        // ensure we store/display only YYYY-MM-DD (no T00:00)
        _calDateCtrl.text = stripDate(master['Cali.Date']);
        _calDueCtrl.text = stripDate(master['Cali.Due']);
        _minCtrl.text = master['Min']?.toString() ?? '';
        _maxCtrl.text = master['Max']?.toString() ?? '';
      } else {
        _workstationCtrl.text = '';
        _probeCtrl.text = '';
        _calDateCtrl.text = '';
        _calDateCtrl.text = '';
        _calDueCtrl.text = '';
        _minCtrl.text = '';
        _maxCtrl.text = '';
      }
    } catch (e) {
      print('loadSensorInfo error: $e');
    } finally {
      if (mounted) setState(() => loadingSensor = false);
    }
  }

  Future<void> _saveLocalOnly() async {
    final col = selectedDet;
    if (col == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Select a DET first')));
      return;
    }
    final param = detToParamNumber(col);
    if (param == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Invalid DET selected')));
      return;
    }

    setState(() => saving = true);
    final Map<String, String> map = {
      'workstation': _workstationCtrl.text.trim(),
      'probeId': _probeCtrl.text.trim(),
      'calibrationDate': _calDateCtrl.text.trim(),
      'calibrationDue': _calDueCtrl.text.trim(),
      'min': _minCtrl.text.trim(),
      'max': _maxCtrl.text.trim(),
    };
    await saveLocalSensorInfo(param, map);
    // notify server (optional, server likely ignores based on current logic)
    // Removed direct widget.channel usage as per refactor

    // Notify Home Screen immediately
    widget.onDetChanged?.call();

    if (mounted) {
      setState(() => saving = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Saved locally on tablet')));
    }
  }

  Future<void> _forceLoadFromDb() async {
    final col = selectedDet;
    if (col == null) return;
    setState(() => loadingSensor = true);

    try {
      final param = detToParamNumber(col);
      if (param == null) return;

      // 1. Fetch from Server
      final master = await fetchSensorInfoFromServerByParam(
        widget.apiHost,
        param,
      );

      if (master != null) {
        // Helper to strip date
        String stripDate(dynamic v) {
          if (v == null) return '';
          final s = v.toString();
          final idx = s.indexOf('T');
          return idx > 0 ? s.substring(0, idx) : s;
        }

        // 2. Prepare data for local save (overwrite)
        final Map<String, String> newData = {
          'workstation': master['ChannelName']?.toString() ?? '',
          'probeId': master['SenID']?.toString() ?? '',
          'calibrationDate': stripDate(master['Cali.Date']),
          'calibrationDue': stripDate(master['Cali.Due']),
          'min': master['Min']?.toString() ?? '',
          'max': master['Max']?.toString() ?? '',
        };

        // 3. Overwrite local storage
        await saveLocalSensorInfo(param, newData);

        // 4. Update UI (Controllers)
        _workstationCtrl.text = newData['workstation']!;
        _probeCtrl.text = newData['probeId']!;
        _calDateCtrl.text = newData['calibrationDate']!;
        _calDueCtrl.text = newData['calibrationDue']!;
        _minCtrl.text = newData['min']!;
        _maxCtrl.text = newData['max']!;

        // 5. Notify Home Screen
        widget.onDetChanged?.call();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Restored from Server & Saved Locally'),
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not fetch from server')),
          );
        }
      }
    } catch (e) {
      print('_forceLoadFromDb error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: $e')));
      }
    } finally {
      if (mounted) setState(() => loadingSensor = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Select DET & Sensor Info'),
        automaticallyImplyLeading:
            false, // hide default back button too if they rely on keys, or just remove explicit leading
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior
            .translucent, // Ensure taps on empty space are caught
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              DetSelector(
                apiHost: widget.apiHost,
                onChanged: _onDetChanged,
                onSensorInfo: (map) {
                  if (map != null) {
                    _workstationCtrl.text =
                        map['ChannelName']?.toString() ?? '';
                    _probeCtrl.text = map['SenID']?.toString() ?? '';

                    String stripDate(dynamic v) {
                      if (v == null) return '';
                      final s = v.toString();
                      final idx = s.indexOf('T');
                      return idx > 0 ? s.substring(0, idx) : s;
                    }

                    _calDateCtrl.text = stripDate(map['Cali.Date']);
                    _calDueCtrl.text = stripDate(map['Cali.Due']);
                    _minCtrl.text = map['Min']?.toString() ?? '';
                    _maxCtrl.text = map['Max']?.toString() ?? '';
                  }
                },
              ),
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Column(
                    children: [
                      TextField(
                        controller: _workstationCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Workstation name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _probeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Probe ID',
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Calibration Date (read-only; opens date picker)
                      InkWell(
                        onTap: () => _pickDate(_calDateCtrl),
                        child: IgnorePointer(
                          child: TextField(
                            controller: _calDateCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Calibration Date',
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      // Calibration Due (read-only; opens date picker)
                      InkWell(
                        onTap: () => _pickDate(_calDueCtrl),
                        child: IgnorePointer(
                          child: TextField(
                            controller: _calDueCtrl,
                            decoration: const InputDecoration(
                              labelText: 'Calibration Due',
                              suffixIcon: Icon(Icons.calendar_today),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _minCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Min Dew Point',
                          suffixText: '°C',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _maxCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Max Dew Point',
                          suffixText: '°C',
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          ElevatedButton.icon(
                            onPressed: (selectedDet == null || loadingSensor)
                                ? null
                                : _forceLoadFromDb,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Load from PC DB'),
                          ),
                          ElevatedButton.icon(
                            onPressed: saving ? null : _saveLocalOnly,
                            icon: saving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save),
                            label: const Text('Save locally'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              Text('Selected: ${selectedDet ?? "—"}'),
            ],
          ),
        ),
      ),
    );
  }
}
