// lib/screens/kiosk_shell.dart
import 'package:flutter/material.dart';

import 'package:flutter/services.dart'; // Added for SystemChannels
import '../services/screen_config_service.dart'; // Import config service
import '../services/ui_state.dart';

// use prefixes to avoid name collisions and make it explicit
import 'web_logs_screen.dart' show WebLogsScreen;
import 'home_screen.dart' as home;
import 'wi_list_screen.dart' show WIListScreen;
import 'gauge_screen.dart' as gauge;
import 'det_selector_screen.dart' show DetSelectorScreen;
import 'settings_screen.dart';

import 'package:ota_update/ota_update.dart';
import '../services/update_service.dart';

class KioskShell extends StatefulWidget {
  final String apiHost;

  const KioskShell({super.key, required this.apiHost});

  @override
  State<KioskShell> createState() => _KioskShellState();
}

class _KioskShellState extends State<KioskShell> {
  late PageController _controller;
  List<Widget> _pages = [];
  int _pageIndex = 0;
  int _pageVersion = 0; // Force update
  final UpdateService _updateService = UpdateService();
  final ScreenConfigService _screenConfigService = ScreenConfigService();
  bool _isLoading = true;

  // GlobalKey to access HomeScreen functionality
  final GlobalKey<home.HomeScreenState> _homeKey =
      GlobalKey<home.HomeScreenState>();

  // GlobalKey to refresh the GaugeScreen when the user navigates back to it,
  // so hardware-configuration changes apply without an app restart.
  final GlobalKey<gauge.GaugeScreenState> _gaugeKey =
      GlobalKey<gauge.GaugeScreenState>();
  int _gaugeIndex = -1;

  // GlobalKey to deep-link into a specific Settings section, and the index of
  // the Sensor Configuration (DET selector) page for guiding the user there.
  final GlobalKey<SettingsScreenState> _settingsKey =
      GlobalKey<SettingsScreenState>();
  int _detSelectorIndex = -1;

  @override
  void initState() {
    super.initState();
    _checkForUpdates();
    _initPages();
  }

  Future<void> _initPages({bool stayOnSettings = false}) async {
    final enabledScreens = await _screenConfigService.getEnabledScreens();

    final List<Widget> pages = [];
    int homeIndex = 0;
    int settingsIndex = -1;
    _gaugeIndex = -1;
    _detSelectorIndex = -1;

    for (final screen in enabledScreens) {
      switch (screen) {
        case AppScreen.webLogs:
          pages.add(WebLogsScreen(pageIndex: pages.length));
          break;
        case AppScreen.home:
          pages.add(
            home.HomeScreen(
              key: _homeKey,
              onNavigateToSensorConfig: _goToSensorConfigPage,
            ),
          );
          homeIndex = pages.length - 1;
          break;
        case AppScreen.wiList:
          pages.add(
            WIListScreen(
              onNavigateToSettings: () => _goToSettingsPage(
                section: SettingsScreen.sectionWorkInstructions,
              ),
            ),
          );
          break;
        case AppScreen.gauge:
          pages.add(
            gauge.GaugeScreen(
              key: _gaugeKey,
              onNavigateToSettings: () => _goToSettingsPage(
                section: SettingsScreen.sectionMachine,
              ),
            ),
          );
          _gaugeIndex = pages.length - 1;
          break;
        case AppScreen.detSelector:
          pages.add(
            DetSelectorScreen(
              apiHost: widget.apiHost,
              onDetChanged: () {
                _homeKey.currentState?.refreshSensorInfo();
              },
            ),
          );
          _detSelectorIndex = pages.length - 1;
          break;
        case AppScreen.settings:
          pages.add(
            SettingsScreen(
              key: _settingsKey,
              onSettingsChanged: () => _initPages(stayOnSettings: true),
            ),
          );
          settingsIndex = pages.length - 1;
          break;
      }
    }

    if (mounted) {
      if (_pages.isNotEmpty) {
        try {
          _controller.dispose();
        } catch (_) {}
      }

      setState(() {
        _pages = pages;
        _pageVersion++; // Force rebuild
        // If we want to stay on settings and it exists, use that. Else home.
        _pageIndex = (stayOnSettings && settingsIndex != -1)
            ? settingsIndex
            : homeIndex;

        debugPrint(
          'KioskShell: stay=$stayOnSettings, settingsIdx=$settingsIndex, homeIdx=$homeIndex, target=$_pageIndex',
        );

        // Re-create controller to snap to new index or just jump
        // If we dispose old one, we must create new one.
        // If _controller is lately initialized, checking _pages.isNotEmpty before might be needed in dispose?
        // We already have logic in dispose/build.
        // It's safer to recreate controller to ensure initialPage is correct.
        _controller = PageController(initialPage: _pageIndex);
        kioskActivePageIndex.value = _pageIndex;
        _isLoading = false;
      });
    }
  }

  Future<void> _checkForUpdates() async {
    // Small delay to let UI build
    await Future.delayed(const Duration(seconds: 2));
    if (!mounted) return;

    final info = await _updateService.checkForUpdate();
    if (info != null && info['updateAvailable'] == true && mounted) {
      _showUpdatePrompt(info);
    }
  }

  // ... rest of update logic methods ...

  void _showUpdatePrompt(Map<String, dynamic> info) {
    showDialog(
      context: context,
      barrierDismissible: false,
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
              constraints: const BoxConstraints(maxHeight: 100),
              child: SingleChildScrollView(
                child: Text(info['releaseNotes'] ?? ''),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Later'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _performUpdate(info['downloadUrl']);
            },
            child: const Text('Update Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _performUpdate(String apkUrl) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _UpdateProgressDialog(
        stream: _updateService.runUpdate(apkUrl),
        onDone: () => Navigator.pop(ctx),
      ),
    );
  }

  Future<void> _goToSettingsPage({int? section}) async {
    final enabledScreens = await _screenConfigService.getEnabledScreens();
    int index = enabledScreens.indexOf(AppScreen.settings);
    if (index != -1) {
      _goTo(index, animate: false);
      if (section != null) {
        // Defer until the Settings page is built/visible so its state exists.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _settingsKey.currentState?.openSection(section);
        });
      }
    }
  }

  void _goToSensorConfigPage() {
    if (_detSelectorIndex != -1) {
      _goTo(_detSelectorIndex);
    }
  }

  void _goTo(int index, {bool animate = true}) {
    if (index < 0 || index > _pages.length - 1) return;

    // Force hide keyboard (Works better for WebViews/Native views than just unfocus)
    SystemChannels.textInput.invokeMethod('TextInput.hide');
    FocusScope.of(context).unfocus();

    setState(() {
      _pageIndex = index;
    });
    kioskActivePageIndex.value = index;

    // Re-apply hardware configuration when returning to the gauge screen so
    // changes made in Settings take effect without an app restart.
    if (index == _gaugeIndex) {
      _gaugeKey.currentState?.refreshConfig();
    }

    if (animate) {
      _controller.animateToPage(
        _pageIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    } else {
      _controller.jumpToPage(_pageIndex);
    }
  }

  @override
  void dispose() {
    // Check if initialized to avoid error if dispose calls before init
    // But local variable created in init... wait, I made controller late.
    // Ideally check if initialized. But since we await in init, it might be safer.
    // Actually, let's just try/catch or assume it's fine for now as user stays on screen.
    if (_pages.isNotEmpty) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: Stack(
        children: [
          PageView(
            key: ValueKey(_pageVersion),
            controller: _controller,
            physics:
                const NeverScrollableScrollPhysics(), // no swipe, use arrows
            children: _pages,
          ),

          // LEFT arrow
          if (_pageIndex > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 16),
                child: _NavButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => _goTo(_pageIndex - 1),
                ),
              ),
            ),

          // RIGHT arrow
          if (_pageIndex < _pages.length - 1)
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 16),
                child: _NavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => _goTo(_pageIndex + 1),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _NavButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(30),
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.8),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: Icon(icon, size: 36, color: Colors.blueGrey[800]),
        ),
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
