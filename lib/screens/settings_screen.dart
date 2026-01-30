import 'package:flutter/material.dart';
import '../services/config_service.dart';
import '../services/update_service.dart';
import 'package:ota_update/ota_update.dart';
import '../constants/work_instructions.dart'; // Import constants

import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final ConfigService _configService = ConfigService();
  final UpdateService _updateService = UpdateService();
  String? _selectedMachine;
  bool _isLoading = true;
  bool _isCheckingUpdate = false;
  String _updateStatus = '';
  String _appVersion = '';

  final TextEditingController _workstationIdController = TextEditingController();
  final List<String> _selectedVideoIds = []; // Track selected videos

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
    final machine = await _configService.getSavedMachineType();
    final workstationId = await _configService.getWorkstationId();
    final savedVideoIds = await _configService.getEnabledVideoIds();
    final packageInfo = await PackageInfo.fromPlatform();
    
    if (mounted) {
      setState(() {
        _selectedMachine = machine;
        _workstationIdController.text = workstationId ?? '';
        _selectedVideoIds.clear();
        _selectedVideoIds.addAll(savedVideoIds);
        _appVersion = packageInfo.version;
        _isLoading = false;
      });
    }
  }

  Future<void> _saveVideoSelection() async {
    await _configService.saveEnabledVideoIds(_selectedVideoIds);
  }

  Future<void> _saveSettings(String? newValue) async {
    if (newValue != null) {
      setState(() {
        _selectedMachine = newValue;
      });
      await _configService.saveMachineType(newValue);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved as $newValue.')),
        );
      }
    }
  }

  Future<void> _saveWorkstationId() async {
    final id = _workstationIdController.text.trim();
    await _configService.saveWorkstationId(id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Workstation ID saved as "$id"')),
      );
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('App is up to date!')),
      );
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
            const Text('Release Notes:', style: TextStyle(fontWeight: FontWeight.bold)),
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
             setState(() { _isCheckingUpdate = false; _updateStatus = ''; });
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
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
                        const Text('Workstation ID (e.g. PRD-025)'),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _workstationIdController,
                                decoration: const InputDecoration(
                                  border: OutlineInputBorder(),
                                  hintText: 'Enter ID',
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _saveWorkstationId,
                              child: const Text('Save'),
                            ),
                          ],
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
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('Current Version'),
                          subtitle: Text(_appVersion.isNotEmpty ? _appVersion : 'Unknown'),
                          trailing: _isCheckingUpdate
                              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                              : ElevatedButton(
                                  onPressed: _handleCheckForUpdates,
                                  child: const Text('Check for Updates'),
                                ),
                        ),
                        if (_updateStatus.isNotEmpty && !_isCheckingUpdate)
                           Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(_updateStatus, style: const TextStyle(color: Colors.red)),
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

  const _UpdateProgressDialog({super.key, required this.stream, required this.onDone});

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
        bool isDone = snapshot.connectionState == ConnectionState.done || snapshot.hasError;
        if (snapshot.hasData && snapshot.data!.status.toString().contains('ERROR')) {
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
                if (!isDone)
                  LinearProgressIndicator(value: progress),
              ],
            ),
            actions: [
               if (isDone)
                 TextButton(onPressed: onDone, child: const Text('Close'))
            ],
          ),
        );
      },
    );
  }
}
