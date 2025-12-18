import 'dart:async';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../socket_service.dart'; 
import '../services/config_service.dart';

class WebLogsScreen extends StatefulWidget {
  const WebLogsScreen({super.key});

  @override
  State<WebLogsScreen> createState() => _WebLogsScreenState();
}

class _WebLogsScreenState extends State<WebLogsScreen>
    with AutomaticKeepAliveClientMixin {
  late final WebViewController _controller;
  bool _isLoading = true;
  StreamSubscription? _gaugeSub;

  @override
  void initState() {
    super.initState();

    // 1. Subscribe to the Gauge Stream
    _gaugeSub = SocketService().gaugeStream.listen((data) {
      if (data.containsKey('value')) {
        final newValue = data['value'].toString();

        // Only inject if the page has finished loading to avoid errors
        if (!_isLoading) {
          _injectValueIntoWeb(newValue);
        }
      }
    });

    // Ensure connection is active
    _connectSocket();

    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFFFFFFFF))
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (url) {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          },
        ),
      )
      ..loadRequest(Uri.parse('https://logi.weberq.in')); //
  }

  @override
  void dispose() {
    _gaugeSub?.cancel();
    super.dispose();
  }

  // Automatically injects the value into the currently focused input field
  Future<void> _injectValueIntoWeb(String value) async {
    final jsScript =
        '''
      (function() {
        var input = document.activeElement;
        // Check if the focused element is a text input or textarea
        if (input && (input.tagName === 'INPUT' || input.tagName === 'TEXTAREA') && !input.readOnly && !input.disabled) {
          
          // Use the prototype setter to bypass React/Angular overrides if present
          var nativeInputValueSetter = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype, "value").set;
          if (nativeInputValueSetter) {
             nativeInputValueSetter.call(input, '$value');
          } else {
             input.value = '$value';
          }
          
          // Dispatch input events so the web app detects the change
          input.dispatchEvent(new Event('input', { bubbles: true }));
          input.dispatchEvent(new Event('change', { bubbles: true }));
        }
      })();
    ''';

    try {
      await _controller.runJavaScript(jsScript);
    } catch (e) {
      // Ignore errors if the webview isn't ready or context is lost
      debugPrint("Error injecting value: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    return Stack(
      children: [
        // The Web View
        SafeArea(child: WebViewWidget(controller: _controller)),

        // Loading Indicator
        if (_isLoading)
          Container(
            color: Colors.white,
            alignment: Alignment.center,
            child: const CircularProgressIndicator(),
          ),
      ],
    );
  }

  @override
  bool get wantKeepAlive => true;

  Future<void> _connectSocket() async {
     final url = await ConfigService().getBaseUrl();
     if (url != null) {
       SocketService().connect(url);
     }
  }
}
