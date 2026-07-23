class ConfigService {
  ConfigService._();

  static const String buildVersion =
      String.fromEnvironment('BUILD_VERSION', defaultValue: '1.0.0');

  static const String buildNumber =
      String.fromEnvironment('BUILD_NUMBER', defaultValue: 'dev');
}
