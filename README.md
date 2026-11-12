# Personal API – iOS-App

Die iPhone-App zu [personal-api](https://github.com/UserPO70/personal-api), einem eigenen Datenserver im Heimnetz. Die App enthält weder Daten noch Geheimnisse. Sie spricht nur mit dem Server, den du einträgst.

**Stand: Probe.** Die App hat erst einen Bildschirm. Er klärt, ob Bauen, Signieren und TestFlight ohne Mac funktionieren und wie sich ein echtes iPhone im Heimnetz verhält. Erst danach entstehen die eigentlichen Funktionen.

## Bauen ohne Mac

Alles läuft auf GitHub Actions (`.github/workflows/app.yml`):

| Auslöser | Was passiert |
|---|---|
| Push, Pull Request | Projekt mit XcodeGen erzeugen, im Simulator bauen. Ohne Geheimnisse. |
| Tag `beta-…` | Zusätzlich signieren und zu TestFlight hochladen (`ci/testflight.sh`) |

Das Xcode-Projekt steht nicht im Repository. `project.yml` beschreibt es, und `xcodegen generate` erzeugt es.

Signiert wird mit einem App-Store-Connect-API-Schlüssel: Xcode holt Zertifikat und Profil selbst (`-allowProvisioningUpdates`). Die einmalige Einrichtung steht in [ANLEITUNG.md](ANLEITUNG.md).

## Was die Probe prüft

1. **Server erreichen (HTTP):** `GET /api/info` an eine IP-Adresse im Heimnetz. Erlaubt nur über `NSAllowsLocalNetworking`, ohne `NSAllowsArbitraryLoads`.
2. **HTTPS mit Fingerabdruck:** Der Server nutzt ein selbst ausgestelltes Zertifikat. Die App vertraut genau dem SHA-256-Fingerabdruck aus `/api/info`. In der fertigen App kommt er aus dem QR-Code.
3. **Testbild senden:** etwa 1–2 MB an `POST /api/app/probe`. Der Server zählt nur die Bytes und speichert nichts.
4. **Im Hintergrund senden:** Hintergrund-Session. Das Ergebnis erscheint im Protokoll, auch wenn die App inzwischen geschlossen war.
5. **Kurzbefehl:** Die Aktion „Testbild senden“ steht in der Kurzbefehle-App, etwa für die Automation „Bei Ankunft zuhause“.

## Prüfliste am iPhone

Im Heim-WLAN:

- [ ] Beim ersten Tippen auf **1** fragt iOS nach dem lokalen Netzwerk → Erlauben. Klappt **1**?
- [ ] **2** (geht nur, wenn am Server HTTPS läuft)
- [ ] **3**: Wie viele Millisekunden?
- [ ] **4** tippen und die App sofort verlassen. Der Server antwortet absichtlich erst nach 30 Sekunden. Nach einer Minute zurück: Steht „angekommen“ im Protokoll?
- [ ] **4** tippen und die App im App-Umschalter ganz wegwischen. Kommt der Upload trotzdem an?
- [ ] Kurzbefehle-App → Automation → „Bei Ankunft“ (Zuhause) oder „WLAN“ → Aktion „Testbild senden“, „Sofort ausführen“. Kommt beim nächsten Heimkommen ein Eintrag?

Außerhalb des WLANs: Was zeigt **1**?

Dann „Kopieren“ beim Protokoll und den Text an Claude schicken.
