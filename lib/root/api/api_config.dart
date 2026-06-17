class ApiConfig {
  ApiConfig._();

  static const String baseUrl = 'https://api.SynCal.example.com';
  static const Duration timeout = Duration(seconds: 30);
  static const Map<String, String> defaultHeaders = {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
  };
}
