# Skylight Bridge Safeguards Review

Author: Oliver Ames
Date: October 6, 2026

Skylight Bridge's local authenticator now reads an existing integrity key when opening a protected file. A missing key produces a distinct error without creating a replacement. First-write key creation remains in the sealing path.

Thirteen standalone synthetic fixtures passed, with zero failures or skips. They covered existing and missing keys, access denial, wrong keys, malformed envelopes, unsupported versions, tampering, first-write creation and reuse, timestamp precision and compatible version-one envelopes.

The harness compiles exactly the authenticator and memory fixtures. It does not launch the app, access Keychain, query CloudKit or access Photos. Bash syntax and shellcheck passed. The complete package suite was excluded because it initializes production application services. A single-commit CI skip marker prevents that broader suite from starting automatically, without changing workflow configuration.

The key service, account names, key size, access policy, signed envelope version and date compatibility remain unchanged. This is a source safeguard, not an installed migration. No existing file or credential was read, replaced or reset.

## Remaining Gates

On October 6, 2026, the former account showed iOS record 6809008416 under Removed Apps, with a September 14 removal date. Its visible 1.0 history records Prepare for Submission on September 5. The historical draft was restored with Limited Access restricted to Oliver Ames, the sole listed account user. A refreshed App Information page confirms the record is editable and restored, but offers no Transfer App control.

[Apple requires at least one released App Store version for ordinary transfer](https://developer.apple.com/help/app-store-connect/transfer-an-app/app-transfer-criteria/). The observed draft history does not establish that prerequisite. [Apple also documents CloudKit ownership and shared-container transfer consequences](https://developer.apple.com/help/app-store-connect/transfer-an-app/overview-of-app-transfer/). A support request asking for a route that preserves both clients and their private cloud data is prepared, but has not been sent.

Both Mac and iOS clients retain their original identifiers, signing settings and cloud container. Restoring the record did not transfer ownership or change customer data.

Cross-signature access to synthetic integrity keys, complete app packaging and Mac/iPhone cloud continuity remain unverified. Keep the current clients and data intact until those gates pass.
