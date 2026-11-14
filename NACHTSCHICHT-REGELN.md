# Regeln für die Nachtschicht in diesem Repository

Die Nachtschicht arbeitet eigentlich nur am Server-Projekt. Aufgaben, die dort in `NACHTSCHICHT.md` als **App-Aufgabe** gekennzeichnet sind, dürfen dieses Repository ändern. Dafür gilt, zusätzlich zu den Regeln der Nachtschicht:

## Dieses Repository ist öffentlich

- Nichts Persönliches hineinschreiben: keine echten Adressen aus dem Heimnetz, keine Namen von Personen, Rechnern oder WLANs, keine Pfade des Servers, keine Schlüssel, keine echten Daten. Beispiele immer mit ausgedachten Werten.
- Commits nur mit der im Repository eingestellten noreply-Adresse von GitHub (`git config user.email` nicht ändern).
- GitHub-Secrets, `ci/testflight.sh`, `.github/workflows/app.yml` und `PersonalAPI.entitlements` nicht ändern. Braucht eine Aufgabe das, als Frage an den User notieren.

## Bauen und testen ohne Mac

- Es gibt hier keinen Swift-Compiler. Gebaut und getestet wird bei GitHub: `git push` auf `main` startet den Lauf (XcodeGen, Bauen, Tests im Simulator).
- Auf das Ergebnis warten: `gh run list --limit 1` für die Nummer, dann `gh run watch <nummer> --exit-status`, Fehler mit `gh run view <nummer> --log | grep -E "error:|failed|Executed"`.
- Schlägt der Lauf fehl: Ursache beheben und erneut pushen, höchstens fünf Versuche. Danach die Aufgabe als teilweise erledigt im Bericht vermerken, mit der letzten Fehlermeldung, und den Stand so hinterlassen, dass `main` baut (fehlerhaften Teil zurücknehmen).
- Bricht ein Lauf ohne Bauserver ab („not acquired by Runner“) oder hängt er in der Warteschlange: `gh run rerun <nummer>` bzw. warten, das ist kein Fehler im Code.
- Swift-Dateien nur mit den Datei-Werkzeugen schreiben und ändern, nicht per `sed` oder Heredoc: Backslashes in `\(…)` gehen dabei verloren.
- Typnamen gelten in der ganzen App: vor einem neuen Typ mit `grep` prüfen, ob es den Namen schon gibt.

## Was zu einer App-Aufgabe gehört

- Die Regeln, die sich ohne Oberfläche prüfen lassen (Anfragen bauen, Antworten lesen, Rechnen, Zustände), stehen in eigenen Typen ohne SwiftUI und haben Tests in `Tests/`.
- Antworten des Servers werden gegen die Beispielantworten geprüft: die passenden Dateien aus `tests/app-beispiele/` des Server-Projekts nach `Tests/Beispiele/` kopieren. Sie enthalten nur erzeugte Testdaten.
- Keine fremden Bibliotheken, nur Frameworks von Apple. Ziel ist iOS 17, nur iPhone.
- Aussehen nach dem Designkonzept des Server-Projekts (`APP-DESIGN.md`): Bereichsfarben nur in Symbolen und Flächen, Text in den Textfarben, hell und dunkel.
- Wortwahl: „Server“, nie „Laptop“. Bei Kalorien und Gewicht sachlich, ohne Bewertung; Schätzungen heißen Schätzungen.
- Gesundheits- und Standortdaten gehen nie an Claude; neue Funktionen dürfen daran nichts ändern.
- Alles, was der Server nicht erreicht, muss ehrlich angezeigt werden (letzter Stand mit Zeitpunkt, oder ein klarer Hinweis). Ändern und Löschen gehen nur mit Verbindung, sofern die Aufgabe nichts anderes sagt.

## Version und TestFlight

- Für eine fertige App-Aufgabe die Version in `project.yml` (`MARKETING_VERSION`) an der zweiten Stelle erhöhen, für eine Korrektur an der dritten.
- Ist der Lauf auf `main` grün, mit dem Tag `beta-<version>-<n>` zu TestFlight hochladen (`git tag …`, `git push origin <tag>`), den Lauf abwarten. Höchstens ein Upload je Aufgabe.
- Der Upload zeigt nur, dass die App baut und die Tests bestehen. Am iPhone hat sie dann noch niemand gesehen.

## Bericht

Im Bericht des Server-Projekts (`berichte/<datum>.md`) je App-Aufgabe: was gebaut ist, Version und Build-Nummer, was die Tests abdecken, und eine kurze Liste „Am iPhone auszuprobieren“ mit den Schritten für den User. Dazu der Stand in `APP-PLAN.md` des Server-Projekts.
