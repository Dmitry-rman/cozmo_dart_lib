/// Конфигурация OpenAI Realtime API
class AIConfig {
  /// URL для создания WebRTC сессии
  final String sessionUrl;

  /// API токен
  final String apiToken;

  /// API секрет
  final String apiSecret;

  /// Системные инструкции для робота
  final String systemInstructions;

  /// Голос (alloy, echo, etc.)
  final String voice;

  /// Язык (ru, en, etc.)
  final String language;

  /// Код голоса (9982 = russian, 9984 = chinese, etc.)
  final int voiceCode;

  const AIConfig({
    required this.sessionUrl,
    required this.apiToken,
    required this.apiSecret,
    required this.systemInstructions,
    this.voice = 'alloy',
    this.language = 'ru',
    this.voiceCode = 9982,
  });

  /// Заголовки для API запросов
  Map<String, String> get headers => {
        'Authorization': 'Bearer $apiToken',
        'Content-Type': 'application/json',
        'apikey': apiSecret,
      };

  /// Body для создания сессии
  Map<String, dynamic> createSessionBody(String offerSdp) {
    return {
      'sdp': offerSdp,
      'language': language,
      'code': voiceCode,
    };
  }
}
