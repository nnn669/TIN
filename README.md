# TIN

TIN is an Android Flutter application.

## Download source

When GitHub's `codeload` service is rate-limited, download the latest `main` branch archive from the stable release asset:

https://github.com/nnn669/TIN/releases/download/source-latest/TIN-main.zip

## Build

```bash
flutter pub get
flutter build apk --release --target-platform android-arm64
```

Configure your own Android signing key before building a release APK. Do not commit credentials, tokens, keystores, or build artifacts.

## License

This project is licensed under AGPL-3.0. See [LICENSE](LICENSE).