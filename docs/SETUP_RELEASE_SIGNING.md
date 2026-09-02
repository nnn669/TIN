# Release Signing Setup

## Generate Keystore

```bash
# Set your passwords
export STORE_PASSWORD="your-strong-store-password"
export KEY_PASSWORD="your-strong-key-password"

# Run the generator
bash scripts/generate-release-keystore.sh
```

## Configure GitHub Secrets

Go to: **GitHub → Settings → Secrets and variables → Actions → New repository secret**

Add these 4 secrets:

| Name | Value |
|---|---|
| `SIGN_KEYSTORE_BASE64` | Output from the script (base64-encoded keystore) |
| `SIGN_STORE_PASSWORD` | Your store password |
| `SIGN_KEY_ALIAS` | `tin-release` |
| `SIGN_KEY_PASSWORD` | Your key password |

## Verify

After setting secrets:
1. Go to **Actions** tab
2. Select **Android Test Release** workflow
3. Click **Run workflow**
4. Choose release type: `formal`
5. Check that APK is signed with your keystore

## Security Notes

- Never commit the keystore file to git
- Never expose passwords in logs
- Keep a backup of the keystore in a secure location
- If the keystore is lost, you cannot update the app on users' devices
