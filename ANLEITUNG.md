# Einmalige Einrichtung: Apple und GitHub

Diese Schritte macht der Besitzer des Apple-Kontos selbst. Schlüssel und Passwörter gibst du nur bei Apple und GitHub ein, nirgends sonst.

Alles geht im Browser, auch am iPhone. Nur Schritt 6 ist an einem Computer bequemer.

## 1. Vereinbarungen unterschreiben

[App Store Connect](https://appstoreconnect.apple.com) → Geschäftliches → **Verträge**: die offene Vereinbarung annehmen. Ohne sie lässt sich nichts hochladen.

Den EU-Händlerstatus (roter Kasten) und den Rechtsträger (blauer Kasten) brauchst du für TestFlight nicht. Sie kommen erst vor dem App Store dran.

## 2. Bundle-ID anmelden

[developer.apple.com/account](https://developer.apple.com/account) → Certificates, IDs & Profiles → **Identifiers** → „+“

- Typ: **App IDs**, dann **App**
- Description: `Personal API`
- Bundle ID: **Explicit**, `io.github.userpo70.personalapi`
- Capabilities: nichts ankreuzen → Continue → Register

## 3. App-Eintrag anlegen

App Store Connect → **Apps** → „+“ → **Neue App**

- Plattform: iOS
- Name: `Personal API`. Ist der Name schon vergeben, nimm einen anderen, etwa „Personal API Probe“. Ändern lässt er sich später.
- Primärsprache: Deutsch
- Bundle-ID: die aus Schritt 2
- SKU: `personalapi` (nur intern, beliebig)
- Benutzerzugriff: Vollständiger Zugriff

## 4. API-Schlüssel anlegen

App Store Connect → **Benutzer und Zugriff** → **Integrationen** → App Store Connect API → Teamschlüssel.

Beim ersten Mal musst du den Zugriff anfordern. Das wird sofort bestätigt.

- „+“, Name: `GitHub`
- Zugriff: **Admin**. Nur damit darf der Bauserver das Signier-Zertifikat selbst anlegen.
- **API-Schlüssel laden:** Die Datei `AuthKey_XXXXXXXXXX.p8` gibt es **nur einmal**. Gut aufheben und niemandem schicken.
- Von derselben Seite notieren: **Schlüssel-ID** (10 Zeichen) und oben die **Aussteller-ID** (eine lange Kennung mit Bindestrichen).

## 5. Team-ID notieren

[developer.apple.com/account](https://developer.apple.com/account) → **Mitgliedschaft** (Membership details) → **Team-ID**, 10 Zeichen.

## 6. GitHub-Secrets eintragen

[github.com/UserPO70/personal-api-app](https://github.com/UserPO70/personal-api-app) → Settings → Secrets and variables → **Actions** → New repository secret. Vier Einträge:

| Name | Inhalt |
|---|---|
| `ASC_KEY_ID` | Schlüssel-ID aus Schritt 4 |
| `ASC_ISSUER_ID` | Aussteller-ID aus Schritt 4 |
| `APPLE_TEAM_ID` | Team-ID aus Schritt 5 |
| `ASC_KEY_P8` | der **ganze Inhalt** der `.p8`-Datei, mit den Zeilen `-----BEGIN PRIVATE KEY-----` und `-----END PRIVATE KEY-----` |

Für `ASC_KEY_P8` die `.p8`-Datei an einem Computer mit einem Texteditor öffnen und alles kopieren.

Geht das nur am Server: Die Datei dort speichern, etwa im Ordner Downloads. Dann in Claude Code selbst eintippen:

```
! gh secret set ASC_KEY_P8 -R UserPO70/personal-api-app < "$HOME\Downloads\AuthKey_XXXXXXXXXX.p8"
```

Der Befehl zeigt den Inhalt nicht an. Danach die Datei an einen sicheren Ort verschieben oder löschen.

## 7. Bescheid sagen

Danach startet Claude den ersten Lauf mit Signieren und Hochladen. Nach 5 bis 30 Minuten Verarbeitung bei Apple:

- App Store Connect → die App → **TestFlight** → Interne Tests → Gruppe anlegen und dich selbst als Tester hinzufügen.
- Am iPhone die App **TestFlight** aus dem App Store laden und die Probe installieren.
- Die [Prüfliste](README.md#prüfliste-am-iphone) durchgehen.
