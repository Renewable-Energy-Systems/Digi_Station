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

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigService _configService = ConfigService();
  final UpdateService _updateService = UpdateService();
  final ScreenConfigService _screenConfigService =
      ScreenConfigService(); // Service instance

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
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Screen Visibility Selection
                const Text(
                  'Screen Visibility',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: AppScreen.values.map((screen) {
                      // Hide mandatory screens (Settings) - Home is now toggleable
                      if (screen == AppScreen.settings)
                        return const SizedBox.shrink();

                      final isEnabled = _enabledScreens.contains(screen);
                      return SwitchListTile(
                        title: Text(_getScreenName(screen)),
                        value: isEnabled,
                        onChanged: (val) => _toggleScreen(screen, val),
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Select Machine Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      children: ConfigService.machineUrls.entries.map((entry) {
                        return RadioListTile<String>(
                          title: Text(entry.key),
                          subtitle: Text(entry.value),
                          value: entry.key,
                          groupValue: _selectedMachine,
                          onChanged: _saveSettings,
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const SizedBox(height: 24),

                const Text(
                  'Workstation Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('Workstation ID'),
                            TextButton.icon(
                              onPressed: () => setState(() => _isManualMode = !_isManualMode),
                              icon: Icon(_isManualMode ? Icons.list_rounded : Icons.edit_rounded, size: 18),
                              label: Text(_isManualMode ? 'Show List' : 'Enter Manually', style: const TextStyle(fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        if (_fetchError != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Text(
                              _fetchError!,
                              style: const TextStyle(color: Colors.red, fontSize: 12),
                            ),
                          ),
                        if (_isFetchingWorkstations)
                          const LinearProgressIndicator()
                        else if (_isManualMode || _workstations.isEmpty)
                          Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _workstationIdController,
                                      decoration: const InputDecoration(
                                        border: OutlineInputBorder(),
                                        hintText: 'Enter ID (e.g. PRD-362)',
                                        isDense: true,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  ElevatedButton(
                                    onPressed: _saveWorkstationId,
                                    child: const Text('Save'),
                                  ),
                                  IconButton(
                                    onPressed: _loadSettings,
                                    icon: const Icon(Icons.refresh_rounded),
                                    tooltip: 'Retry Loading List',
                                  ),
                                ],
                              ),
                              if (_workstations.isEmpty && !_isFetchingWorkstations)
                                const Padding(
                                  padding: EdgeInsets.only(top: 8.0),
                                  child: Text(
                                    'Notice: List is empty. Using manual entry.',
                                    style: TextStyle(color: Colors.orange, fontSize: 11),
                                  ),
                                ),
                            ],
                          )
                        else
                          DropdownButtonFormField<String>(
                            value: _workstations.any((w) => w['id'] == _workstationIdController.text)
                                ? _workstationIdController.text
                                : null,
                            decoration: const InputDecoration(
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                            items: _workstations.map((ws) {
                              return DropdownMenuItem<String>(
                                value: ws['id'],
                                child: Text("${ws['id']} - ${ws['name']}"),
                              );
                            }).toList(),
                            onChanged: (val) {
                              if (val != null) {
                                _workstationIdController.text = val;
                                _saveWorkstationId();
                              }
                            },
                            hint: const Text('Select Workstation'),
                          ),
                        const SizedBox(height: 8),
                        Text(
                          'Source: ${ApiConstants.opsDigiBaseUrl}',
                          style: TextStyle(fontSize: 10, color: Colors.grey.shade400),
                        ),
                        const Divider(height: 32),
                        
                        // API Environment Switch
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'API Environment',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                Text(
                                  'Choose between Local and Production Server',
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                const Text('Local', style: TextStyle(fontSize: 12)),
                                Switch(
                                  value: _useProductionApi,
                                  onChanged: (val) async {
                                    await _configService.saveUseProductionApi(val);
                                    setState(() => _useProductionApi = val);
                                    _loadSettings(); // Reload workstations from new source
                                    widget.onSettingsChanged?.call();
                                  },
                                ),
                                const Text('Production', style: TextStyle(fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _useProductionApi 
                              ? 'Active: ${ApiConstants.productionOpsDigiBaseUrl}'
                              : 'Active: ${ApiConstants.opsDigiBaseUrl}',
                          style: const TextStyle(fontSize: 10, color: Colors.blueAccent),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                const Text(
                  'Video Configuration',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Card(
                  child: Column(
                    children: WorkInstructionsConstants.allWis.map((wi) {
                      final isSelected = _selectedVideoIds.contains(wi.id);
                      return CheckboxListTile(
                        title: Text(wi.title),
                        subtitle: Text(wi.id),
                        value: isSelected,
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedVideoIds.add(wi.id);
                            } else {
                              _selectedVideoIds.remove(wi.id);
                            }
                          });
                          _saveVideoSelection();
                        },
                      );
                    }).toList(),
                  ),
                ),
                const SizedBox(height: 24),

                // Update Section
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'App Updates',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Current Version'),
                          subtitle: Text(
                            _appVersion.isNotEmpty ? _appVersion : 'Unknown',
                          ),
                          trailing: _isCheckingUpdate
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : ElevatedButton(
                                  onPressed: _handleCheckForUpdates,
                                  child: const Text('Check for Updates'),
                                ),
                        ),
                        if (_updateStatus.isNotEmpty && !_isCheckingUpdate)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              _updateStatus,
                              style: const TextStyle(color: Colors.red),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
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
