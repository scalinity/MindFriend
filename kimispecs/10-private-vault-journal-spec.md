# Private Vault Journal

## Step 1: Feature Analysis

### Core purpose and value proposition
- Provide a local-only, encrypted journal for highly sensitive reflections.
- Increase trust and depth of engagement through strong privacy guarantees.

### Target users and use cases
- Users who want to journal without cloud storage.
- Users who need a private space separate from standard mood notes.

### Dependencies / prerequisites
- iOS Keychain and LocalAuthentication (Face ID / Touch ID).
- Local encryption (CryptoKit).
- Existing journaling UI patterns.

## Step 2: Specification Document

### 1. Feature Overview
- **Feature name:** Private Vault Journal
- **Description:** A local-only journal protected by device authentication and encrypted at rest. Entries never leave the device and are excluded from AI processing.
- **Business justification and user value:** Builds trust and supports more vulnerable users, increasing retention and perceived safety.

### 2. Functional Requirements

#### FR1: Vault setup and access
- User stories:
  - As a user, I want to enable a private vault so I can store sensitive notes.
- Acceptance criteria:
  - Vault can be enabled in Settings with Face ID/Touch ID requirement.
  - If biometric is unavailable, use a device passcode fallback.

#### FR2: Create and manage entries
- User stories:
  - As a user, I want to create and edit vault entries.
- Acceptance criteria:
  - Users can create, edit, and delete vault entries.
  - Entries are stored only on-device and not synced.
  - Search is supported locally.

#### FR3: Vault privacy rules
- User stories:
  - As a user, I want assurance that vault data is never used by AI.
- Acceptance criteria:
  - Vault entries are excluded from AI prompts and analytics.
  - No remote backups or sync are performed.

### 3. Technical Specifications

#### Architecture and system design considerations
- Store encrypted entries in local app storage with a key stored in Keychain.
- Gate vault access behind LocalAuthentication prompt.

#### Data models and schemas (proposed)
- Local-only model:
  - `VaultEntry` { id, title, body, createdAt, updatedAt }

#### API endpoints / interfaces
- None (local only).

#### Integration points with existing systems
- Settings screen for enable/disable.
- Journal UI for entry creation.

### 4. User Interface Requirements

#### UI/UX guidelines and mockup descriptions
- Settings toggle: “Enable Private Vault.”
- Vault list screen with lock icon.
- Entry editor similar to notes app.

#### User flow diagram (text)
1. User enables vault in Settings.
2. Face ID prompt unlocks vault.
3. User creates entries.

#### Accessibility requirements
- VoiceOver support for vault unlock and entry list.
- Dynamic Type for entry text.

### 5. Edge Cases and Error Handling
- If biometric auth fails, allow retry with passcode.
- If encryption key is missing, prompt to reset vault (warning of data loss).

### 6. Testing Requirements
- Unit tests: encrypt/decrypt, keychain retrieval.
- UAT: enable vault, add entries, lock/unlock.

### 7. Implementation Notes
- Use CryptoKit AES.GCM for encryption.
- Add a clear disclaimer that entries are local-only.
