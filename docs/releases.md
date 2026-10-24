# Releasing SessionMonitor

[← SessionMonitor](../README.md) · [Development](development.md)

GitHub distribution and App Store Connect are separate channels. Release credentials and
signing assets stay on the local Mac, not in GitHub Actions or the repository.

## GitHub: Developer ID + notarization

The pipeline creates a universal arm64/x86_64 DMG with the app, WidgetKit extension, and CLI,
plus a standalone universal CLI ZIP and SHA-256 checksums. App/extension signing uses Developer
ID Application and hardened runtime. The scripts verify signatures, embedded profiles, App Group,
architectures, notarization, stapling, and Gatekeeper acceptance. The CLI ZIP is notarized but
cannot be stapled; its ticket is checked online by Gatekeeper.

Prerequisites:

- A Developer ID Application certificate **with its private key** in the local Keychain.
- An Xcode account for team `P8T2366K8X` and appropriate Developer ID profiles.
- App Group `group.ru.egormerkushev.session-monitor` assigned to both
  `ru.egormerkushev.session-monitor` and `ru.egormerkushev.session-monitor.widget`.
- A local `notarytool` Keychain profile. Never commit keys, certificates, or downloaded profiles.

Prepare only from a clean local `main` synchronized with `origin/main`, after merging the release
changes. `source-revision.txt` pins artifacts to the source commit; publication rejects a mismatch.

```sh
NOTARY_PROFILE=my-notary-profile ALLOW_PROVISIONING_UPDATES=YES make release-github
```

Xcode archives with Automatic signing and exports for Developer ID. Provisioning updates may
create/download profiles via the developer account; they do not create a missing private key.
The default output is `.build/release-github`. Before running locally, direct `RELEASE_ROOT`,
`RELEASE_DERIVED_DATA`, `CLI_SCRATCH_ROOT`, and `SWIFTPM_CACHE_PATH` to your approved build/cache
locations. See [release-github.sh](../scripts/release-github.sh) for supported flags.

### CLI build engine

The GitHub release pipeline uses `CLI_BUILD_SYSTEM=native` for universal CLI slices to avoid
swiftbuild host-macro dependency failures during Intel cross-builds. Native is deprecated by
current SwiftPM; this is a compatibility workaround, not a long-term engine choice.
Set `CLI_BUILD_SYSTEM=swiftbuild` only after validating that the installed toolchain supports
both target architectures and host macros. Product paths are obtained with `--show-bin-path`.

`make release-github-local` skips notarization for local packaging/signing checks. Its output is
not suitable for publication. A signed build alone is not a notarized release.

Publication is a separate step, after inspecting the stapled DMG and checksums:

```sh
NOTARY_PROFILE=my-notary-profile make github-release
```

It requests confirmation, rechecks all three notarization statuses with Apple, creates the
versioned GitHub Release, uploads the DMG/CLI ZIP/checksums, then downloads both binaries and
compares their SHA-256. It requires the same clean synchronized `main` and artifact commit.
See [publish-github-release.sh](../scripts/publish-github-release.sh).

Verify clean installation, first launch, widget data sharing, and preservation of existing
user data separately. Packaging checks do not establish those acceptance criteria.
Automatic updates are not configured by this workflow.

## App Store Connect: local archive and upload

Before preparing a candidate, follow the [current Mac App Store readiness assessment](mac-app-store-readiness.md).
The October 24 preflight identifies sandbox access, persistent folder bookmarks, and shared app/CLI index
behavior as engineering work before a Store candidate; the historical export workflow alone is not readiness evidence.

This path produces an App Store `.pkg`; it does not use the Developer ID release artifacts.
Authorize `asc` locally through Keychain, then run:

```sh
make release-local
```

The Mac needs **Mac App Distribution** and **Mac Installer Distribution** identities with private
keys, and suitable Mac App Store Connect provisioning profiles for the app and extension.
The app’s explicit bundle ID is `ru.egormerkushev.session-monitor`; App Store Connect app ID is
`6812366729`. Inspect installed profiles with:

```sh
asc profiles local list --bundle-id ru.egormerkushev.session-monitor --output table
```

An ASC API key authorizes API/upload access; it does not replace distribution signing identities.
Keep all keys, profiles, archives, and packages outside Git. The local script checks the app/bundle
IDs, archives and exports under ignored `.build/release-local`, then asks before upload.
For an export without upload:

```sh
scripts/release-local.sh --archive-only
```

For missing profiles, allow Xcode to update provisioning via the signed-in developer account:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
ALLOW_PROVISIONING_UPDATES=YES make release-local
```

Use an appropriate stable Xcode for submission. Profile storage locations vary by Xcode version;
manual migration to an old `~/Library/MobileDevice` directory is not required. These commands do
not create a missing distribution certificate/private key or submit the app for review automatically.
