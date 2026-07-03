import 'package:flutter/foundation.dart';

/// Index of the page currently visible in the kiosk [PageView].
///
/// Kept-alive screens can read this to skip background work when they are
/// off-screen (e.g. the Web Logs screen only injects the live gauge value into
/// its WebView while it is actually the visible page).
final ValueNotifier<int> kioskActivePageIndex = ValueNotifier<int>(0);
