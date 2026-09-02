#!/bin/bash
set -euo pipefail

KEYSTORE_PATH="android/release-keystore.jks"
ALIAS="tin-release"
VALIDITY=10000
KEY_SIZE=2048

if [ -f "$KEYSTORE_PATH" ]; then
  echo "ERROR: $KEYSTORE_PATH already exists"
  echo "Remove it first if you want to regenerate"
  exit 1
fi

echo "Generating release keystore..."
keytool -genkeypair \
  -v \
  -keystore "$KEYSTORE_PATH" \
  -keyalg RSA \
  -keysize "$KEY_SIZE" \
  -validity "$VALIDITY" \
  -alias "$ALIAS" \
  -storepass "$STORE_PASSWORD" \
  -keypass "$KEY_PASSWORD" \
  -dname "CN=TIN, OU=Android, O=nnn669, L=Beijing, S=Beijing, C=CN"

echo ""
echo "Keystore generated: $KEYSTORE_PATH"
echo "Base64 for GitHub Secrets:"
base64 -w 0 "$KEYSTORE_PATH"
echo ""
echo ""
echo "GitHub Secrets to set:"
echo "  SIGN_KEYSTORE_BASE64=<base64-output>"
echo "  SIGN_STORE_PASSWORD=$STORE_PASSWORD"
echo "  SIGN_KEY_ALIAS=$ALIAS"
echo "  SIGN_KEY_PASSWORD=$KEY_PASSWORD"
