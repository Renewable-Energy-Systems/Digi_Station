class ApiConstants {
  // Default Dewpoint live-feed host as "IP:port" (the WebSocket and the HTTP
  // sensor-info API share it). Overridable at runtime via ConfigService /
  // Settings so a network IP change doesn't require rebuilding the APK — this is
  // only the fallback default.
  static const String defaultDewpointHost = '192.168.0.76:3000';
  static const String detApiHost = 'http://$defaultDewpointHost';
  static const String detWsUrl = 'ws://$defaultDewpointHost';

  static const String opsDigiBaseUrl = 'http://192.168.0.8/apis.digi/ops_digi';
  static const String productionOpsDigiBaseUrl =
      'https://apis.resindia.co.in/ops_digi';
}
