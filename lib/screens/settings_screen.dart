import 'package:flutter/material.dart';
import '../config/api_constants.dart';
import '../services/config_service.dart';
import '../services/update_service.dart';
import '../services/screen_config_service.dart'; // Import new service
import 'package:ota_update/ota_update.dart';
import '../constants/work_instructions.dart';

import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  final VoidCallback? onSettingsChanged;

  const SettingsScreen({super.key, this.onSettingsChanged});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with AutomaticKeepAliveClientMixin {
  final ConfigService _configService = ConfigService();
  final UpdateService _updateService = UpdateService();
  final ScreenConfigService _screenConfigService =
      ScreenConfigService(); // Service instance

  @override
  bool get wantKeepAlive => true;

  String? _selectedMachine;
  bool _isLoading = true;
  bool _isCheckingUpdate = false;
  String _updateStatus = '';
  String _appVersion = '';
  List<Map<String, dynamic>> _workstations = [];
  bool _isFetchingWorkstations = false;
  String? _fetchError;
  bool _isManualMode = false;
  bool _useProductionApi = false;

  final TextEditingController _workstationIdController =
      TextEditingController();
  final List<String> _selectedVideoIds = [];

  // Screen Visibility State
  List<AppScreen> _enabledScreens = [];

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _workstationIdController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() {
      _isFetchingWorkstations = true;
      _fetchError = null;
    });

    try {
      // 1. Load local preferences first
      final workstationId = await _configService.getWorkstationId();
      final machine = await _configService.getSavedMachineType();
      final savedVideoIds = await _configService.getEnabledVideoIds();
      final packageInfo = await PackageInfo.fromPlatform();
      final enabledScreens = await _screenConfigService.getEnabledScreens();
      final useProductionApi = await _configService.shouldUseProductionApi();

      if (mounted) {
        setState(() {
          _selectedMachine = machine;
          _workstationIdController.text = workstationId ?? '';
          _appVersion = packageInfo.version;
          _selectedVideoIds.clear();
          _selectedVideoIds.addAll(savedVideoIds);
          _enabledScreens = enabledScreens;
          _useProductionApi = useProductionApi;
        });
      }

      // 2. Attempt network calls
      final workstations = await _configService.fetchWorkstations();

      if (mounted) {
        setState(() {
          _workstations = workstations;
          _isFetchingWorkstations = false;
          _isLoading = false;

          // Auto-enable manual mode if no workstations were fetched
          if (_workstations.isEmpty && workstationId != null && workstationId.isNotEmpty) {
            _isManualMode = true;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isFetchingWorkstations = false;
          _fetchError = "Error: $e";
          _isManualMode = true; // Fallback to manual entry
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _saveVideoSelection() async {
    await _configService.saveEnabledVideoIds(_selectedVideoIds);
  }

  Future<void> _toggleScreen(AppScreen screen, bool enabled) async {
    final newScreens = List<AppScreen>.from(
      _enabledScreens,
    ); // Create a mutable copy to avoid reference issues

    if (enabled) {
      if (!newScreens.contains(screen)) {
        newScreens.add(screen);
      }
    } else {
      newScreens.remove(screen);
    }

    setState(() {
      _enabledScreens = newScreens;
    });

    await _screenConfigService.saveEnabledScreens(_enabledScreens);

    // Notify parent to refresh
    widget.onSettingsChanged?.call();
  }

  Future<void> _saveSettings(String? newValue) async {
    if (newValue != null) {
      setState(() {
        _selectedMachine = newValue;
      });
      await _configService.saveMachineType(newValue);

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Saved as $newValue.')));
      }
    }
  }

  Future<void> _saveWorkstationId() async {
    final id = _workstationIdController.text.trim();
    await _configService.saveWorkstationId(id);
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Workstation ID saved as "$id"')));
    }
  }

  Future<void> _handleCheckForUpdates() async {
    setState(() {
      _isCheckingUpdate = true;
      _updateStatus = 'Checking GitHub...';
    });

    final info = await _updateService.checkForUpdate();

    if (!mounted) return;

    setState(() {
      _isCheckingUpdate = false;
      _updateStatus = '';
    });

    if (info != null && info['updateAvailable'] == true) {
      _showUpdateAvailableDialog(info);
    } else if (info != null && info.containsKey('error')) {
      _showErrorDialog(info['error']);
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('App is up to date!')));
    }
  }

  void _showUpdateAvailableDialog(Map<String, dynamic> info) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('New Update Available'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Version ${info['latestVersion']} is available.'),
            const SizedBox(height: 8),
            const Text(
              'Release Notes:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            Container(
              constraints: const BoxConstraints(maxHeight: 150),
              child: SingleChildScrollView(
                child: Text(info['releaseNotes'] ?? ''),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performUpdate(info['downloadUrl']);
            },
            child: const Text('Update'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String error) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update Check Failed'),
        content: Text(error),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Future<void> _performUpdate(String apkUrl) async {
    setState(() {
      _isCheckingUpdate = true;
      _updateStatus = 'Starting download...';
    });

    // Show progress dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return _UpdateProgressDialog(
          stream: _updateService.runUpdate(apkUrl),
          onDone: () {
            Navigator.pop(ctx); // Close dialog
            setState(() {
              _isCheckingUpdate = false;
              _updateStatus = '';
            });
          },
        );
      },
    );
  }

  // Helper to map enum to friendly name
  String _getScreenName(AppScreen s) {
    switch (s) {
      case AppScreen.webLogs:
        return 'Web Logs (Left)';
      case AppScreen.home:
        return 'Home Screen';
      case AppScreen.wiList:
        return 'Work Instructions (Right)';
      case AppScreen.gauge:
        return 'Gauge Screen (Right+)';
      case AppScreen.detSelector:
        return 'DET Selector (Right++)';
      case AppScreen.settings:
        return 'Settings (Right+++)';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      appBar: AppBar(
        title: const Text(
          'System Settings',
          style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
        ),
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
              children: [
                // 1. Screen Visibility
                _buildSectionHeader('LAYOUT & NAVIGATION', Icons.visibility_rounded),
                _buildCard(
                  child: Column(
                    children: AppScreen.values.map((screen) {
                      if (screen == AppScreen.settings) return const SizedBox.shrink();
                      final isEnabled = _enabledScreens.contains(screen);
                      return SwitchListTile(
                        title: Text(
                          _getScreenName(screen),
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        secondary: Icon(_getScreenIcon(screen), color: primaryColor, size: 22),
                        value: isEnabled,
                        activeColor: primaryColor,
                        onChanged: (val) => _toggleScreen(screen, val),
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // 2. Machine Configuration
                _buildSectionHeader('HARDWARE CONFIGURATION', Icons.settings_input_component_rounded),
                _buildCard(
                  child: Column(
                    children: ConfigService.machineUrls.entries.map((entry) {
                      return RadioListTile<String>(
                        title: Text(
                          entry.key,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(entry.value, style: const TextStyle(fontSize: 12)),
                        value: entry.key,
                        groupValue: _selectedMachine,
                        activeColor: primaryColor,
                        onChanged: _saveSettings,
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // 3. Workstation Configuration
                _buildSectionHeader('STATION & API SETTINGS', Icons.lan_rounded),
                _buildCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Workstation Identity',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          TextButton.icon(
                            onPressed: () => setState(() => _isManualMode = !_isManualMode),
                            icon: Icon(_isManualMode ? Icons.list_rounded : Icons.edit_rounded, size: 16),
                            label: Text(_isManualMode ? 'Select from List' : 'Manual Entry', style: const TextStyle(fontSize: 11)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      if (_fetchError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(_fetchError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
                        ),
                      if (_isFetchingWorkstations)
                        const LinearProgressIndicator()
                      else if (_isManualMode || _workstations.isEmpty)
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _workstationIdController,
                                decoration: InputDecoration(
                                  hintText: 'Enter ID (e.g. PRD-362)',
                                  filled: true,
                                  fillColor: Colors.blueGrey[50]!.withOpacity(0.5),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            ElevatedButton(
                              onPressed: _saveWorkstationId,
                              style: ElevatedButton.styleFrom(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                              child: const Text('Save'),
                            ),
                          ],
                        )
                      else
                        DropdownButtonFormField<String>(
                          value: _workstations.any((w) => w['id'] == _workstationIdController.text) ? _workstationIdController.text : null,
                          decoration: InputDecoration(
                            filled: true,
                            fillColor: Colors.blueGrey[50]!.withOpacity(0.5),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                            isDense: true,
                          ),
                          items: _workstations
                              .map((ws) => DropdownMenuItem<String>(
                                  value: ws['id'],
                                  child: Text("${ws['id']} - ${ws['name']}")))
                              .toList(),
                          onChanged: (val) {
                            if (val != null) {
                              _workstationIdController.text = val;
                              _saveWorkstationId();
                            }
                          },
                          hint: const Text('Select Workstation'),
                        ),
                      
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Divider(),
                      ),

                      const Text(
                        'API Environment',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: Colors.blueGrey[50]!.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            _buildEnvToggle(false, 'LOCAL'),
                            _buildEnvToggle(true, 'PRODUCTION'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        _useProductionApi ? ApiConstants.productionOpsDigiBaseUrl : ApiConstants.opsDigiBaseUrl,
                        style: TextStyle(fontSize: 10, color: primaryColor, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // 4. Video Configuration
                _buildSectionHeader('WORK INSTRUCTIONS', Icons.video_collection_rounded),
                _buildCard(
                  child: Column(
                    children: WorkInstructionsConstants.allWis.map((wi) {
                      final isSelected = _selectedVideoIds.contains(wi.id);
                      return CheckboxListTile(
                        title: Text(wi.title, style: const TextStyle(fontWeight: FontWeight.w500)),
                        subtitle: Text(wi.id, style: const TextStyle(fontSize: 12)),
                        value: isSelected,
                        activeColor: primaryColor,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) _selectedVideoIds.add(wi.id);
                            else _selectedVideoIds.remove(wi.id);
                          });
                          _saveVideoSelection();
                        },
                      );
                    }).toList(),
                  ),
                ),

                const SizedBox(height: 24),

                // 5. App Updates
                _buildSectionHeader('SYSTEM UPDATES', Icons.system_update_rounded),
                _buildCard(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Firmware Version', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                              Text(_appVersion.isNotEmpty ? 'Build v$_appVersion' : 'Fetching version...', style: TextStyle(color: Colors.blueGrey[400], fontSize: 13)),
                            ],
                          ),
                          if (_isCheckingUpdate)
                            const CircularProgressIndicator(strokeWidth: 3)
                          else
                            ElevatedButton.icon(
                              onPressed: _handleCheckForUpdates,
                              icon: const Icon(Icons.refresh_rounded, size: 18),
                              label: const Text('Check Now'),
                              style: ElevatedButton.styleFrom(elevation: 0, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))),
                            ),
                        ],
                      ),
                      if (_updateStatus.isNotEmpty && !_isCheckingUpdate)
                        Padding(
                          padding: const EdgeInsets.only(top: 12),
                          child: Text(_updateStatus, style: const TextStyle(color: Colors.red, fontSize: 12, fontWeight: FontWeight.w500)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
      child: Row(
        children: [
          Icon(icon, size: 16, color: Colors.blueGrey[400]),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: Colors.blueGrey[400],
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCard({required Widget child, EdgeInsetsGeometry? padding}) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: Colors.blueGrey[50]!),
      ),
      child: Padding(
        padding: padding ?? EdgeInsets.zero,
        child: child,
      ),
    );
  }

  Widget _buildEnvToggle(bool isProd, String label) {
    final active = _useProductionApi == isProd;
    final primaryColor = Theme.of(context).primaryColor;
    
    return Expanded(
      child: GestureDetector(
        onTap: () async {
          if (_useProductionApi == isProd) return;
          await _configService.saveUseProductionApi(isProd);
          setState(() => _useProductionApi = isProd);
          _loadSettings();
          widget.onSettingsChanged?.call();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: active ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: active ? [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, 2))] : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: active ? FontWeight.bold : FontWeight.w500,
              color: active ? primaryColor : Colors.blueGrey[400],
            ),
          ),
        ),
      ),
    );
  }

  IconData _getScreenIcon(AppScreen s) {
    switch (s) {
      case AppScreen.webLogs:
        return Icons.cloud_sync_rounded;
      case AppScreen.home:
        return Icons.dashboard_rounded;
      case AppScreen.wiList:
        return Icons.play_lesson_rounded;
      case AppScreen.gauge:
        return Icons.speed_rounded;
      case AppScreen.detSelector:
        return Icons.tune_rounded;
      case AppScreen.settings:
        return Icons.settings_rounded;
    }
  }
}

class _UpdateProgressDialog extends StatelessWidget {
  final Stream<OtaEvent> stream;
  final VoidCallback onDone;

  const _UpdateProgressDialog({required this.stream, required this.onDone});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<OtaEvent>(
      stream: stream,
      builder: (context, snapshot) {
        String status = "Starting download...";
        double? progress;

        if (snapshot.hasError) {
          status = "Error: ${snapshot.error}";
        } else if (snapshot.hasData) {
          final event = snapshot.data!;
          status = "${event.status} ${event.value ?? ''}";
          if (event.status == OtaStatus.DOWNLOADING) {
            progress = (int.tryParse(event.value ?? '0') ?? 0) / 100.0;
          }
          if (event.status == OtaStatus.INSTALLING) {
            progress = null; // indeterminate
            status = "Installing...";
          }
        }

        // Allow closing if stream is done or error occurred
        bool isDone =
            snapshot.connectionState == ConnectionState.done ||
            snapshot.hasError;
        if (snapshot.hasData &&
            snapshot.data!.status.toString().contains('ERROR')) {
          isDone = true;
        }

        return PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Updating App'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(status),
                const SizedBox(height: 10),
                // Hide progress bar if done
                if (!isDone) LinearProgressIndicator(value: progress),
              ],
            ),
            actions: [
              if (isDone)
                TextButton(onPressed: onDone, child: const Text('Close')),
            ],
          ),
        );
      },
    );
  }
}
