/// Browser-compatible headers for remote images embedded in generated content.
///
/// Some image CDNs reject Dart's default client identity while accepting the
/// same signed URL in a WebView. These headers contain no provider credentials.
const Map<String, String> browserImageRequestHeaders = <String, String>{
  'Accept': 'image/webp,image/png,image/jpeg,image/gif,image/*;q=0.8,*/*;q=0.5',
  'User-Agent':
      'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
};
