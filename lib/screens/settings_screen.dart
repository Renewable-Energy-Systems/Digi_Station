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

  // Section indices, for deep-linking into a specific section from other screens.
  static const int sectionLayout = 0;
  static const int sectionMachine = 1;
  static const int sectionStation = 2;
  static const int sectionWorkInstructions = 3;
  static const int sectionUpdates = 4;

  @override
  State<SettingsScreen> createState() => SettingsScreenState();
}

class SettingsScreenState extends State<SettingsScreen>
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

  // Currently selected settings category in the two-pane layout.
  int _selectedSection = 0;

  // Metadata driving the sidebar navigation and content headers.
  static const List<_SettingsSection> _sections = [
    _SettingsSection(
      'Layout & Navigation',
      'Choose which screens appear and in what order',
      Icons.dashboard_customize_rounded,
    ),
    _SettingsSection(
      'Machine',
      'Select the machine connected to this station',
      Icons.settings_input_component_rounded,
    ),
    _SettingsSection(
      'Station & API',
      'Workstation identity and API environment',
      Icons.lan_rounded,
    ),
    _SettingsSection(
      'Work Instructions',
      'Pick which instruction videos are shown',
      Icons.video_collection_rounded,
    ),
    _SettingsSection(
      'System Updates',
      'App version and over-the-air updates',
      Icons.system_update_rounded,
    ),
  ];

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

  /// Opens a specific settings section (used for deep-links from other screens).
  void openSection(int index) {
    if (index < 0 || index >= _sections.length) return;
    setState(() => _selectedSection = index);
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Machine set to $newValue — applies on Live Readings.'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 2),
          ),
        );
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
        return 'Live Readings (Right+)';
      case AppScreen.detSelector:
        return 'Sensor Configuration (Right++)';
      case AppScreen.settings:
        return 'Settings (Right+++)';
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final theme = Theme.of(context);
    final primaryColor = theme.primaryColor;

    if (_isLoading) {
      return const Scaffold(
        backgroundColor: Color(0xFFF8FAFF),
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFF),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 760;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildSidebar(compact, primaryColor),
                Expanded(child: _buildContentPane(primaryColor)),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Two-pane scaffolding
  // ---------------------------------------------------------------------------

  Widget _buildSidebar(bool compact, Color primaryColor) {
    final width = compact ? 78.0 : 264.0;
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Colors.blueGrey[50]!)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Brand / title header
          Padding(
            padding: EdgeInsets.fromLTRB(
                compact ? 0 : 20, 22, compact ? 0 : 20, 18),
            child: compact
                ? Icon(Icons.settings_rounded, color: primaryColor, size: 28)
                : Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: primaryColor,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Icon(Icons.settings_rounded,
                            color: Colors.white, size: 22),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Settings',
                          style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.black87),
                        ),
                      ),
                    ],
                  ),
          ),
          Divider(height: 1, color: Colors.blueGrey[50]),
          // Nav items
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(
                  horizontal: compact ? 10 : 12, vertical: 10),
              itemCount: _sections.length,
              itemBuilder: (context, i) =>
                  _buildNavItem(i, compact, primaryColor),
            ),
          ),
          // Footer version
          Divider(height: 1, color: Colors.blueGrey[50]),
          Padding(
            padding: const EdgeInsets.all(14),
            child: compact
                ? Icon(Icons.verified_rounded,
                    size: 18, color: Colors.blueGrey[300])
                : Row(
                    children: [
                      Icon(Icons.verified_rounded,
                          size: 16, color: Colors.blueGrey[300]),
                      const SizedBox(width: 8),
                      Text(
                        _appVersion.isNotEmpty
                            ? 'Version $_appVersion'
                            : 'Loading…',
                        style: TextStyle(
                            fontSize: 12,
                            color: Colors.blueGrey[400],
                            fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, bool compact, Color primaryColor) {
    final section = _sections[index];
    final selected = _selectedSection == index;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Material(
        color: selected ? primaryColor.withValues(alpha: 0.10) : Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => setState(() => _selectedSection = index),
          child: Container(
            padding: EdgeInsets.symmetric(
                horizontal: compact ? 0 : 14, vertical: 13),
            child: compact
                ? Icon(section.icon,
                    size: 24,
                    color:
                        selected ? primaryColor : Colors.blueGrey[400])
                : Row(
                    children: [
                      Icon(section.icon,
                          size: 20,
                          color: selected
                              ? primaryColor
                              : Colors.blueGrey[400]),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          section.title,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: selected
                                ? FontWeight.bold
                                : FontWeight.w500,
                            color: selected
                                ? primaryColor
                                : Colors.blueGrey[700],
                          ),
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }

  Widget _buildContentPane(Color primaryColor) {
    final section = _sections[_selectedSection];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Header
        Padding(
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: primaryColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(section.icon, color: primaryColor, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(section.title,
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: Colors.black87)),
                    const SizedBox(height: 2),
                    Text(section.subtitle,
                        style: TextStyle(
                            fontSize: 13, color: Colors.blueGrey[400])),
                  ],
                ),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: Colors.blueGrey[50]),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(28, 20, 28, 32),
            child: Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 820),
                child: _buildSectionContent(_selectedSection, primaryColor),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionContent(int index, Color primaryColor) {
    switch (index) {
      case 0:
        return _buildLayoutSection(primaryColor);
      case 1:
        return _buildHardwareSection(primaryColor);
      case 2:
        return _buildStationSection(primaryColor);
      case 3:
        return _buildVideoSection(primaryColor);
      case 4:
        return _buildUpdatesSection(primaryColor);
      default:
        return const SizedBox.shrink();
    }
  }

  // ---------------------------------------------------------------------------
  // Section content
  // ---------------------------------------------------------------------------

  Widget _buildLayoutSection(Color primaryColor) {
    return _buildCard(
      child: Column(
        children: AppScreen.values.map((screen) {
          if (screen == AppScreen.settings) return const SizedBox.shrink();
          final isEnabled = _enabledScreens.contains(screen);
          return SwitchListTile(
            title: Text(
              _getScreenName(screen),
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
            secondary:
                Icon(_getScreenIcon(screen), color: primaryColor, size: 22),
            value: isEnabled,
            activeThumbColor: primaryColor,
            onChanged: (val) => _toggleScreen(screen, val),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildHardwareSection(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: ConfigService.machineUrls.entries
              .map((e) => _buildMachineTile(e, primaryColor))
              .toList(),
        ),
        const SizedBox(height: 20),
        _buildInfoNote(
          'Changes apply as soon as you return to Live Readings — no app restart needed.',
          primaryColor,
        ),
      ],
    );
  }

  Widget _buildMachineTile(MapEntry<String, String> entry, Color primaryColor) {
    final selected = _selectedMachine == entry.key;
    final ip = entry.value.replaceAll('http://', '').replaceAll(':5050', '');
    return SizedBox(
      width: 172,
      child: Material(
        color: selected ? primaryColor.withValues(alpha: 0.06) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: () => _saveSettings(entry.key),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: selected ? primaryColor : Colors.blueGrey[100]!,
                width: selected ? 2 : 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: selected ? primaryColor : Colors.blueGrey[50],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        Icons.precision_manufacturing_rounded,
                        size: 20,
                        color: selected ? Colors.white : Colors.blueGrey[400],
                      ),
                    ),
                    Icon(
                      selected
                          ? Icons.check_circle_rounded
                          : Icons.circle_outlined,
                      size: 22,
                      color: selected ? primaryColor : Colors.blueGrey[200],
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  entry.key,
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: selected ? primaryColor : Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.lan_rounded,
                        size: 12, color: Colors.blueGrey[300]),
                    const SizedBox(width: 4),
                    Text(ip,
                        style: TextStyle(
                            fontSize: 12, color: Colors.blueGrey[400])),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStationSection(Color primaryColor) {
    return _buildCard(
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
                onPressed: () =>
                    setState(() => _isManualMode = !_isManualMode),
                icon: Icon(
                    _isManualMode
                        ? Icons.list_rounded
                        : Icons.edit_rounded,
                    size: 16),
                label: Text(
                    _isManualMode ? 'Select from List' : 'Manual Entry',
                    style: const TextStyle(fontSize: 11)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_fetchError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(_fetchError!,
                  style: const TextStyle(color: Colors.red, fontSize: 12)),
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
                      fillColor: Colors.blueGrey[50]!.withValues(alpha: 0.5),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _saveWorkstationId,
                  style: ElevatedButton.styleFrom(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                  child: const Text('Save'),
                ),
              ],
            )
          else
            DropdownButtonFormField<String>(
              initialValue: _workstations
                      .any((w) => w['id'] == _workstationIdController.text)
                  ? _workstationIdController.text
                  : null,
              decoration: InputDecoration(
                filled: true,
                fillColor: Colors.blueGrey[50]!.withValues(alpha: 0.5),
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
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
              color: Colors.blueGrey[50]!.withValues(alpha: 0.5),
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
            _useProductionApi
                ? ApiConstants.productionOpsDigiBaseUrl
                : ApiConstants.opsDigiBaseUrl,
            style: TextStyle(
                fontSize: 10,
                color: primaryColor,
                fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoSection(Color primaryColor) {
    return _buildCard(
      child: Column(
        children: WorkInstructionsConstants.allWis.map((wi) {
          final isSelected = _selectedVideoIds.contains(wi.id);
          return CheckboxListTile(
            title:
                Text(wi.title, style: const TextStyle(fontWeight: FontWeight.w500)),
            subtitle: Text(wi.id, style: const TextStyle(fontSize: 12)),
            value: isSelected,
            activeColor: primaryColor,
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
    );
  }

  Widget _buildUpdatesSection(Color primaryColor) {
    return _buildCard(
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
                  const Text('Firmware Version',
                      style: TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                      _appVersion.isNotEmpty
                          ? 'Build v$_appVersion'
                          : 'Fetching version...',
                      style: TextStyle(
                          color: Colors.blueGrey[400], fontSize: 13)),
                ],
              ),
              if (_isCheckingUpdate)
                const CircularProgressIndicator(strokeWidth: 3)
              else
                ElevatedButton.icon(
                  onPressed: _handleCheckForUpdates,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('Check Now'),
                  style: ElevatedButton.styleFrom(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10))),
                ),
            ],
          ),
          if (_updateStatus.isNotEmpty && !_isCheckingUpdate)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(_updateStatus,
                  style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w500)),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Shared helpers
  // ---------------------------------------------------------------------------

  Widget _buildInfoNote(String text, Color primaryColor) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: primaryColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: primaryColor),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(fontSize: 12.5, color: Colors.blueGrey[700]),
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
            boxShadow: active
                ? [
                    BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 4,
                        offset: const Offset(0, 2))
                  ]
                : null,
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

/// Metadata for one entry in the settings sidebar / content header.
class _SettingsSection {
  final String title;
  final String subtitle;
  final IconData icon;

  const _SettingsSection(this.title, this.subtitle, this.icon);
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
