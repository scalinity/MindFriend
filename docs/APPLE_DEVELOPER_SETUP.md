# Apple Developer Account Setup Guide

**Last Updated:** 2026-01-23
**Status:** Configuration Required
**Owner:** @danny

This guide covers all Apple Developer account configurations needed for the MindFriend iOS app.

---

## Quick Reference: Required Apple Assets

| Asset                     | Location                   | Format   | Purpose                                |
| ------------------------- | -------------------------- | -------- | -------------------------------------- |
| **Team ID**               | Membership page            | 10 chars | Code signing, APNs, Sign in with Apple |
| **APNs Auth Key**         | Keys → Create Key          | .p8 file | Push notifications                     |
| **APNs Key ID**           | After creating key         | 10 chars | APNs configuration                     |
| **App Store Connect Key** | App Store Connect → Keys   | .p8 file | StoreKit validation                    |
| **App Store Key ID**      | After creating key         | 10 chars | StoreKit API                           |
| **App Store Issuer ID**   | Keys page header           | UUID     | StoreKit API                           |
| **Service ID**            | Identifiers → Services IDs | String   | Sign in with Apple                     |

---

## Phase 1: Apple Developer Console Setup

### 1.1 Create App Identifier

**Navigation:** Certificates, Identifiers & Profiles → Identifiers → App IDs

**Configuration:**

- **Description:** MindFriend
- **Bundle ID:** `com.mindfriend.app` (Explicit)
- **Capabilities to Enable:**
  - ✅ Sign in with Apple
  - ✅ Push Notifications
  - ✅ In-App Purchase
  - ✅ App Groups

**Steps:**

1. Click "+" to create new identifier
2. Select "App IDs" → Continue
3. Select "App" → Continue
4. Fill in description and bundle ID
5. Scroll to Capabilities section
6. Enable the 4 capabilities listed above
7. Click Continue → Register

### 1.2 Create App Groups

**Navigation:** Certificates, Identifiers & Profiles → Identifiers → App Groups

**Configuration:**

- **Description:** MindFriend Shared Data
- **Identifier:** `group.com.mindfriend.app`

**Steps:**

1. Click "+" to create new identifier
2. Select "App Groups" → Continue
3. Enter description and identifier
4. Click Continue → Register

**Link to App ID:**

1. Go back to your App ID (`com.mindfriend.app`)
2. Click "Edit" next to App Groups capability
3. Select `group.com.mindfriend.app`
4. Save

### 1.3 Create Services ID (Sign in with Apple)

**Navigation:** Certificates, Identifiers & Profiles → Identifiers → Services IDs

**Configuration:**

- **Description:** MindFriend Sign in with Apple
- **Identifier:** `com.mindfriend.app.service`

**Steps:**

1. Click "+" to create new identifier
2. Select "Services IDs" → Continue
3. Enter description and identifier
4. Check "Sign in with Apple"
5. Click Configure
6. **Primary App ID:** Select `com.mindfriend.app`
7. **Website URLs:**
   - **Domains and Subdomains:** `getmindfriend.app`, `[your-supabase-project].supabase.co`
   - **Return URLs:**
     - `https://getmindfriend.app/auth/callback`
     - `https://[your-supabase-project].supabase.co/auth/v1/callback`
8. Save → Continue → Register

**Note:** You'll need to get your exact Supabase project URL from the Supabase Dashboard.

### 1.4 Generate APNs Authentication Key

**Navigation:** Certificates, Identifiers & Profiles → Keys

**Steps:**

1. Click "+" to create new key
2. **Key Name:** MindFriend APNs Key
3. Check "Apple Push Notifications service (APNs)"
4. Click Continue → Register
5. **Download the .p8 file immediately** (only chance!)
6. **Save the Key ID** (10 characters, e.g., `ABC1234567`)
7. **Save your Team ID** (Membership page, 10 characters)

**Security:**

- Store the .p8 file securely (password manager, secrets vault)
- Never commit to git
- Cannot be re-downloaded (must regenerate if lost)

**Convert to Base64 for Supabase:**

```bash
base64 -i AuthKey_ABC1234567.p8 | tr -d '\n' | pbcopy
```

---

## Phase 2: App Store Connect Setup

### 2.1 Create App Record

**Navigation:** App Store Connect → My Apps → "+" → New App

**Configuration:**

- **Platform:** iOS
- **Name:** MindFriend
- **Primary Language:** English (U.S.)
- **Bundle ID:** `com.mindfriend.app`
- **SKU:** `mindfriend-ios` (or any unique identifier)
- **User Access:** Full Access

### 2.2 Create In-App Purchase Products

**Navigation:** App Store Connect → My Apps → MindFriend → In-App Purchases

**Required Products (Auto-Renewable Subscriptions):**

| Product ID                       | Display Name    | Type           | Duration |
| -------------------------------- | --------------- | -------------- | -------- |
| `com.mindfriend.premium.monthly` | Premium Monthly | Auto-Renewable | 1 Month  |
| `com.mindfriend.premium.yearly`  | Premium Yearly  | Auto-Renewable | 1 Year   |
| `com.mindfriend.couples.monthly` | Couples Monthly | Auto-Renewable | 1 Month  |
| `com.mindfriend.couples.annual`  | Couples Annual  | Auto-Renewable | 1 Year   |
| `com.mindfriend.family.monthly`  | Family Monthly  | Auto-Renewable | 1 Month  |
| `com.mindfriend.family.annual`   | Family Annual   | Auto-Renewable | 1 Year   |

**Setup for Each Product:**

1. Click "+" → Auto-Renewable Subscription
2. Create subscription group (if first product): "MindFriend Subscriptions"
3. **Reference Name:** (e.g., "Premium Monthly")
4. **Product ID:** (from table above)
5. **Subscription Duration:** (from table above)
6. **Subscription Prices:** Set pricing tier
7. **Localization:**
   - Add English (U.S.)
   - Add Spanish (Spain/Mexico) - MVP requirement
   - Add Portuguese (Brazil) - MVP requirement
8. **Review Information:** Add screenshots (can be placeholders initially)
9. Submit for Review (after app is ready)

**Subscription Group Levels:**

- Level 1: Individual plans (monthly, yearly)
- Level 2: Couples plans (monthly, annual)
- Level 3: Family plans (monthly, annual)

### 2.3 Generate App Store Connect API Key

**Navigation:** App Store Connect → Users and Access → Keys (under "Integrations" tab)

**Steps:**

1. Click "+" to generate new key
2. **Name:** MindFriend Server Validation
3. **Access:** App Manager (or Admin if preferred)
4. Click Generate
5. **Download the .p8 file immediately** (only chance!)
6. **Save the Key ID** (10 characters)
7. **Save the Issuer ID** (UUID, shown at top of Keys page)

**Security:** Same precautions as APNs key

**Convert to Base64 for Supabase:**

```bash
base64 -i AuthKey_XYZ1234567.p8 | tr -d '\n' | pbcopy
```

---

## Phase 3: Xcode Configuration

### 3.1 Update Development Team

**Option A: Via project.yml (Recommended if using XcodeGen)**

Edit `apps/ios/project.yml`:

```yaml
settings:
  base:
    DEVELOPMENT_TEAM: "ABC1234567" # Replace with your Team ID
```

Then regenerate:

```bash
cd apps/ios
xcodegen generate
```

**Option B: Via Xcode GUI**

1. Open `apps/ios/MindFriendApp.xcodeproj`
2. Select MindFriendApp project in navigator
3. Select MindFriendApp target
4. Go to Signing & Capabilities tab
5. Select your Team from dropdown
6. Repeat for MindFriendAppTests and MindFriendAppUITests targets

### 3.2 Configure Entitlements

**File:** `apps/ios/MindFriendApp/MindFriendApp.entitlements`

**Required Entitlements:**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- Push Notifications -->
    <key>aps-environment</key>
    <string>development</string> <!-- Change to 'production' for release builds -->

    <!-- Sign in with Apple -->
    <key>com.apple.developer.applesignin</key>
    <array>
        <string>Default</string>
    </array>

    <!-- App Groups -->
    <key>com.apple.security.application-groups</key>
    <array>
        <string>group.com.mindfriend.app</string>
    </array>
</dict>
</plist>
```

**How to Update:**

1. Open Xcode
2. Select MindFriendApp target → Signing & Capabilities
3. Click "+ Capability"
4. Add "Push Notifications"
5. Add "Sign in with Apple"
6. Add "App Groups" → Configure → Check `group.com.mindfriend.app`

Or manually edit the `.entitlements` file with the XML above.

### 3.3 Verify Info.plist Configuration

**File:** `apps/ios/MindFriendApp/Info.plist`

**Already Configured (no changes needed):**

- ✅ Google OAuth reverse client ID
- ✅ Deep link URL scheme (`mindfriend://`)
- ✅ Background modes (remote notifications)

**Verification:**

```bash
cd apps/ios
plutil -p MindFriendApp/Info.plist | grep -A5 "CFBundleURLSchemes\|UIBackgroundModes"
```

---

## Phase 4: Supabase Dashboard Configuration

### 4.1 Configure Apple Auth Provider

**Navigation:** Supabase Dashboard → Authentication → Providers → Apple

**Configuration:**

1. Toggle "Apple enabled" to ON
2. **Services ID:** `com.mindfriend.app.service`
3. **Team ID:** (from Apple Developer Console Membership)
4. **Key ID:** (from APNs key generation)
5. **Private Key:** (paste entire contents of .p8 file, including BEGIN/END lines)
6. Click Save

### 4.2 Configure Google Auth Provider

**Navigation:** Supabase Dashboard → Authentication → Providers → Google

**Current Configuration (verify):**

- **Client ID:** `937820575713-afr6c9u3mtle5emk9aefa1fiosojfmbg.apps.googleusercontent.com`
- **Client Secret:** (should already be set)

**Action:** Verify this matches your Google Cloud Console OAuth configuration, or reconfigure if needed.

### 4.3 Set Edge Function Environment Variables

**Navigation:** Supabase Dashboard → Edge Functions → (select function) → Settings → Secrets

**OR** via Supabase CLI:

```bash
supabase secrets set APNS_KEY_ID="ABC1234567"
supabase secrets set APNS_TEAM_ID="XYZ9876543"
supabase secrets set APNS_PRIVATE_KEY="<base64-encoded-p8-contents>"
supabase secrets set APNS_BUNDLE_ID="com.mindfriend.app"
supabase secrets set APNS_ENVIRONMENT="development"  # or 'production'

supabase secrets set APP_STORE_ISSUER_ID="12345678-1234-1234-1234-123456789abc"
supabase secrets set APP_STORE_KEY_ID="DEF1234567"
supabase secrets set APP_STORE_PRIVATE_KEY="<base64-encoded-p8-contents>"
```

**Required Secrets:**

| Secret                  | Value                         | Source                                    |
| ----------------------- | ----------------------------- | ----------------------------------------- |
| `APNS_KEY_ID`           | 10-char string                | APNs key generation step 1.4              |
| `APNS_TEAM_ID`          | 10-char string                | Apple Developer Membership page           |
| `APNS_PRIVATE_KEY`      | Base64 string                 | Base64-encoded APNs .p8 file              |
| `APNS_BUNDLE_ID`        | `com.mindfriend.app`          | Hardcoded                                 |
| `APNS_ENVIRONMENT`      | `development` or `production` | Based on deployment                       |
| `APP_STORE_ISSUER_ID`   | UUID                          | App Store Connect API key step 2.3        |
| `APP_STORE_KEY_ID`      | 10-char string                | App Store Connect API key step 2.3        |
| `APP_STORE_PRIVATE_KEY` | Base64 string                 | Base64-encoded App Store Connect .p8 file |

**Verification:**

```bash
supabase secrets list
```

### 4.4 Configure URL Settings

**Navigation:** Supabase Dashboard → Authentication → URL Configuration

**Site URL:**

```
https://getmindfriend.app/auth/callback
```

**Redirect URLs (add all):**

```
https://getmindfriend.app
https://getmindfriend.app/auth/callback
https://getmindfriend.app/auth/confirmed
mindfriend://auth/callback
```

**Additional Redirect URLs (optional, for testing):**

```
http://localhost:3000/auth/callback
```

---

## Phase 5: Testing & Validation

### 5.1 Test Sign in with Apple (Sandbox)

**Prerequisites:**

- Device signed in with Apple ID (Settings → [Your Name])
- Apple ID configured for Sandbox testing (App Store Connect → Users and Access → Sandbox Testers)

**Test Steps:**

1. Run app in Xcode Simulator or physical device
2. Tap "Sign in with Apple"
3. Use Sandbox Apple ID credentials
4. Verify successful authentication
5. Check Supabase Dashboard → Authentication → Users for new user

**Common Issues:**

- "Invalid client" → Service ID configuration mismatch
- "Invalid redirect URI" → Check Supabase redirect URLs match Apple configuration

### 5.2 Test Push Notifications (Development)

**Prerequisites:**

- Physical iOS device (push notifications don't work in Simulator)
- Development provisioning profile with Push Notifications capability
- APNs environment variables set to `development`

**Test Steps:**

1. Build and run app on physical device
2. Grant push notification permission when prompted
3. Trigger a test notification via Supabase Edge Function:
   ```bash
   curl -X POST https://[your-project].supabase.co/functions/v1/send-notification \
     -H "Authorization: Bearer [your-jwt]" \
     -H "Content-Type: application/json" \
     -d '{"title": "Test", "body": "Hello from MindFriend"}'
   ```
4. Verify notification appears on device

**Common Issues:**

- No notification received → Check device token registration, APNs credentials
- "Invalid APNs certificate" → Verify APNs key is correct and not expired

### 5.3 Test In-App Purchases (Sandbox)

**Prerequisites:**

- Sandbox tester account (App Store Connect → Users and Access → Sandbox Testers)
- Device signed out of production App Store (Settings → App Store → Sign Out)
- All 6 subscription products created in App Store Connect

**Test Steps:**

1. Run app on device or simulator
2. Navigate to Premium/Subscription screen
3. Tap a subscription option (e.g., Premium Monthly)
4. Sign in with Sandbox tester credentials when prompted
5. Complete purchase flow
6. Verify subscription granted in app
7. Check Supabase `subscriptions` table for new record

**Common Issues:**

- Products not loading → Verify bundle ID matches exactly, check product IDs in code
- Purchase fails → Check StoreKit configuration, verify App Store Connect API key

### 5.4 Verify StoreKit Server Validation

**Test via Edge Function:**

```bash
# After completing a sandbox purchase, get the transaction ID from iOS logs
curl -X POST https://[your-project].supabase.co/functions/v1/verify-purchase \
  -H "Authorization: Bearer [your-jwt]" \
  -H "Content-Type: application/json" \
  -d '{"originalTransactionId": "1000000123456789"}'
```

**Expected Response:**

```json
{
  "valid": true,
  "subscription": {
    "productId": "com.mindfriend.premium.monthly",
    "expiresDate": "2026-02-23T12:34:56Z",
    "isActive": true
  }
}
```

**Common Issues:**

- "Invalid transaction" → Verify App Store Connect API credentials
- "Bundle ID mismatch" → Ensure transaction is for `com.mindfriend.app`

---

## Phase 6: Production Deployment

### 6.1 Update Entitlements for Production

**Change:** `apps/ios/MindFriendApp/MindFriendApp.entitlements`

```xml
<key>aps-environment</key>
<string>production</string> <!-- Changed from 'development' -->
```

### 6.2 Update Supabase Environment Variables

```bash
supabase secrets set APNS_ENVIRONMENT="production"
```

### 6.3 Create Production Provisioning Profiles

**Navigation:** Xcode → Preferences → Accounts → [Your Team] → Download Manual Profiles

**Or:** Xcode will automatically create/update when archiving for release

### 6.4 Archive and Upload to App Store Connect

**Steps:**

1. Xcode → Product → Archive
2. Wait for archive to complete
3. Organizer window opens → Select archive
4. Click "Distribute App"
5. Select "App Store Connect" → Upload
6. Select signing options (Automatically manage signing)
7. Click Upload
8. Wait for processing in App Store Connect

### 6.5 Submit for Review

**Navigation:** App Store Connect → My Apps → MindFriend → App Store tab

**Required for Submission:**

- App metadata (name, description, screenshots)
- Privacy policy URL
- Support URL
- Age rating
- Export compliance information
- At least one build uploaded

---

## Troubleshooting

### Code Signing Issues

**Error:** "No signing certificate found"

- **Solution:** Xcode → Preferences → Accounts → Download Manual Profiles

**Error:** "Provisioning profile doesn't include capability"

- **Solution:** Regenerate profile in Apple Developer Console, download in Xcode

### Push Notification Issues

**Error:** "Invalid APNs token"

- **Solution:** Verify Base64 encoding is correct, no newlines

**Error:** "Mismatched topic"

- **Solution:** Ensure APNs bundle ID matches app bundle ID exactly

### StoreKit Issues

**Error:** "Products not loading in sandbox"

- **Solution:** Wait 2-4 hours after creating products, clear app data and retry

**Error:** "Invalid product ID"

- **Solution:** Verify product IDs in code match App Store Connect exactly

### Sign in with Apple Issues

**Error:** "Invalid client"

- **Solution:** Verify Service ID matches Supabase configuration

**Error:** "Redirect URI mismatch"

- **Solution:** Ensure all redirect URLs are configured in both Apple Developer Console and Supabase

---

## Security Checklist

- [ ] Never commit `.p8` files to git
- [ ] Store private keys in secure password manager
- [ ] Use environment variables for all sensitive values
- [ ] Rotate APNs keys annually
- [ ] Rotate App Store Connect API keys annually
- [ ] Enable two-factor authentication on Apple Developer account
- [ ] Limit access to App Store Connect API keys (App Manager role minimum)
- [ ] Monitor key usage in App Store Connect dashboard

---

## Reference Links

- [Apple Developer Portal](https://developer.apple.com/account/)
- [App Store Connect](https://appstoreconnect.apple.com/)
- [Supabase Dashboard](https://app.supabase.com/)
- [Sign in with Apple Documentation](https://developer.apple.com/sign-in-with-apple/)
- [APNs Documentation](https://developer.apple.com/documentation/usernotifications/)
- [StoreKit 2 Documentation](https://developer.apple.com/documentation/storekit/)

---

## Appendix: File Locations

**iOS App:**

- `apps/ios/MindFriendApp.xcodeproj` - Xcode project
- `apps/ios/project.yml` - XcodeGen configuration (if used)
- `apps/ios/MindFriendApp/MindFriendApp.entitlements` - Entitlements file
- `apps/ios/MindFriendApp/Info.plist` - App configuration
- `apps/ios/MindFriendApp/Core/Services/BillingService.swift` - StoreKit product IDs
- `apps/ios/MindFriendApp/Features/Auth/SignInView.swift` - Google OAuth client ID

**Supabase:**

- `supabase/functions/_shared/apns.ts` - APNs implementation
- `supabase/functions/send-notification/index.ts` - Push notification sender
- `supabase/functions/verify-purchase/index.ts` - StoreKit validation
- `supabase/config.toml` - Supabase project configuration

**Documentation:**

- `docs/CLAUDE.md` - Project conventions (lists required env vars)
- `docs/PROGRESS.md` - Development progress log
- `docs/decisions.md` - Architecture decisions
- `docs/APPLE_DEVELOPER_SETUP.md` - This document

---

**End of Guide**
