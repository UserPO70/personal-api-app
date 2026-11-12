#!/bin/bash
# Signieren ohne Mac: Xcode holt Zertifikat und Profil selbst über den App-Store-Connect-API-Schlüssel
# ("cloud-managed" Zertifikat, -allowProvisioningUpdates). Kein Zertifikats-Repository nötig.
# Archiviert wird unsigniert (eine Entwickler-Signatur bräuchte ein registriertes Gerät),
# signiert wird erst beim Export für den App Store.
# Der Schlüssel liegt nur für die Dauer des Laufs in einer Datei und wird danach gelöscht.
set -euo pipefail

for name in ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8 TEAM_ID; do
  if [ -z "${!name:-}" ]; then
    echo "Fehlt: GitHub-Secret für $name (siehe ANLEITUNG.md)" >&2
    exit 1
  fi
done

# Beim Kopieren am iPhone rutschen leicht Leerzeichen oder Zeilenumbrüche mit hinein.
ASC_KEY_ID="$(printf '%s' "$ASC_KEY_ID" | tr -d '[:space:]')"
ASC_ISSUER_ID="$(printf '%s' "$ASC_ISSUER_ID" | tr -d '[:space:]')"
TEAM_ID="$(printf '%s' "$TEAM_ID" | tr -d '[:space:]')"

ordner="$RUNNER_TEMP/asc"
mkdir -p "$ordner"
schluessel="$ordner/AuthKey_$ASC_KEY_ID.p8"
printf '%s\n' "$ASC_KEY_P8" > "$schluessel"
trap 'rm -rf "$ordner"' EXIT

anmeldung=(-allowProvisioningUpdates
  -authenticationKeyPath "$schluessel"
  -authenticationKeyID "$ASC_KEY_ID"
  -authenticationKeyIssuerID "$ASC_ISSUER_ID")

# Baunummer muss bei jedem Upload steigen: Laufnummer von GitHub.
baunummer="${GITHUB_RUN_NUMBER:-1}"

xcodebuild -project PersonalAPI.xcodeproj -scheme PersonalAPI -configuration Release \
  -destination 'generic/platform=iOS' -archivePath build/PersonalAPI.xcarchive \
  DEVELOPMENT_TEAM="$TEAM_ID" CURRENT_PROJECT_VERSION="$baunummer" \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY="" \
  "${anmeldung[@]}" archive | tail -n 60
test "${PIPESTATUS[0]}" -eq 0

cat > build/ExportOptions.plist <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key><string>app-store-connect</string>
  <key>destination</key><string>upload</string>
  <key>signingStyle</key><string>automatic</string>
  <key>teamID</key><string>$TEAM_ID</string>
  <key>manageAppVersionAndBuildNumber</key><false/>
  <key>uploadSymbols</key><true/>
</dict>
</plist>
EOF

xcodebuild -exportArchive -archivePath build/PersonalAPI.xcarchive \
  -exportOptionsPlist build/ExportOptions.plist -exportPath build/export \
  "${anmeldung[@]}" | tail -n 60
test "${PIPESTATUS[0]}" -eq 0

echo "Hochgeladen: Build $baunummer."
echo "Apple verarbeitet den Build noch 5-30 Minuten, dann erscheint er in TestFlight."
