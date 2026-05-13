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
        final sensorData = Map<String, dynamic>.from(j['sensor']);
        // Cache successful response
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(
          'sensor_master_cache_$param',
          json.encode(sensorData),
        );
        return sensorData;
      }
    }
  } catch (e) {
    print('fetchSensorInfoFromServerByParam error: $e');
  }

  // Fallback to cache if network request fails
  try {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getString('sensor_master_cache_$param');
    if (cached != null) {
      print('[DEBUG] using cached sensorinfo for param $param in DetSelector');
      return Map<String, dynamic>.from(json.decode(cached));
    }
  } catch (e) {
    print('fetchSensorInfoFromServerByParam cache error: $e');
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

class _DetSelectorScreenState extends State<DetSelectorScreen>
    with AutomaticKeepAliveClientMixin {
  String? selectedDet;
  bool loadingSensor = false;
  bool saving = false;
  bool _isEditingSelection = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _initSelection();
  }

  Future<void> _initSelection() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('selected_det_column');
    if (saved != null && mounted) {
      setState(() => selectedDet = saved);
      _loadSensorInfoFor(saved);
    }
  }

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
    super.build(context); // Important for KeepAlive

    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text(
          'Sensor Configuration',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        automaticallyImplyLeading: false,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.translucent,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 1. Channel Selection Card
              _buildSelectionHeader(primaryColor),
              const SizedBox(height: 16),

              // 2. Sensor Details Form
              Text(
                "SENSOR INFORMATION",
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  color: Colors.blueGrey[400],
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(height: 12),
              _buildSensorFormCard(primaryColor),

              const SizedBox(height: 24),

              // 3. Status Footer (Removed as requested)
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSelectionHeader(Color primaryColor) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [primaryColor, primaryColor.withOpacity(0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Channel - Work Station",
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
              IconButton(
                onPressed: () {
                  setState(() => _isEditingSelection = !_isEditingSelection);
                },
                icon: Icon(
                  _isEditingSelection ? Icons.close : Icons.edit_note_rounded,
                  color: Colors.white,
                  size: 28,
                ),
                tooltip: "Change Channel",
              ),
            ],
          ),
          const SizedBox(height: 4),
          if (_isEditingSelection)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
              ),
              child: DetSelector(
                apiHost: widget.apiHost,
                onChanged: (val) {
                  // Update selection but don't close edit mode automatically
                  _onDetChanged(val);
                },
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
            )
          else
            Text(
              selectedDet ?? "None Selected",
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w800,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSensorFormCard(Color primaryColor) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.blueGrey[50]!),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            _buildField(
              controller: _workstationCtrl,
              label: 'Workstation Name',
              icon: Icons.business_rounded,
              readOnly: !_isEditingSelection,
            ),
            const SizedBox(height: 12),
            _buildField(
              controller: _probeCtrl,
              label: 'Sensor ID',
              icon: Icons.sensors_rounded,
              readOnly: !_isEditingSelection,
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    controller: _calDateCtrl,
                    label: 'Calib. Date',
                    icon: Icons.calendar_today_rounded,
                    readOnly: true,
                    onTap:
                        _isEditingSelection ? () => _pickDate(_calDateCtrl) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildField(
                    controller: _calDueCtrl,
                    label: 'Calib. Due',
                    icon: Icons.event_available_rounded,
                    readOnly: true,
                    onTap:
                        _isEditingSelection ? () => _pickDate(_calDueCtrl) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildField(
                    controller: _minCtrl,
                    label: 'Min Dew Point',
                    icon: Icons.arrow_downward_rounded,
                    suffix: '°C',
                    readOnly: !_isEditingSelection,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildField(
                    controller: _maxCtrl,
                    label: 'Max Dew Point',
                    icon: Icons.arrow_upward_rounded,
                    suffix: '°C',
                    readOnly: !_isEditingSelection,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: (selectedDet == null ||
                            loadingSensor ||
                            !_isEditingSelection)
                        ? null
                        : _forceLoadFromDb,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      side: BorderSide(
                        color: _isEditingSelection
                            ? primaryColor
                            : Colors.blueGrey[200]!,
                      ),
                    ),
                    icon: loadingSensor
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.cloud_download_rounded, size: 20),
                    label: const Text('RESTORE DB'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: (selectedDet == null ||
                            saving ||
                            !_isEditingSelection)
                        ? null
                        : _saveLocalOnly,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _isEditingSelection
                          ? primaryColor
                          : Colors.blueGrey[100],
                      foregroundColor: _isEditingSelection
                          ? Colors.white
                          : Colors.blueGrey[400],
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      elevation: 0,
                    ),
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.save_rounded, size: 20),
                    label: const Text('SAVE LOCAL'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool readOnly = false,
    VoidCallback? onTap,
    String? suffix,
  }) {
    return TextFormField(
      controller: controller,
      readOnly: readOnly,
      onTap: onTap,
      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 18),
        suffixText: suffix,
        filled: true,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        fillColor: Colors.blueGrey[50]!.withOpacity(0.3),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.blue, width: 1.5),
        ),
        floatingLabelStyle: const TextStyle(
          fontWeight: FontWeight.bold,
          color: Colors.blue,
        ),
      ),
    );
  }
}
