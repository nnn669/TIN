import '../../providers/settings_provider.dart';

const String _appUserAgent = 'TIN';
const String _openRouterAppReferer = 'https://github.com/nnn669/TIN';
const String _openRouterAppTitle = 'TIN';
const String _openRouterAppCategories = 'general-chat';

bool isOpenRouterProvider(ProviderConfig config) {
  final host = Uri.tryParse(config.baseUrl)?.host.toLowerCase() ?? '';
  return host.contains('openrouter.ai');
}

Map<String, String> providerDefaultHeaders(ProviderConfig config) {
  if (!isOpenRouterProvider(config)) {
    return const <String, String>{'User-Agent': _appUserAgent};
  }
  return const <String, String>{
    'User-Agent': _appUserAgent,
    'HTTP-Referer': _openRouterAppReferer,
    'X-OpenRouter-Title': _openRouterAppTitle,
    'X-OpenRouter-Categories': _openRouterAppCategories,
  };
}
