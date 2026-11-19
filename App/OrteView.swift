import CryptoKit
import SwiftUI
import WebKit

/// Der Tab „Orte“: wo du an einem Tag warst und wie du dazwischen gefahren bist, darüber der Weg zur Karte.
struct OrteView: View {
    @EnvironmentObject private var zustand: AppZustand
    @ObservedObject private var schlange = Warteschlange.shared
    @ObservedObject private var fahrtenbuch = Fahrtenbuch.shared
    @ObservedObject private var standort = Standort.shared
    @State private var tag = Kalendertag.heute()
    @State private var ortstag: Ortstag?
    @State private var standVon: Date?
    @State private var fehler: String?
    /// Erkannte Orte des Servers (gemerkt): zum Benennen und für die Namen der eigenen Fahrten unterwegs.
    @State private var bekannte: [BekannterOrt] = []
    @State private var blatt: Ortstag.Aufenthalt?
    /// Zählt hoch, wenn sich Orte geändert haben: Die Kartenvorschau lädt dann neu.
    @State private var karteStand = 0

    var body: some View {
        NavigationStack {
            AppListe {
                if zustand.demo {
                    Section {
                        Label("Demo: ausgedachte Daten, kein Server", systemImage: "theatermasks")
                            .foregroundStyle(Color.text2)
                    }
                }
                Section {
                    TagWahl(tag: $tag, heute: Kalendertag.heute())
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                }
                Section {
                    Kartenvorschau(tag: tag)
                        .id("\(tag)|\(karteStand)")
                        .frame(height: 220)
                        .listRowInsets(EdgeInsets())
                        // Ganze Vorschau antippbar, ohne den Pfeil einer Listenzeile.
                        .background {
                            NavigationLink {
                                KarteView(tag: tag)
                                    .alsUnterseite()
                            } label: {
                                EmptyView()
                            }
                            .opacity(0)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("Karte mit den Strecken dieses Tages")
                        .accessibilityHint("Öffnet die Karte zum Verschieben und Zoomen")
                        .accessibilityAddTraits(.isButton)
                }
                unterwegs()
                if let ortstag {
                    ablauf(ortstag)
                } else if let fehler {
                    Section {
                        Label(fehler, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(Color.warnung)
                    }
                } else {
                    Section { ProgressView() }
                }
            }
            .navigationTitle("Orte")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        MeineOrteView()
                            .alsUnterseite()
                    } label: {
                        Label("Meine Orte", systemImage: "list.bullet")
                    }
                }
            }
            .refreshable { await laden() }
            .task(id: tag) { await laden() }
            .sheet(item: $blatt) { aufenthalt in
                OrtBlatt(aufenthalt: aufenthalt, tag: tag,
                         ort: Ortsdienst.ort(zu: aufenthalt.ort, in: bekannte)) {
                    await laden()
                    karteStand += 1
                }
                .environmentObject(zustand)
            }
        }
    }

    // MARK: Unterwegs

    /// Fahrten, die die App selbst erkannt hat und die der Server noch nicht kennt (unterwegs ohne Verbindung,
    /// oder die Punkte sind noch unterwegs zum Server). Kommen sie dort an, ersetzt sie der Ablauf des Servers.
    @ViewBuilder
    private func unterwegs() -> some View {
        let offen = zustand.demo ? [] : Fahrtregel.offen(fahrtenbuch.fahrten, server: ortstag, tag: tag)
        if !offen.isEmpty {
            Section {
                ForEach(offen) { fahrt in
                    eigeneFahrtZeile(fahrt)
                }
            } header: {
                Text("Unterwegs erfasst")
            } footer: {
                Text("Erkannt von der App, noch nicht vom Server ausgewertet. Sobald die Standortpunkte dort sind, "
                     + "stehen die Fahrten mit Strecke im Ablauf.")
            }
        }
    }

    private func eigeneFahrtZeile(_ fahrt: LokaleFahrt) -> some View {
        let start = Fahrtregel.ortsname(lat: fahrt.startLat, lon: fahrt.startLon, orte: bekannte) ?? "Unbekannter Ort"
        let ziel = fahrt.laeuft ? "…"
            : Fahrtregel.ortsname(lat: fahrt.zielLat, lon: fahrt.zielLon, orte: bekannte) ?? "Neuer Ort"
        var teile = [fahrt.beginn.formatted(date: .omitted, time: .shortened)]
        if fahrt.laeuft {
            teile[0] = "seit " + teile[0]
        } else if let minuten = fahrt.minuten {
            teile.append(Dauertext.minuten(minuten))
        }
        if fahrt.meter >= 100 { teile.append(Dauertext.kilometer(fahrt.meter / 1000)) }
        return HStack(alignment: .firstTextBaseline, spacing: Abstand.kachel) {
            Image(systemName: fahrt.laeuft ? "location.fill" : "car.fill")
                .font(.footnote)
                .foregroundStyle(fahrt.laeuft ? Color.orte : Color.text3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(fahrt.laeuft ? "\(start) → unterwegs" : "\(start) → \(ziel)")
                    .font(.subheadline)
                    .foregroundStyle(Color.text2)
                Text(teile.joined(separator: " · "))
                    .font(.footnote)
                    .foregroundStyle(Color.text3)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: Ablauf

    @ViewBuilder
    private func ablauf(_ ortstag: Ortstag) -> some View {
        let schritte = ortstag.ablauf
        Section {
            if schritte.isEmpty {
                Text("Für diesen Tag gibt es keine Orte. Läuft der Standort in den Einstellungen?")
                    .foregroundStyle(Color.text2)
            }
            ForEach(schritte) { schritt in
                switch schritt {
                case .ort(let aufenthalt):
                    if !zustand.demo, aufenthalt.lat != nil {
                        Button {
                            blatt = aufenthalt
                        } label: {
                            ortZeile(aufenthalt, tag: ortstag.tag)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Benennen oder als „Kein Halt“ ausblenden")
                    } else {
                        ortZeile(aufenthalt, tag: ortstag.tag)
                    }
                case .fahrt(let fahrt):
                    fahrtZeile(fahrt)
                }
            }
        } header: {
            Text("Ablauf")
        } footer: {
            VStack(alignment: .leading, spacing: Abstand.winzig) {
                if let standVon {
                    Text("Server nicht erreichbar. Stand von \(standVon.formatted(date: .abbreviated, time: .shortened)).")
                }
                if !zustand.demo, standort.wartend > 0, tag == Kalendertag.heute() {
                    Text("\(standort.wartend) Standortpunkte warten auf den Server.")
                }
                if !zustand.demo, !ortstag.ablauf.isEmpty {
                    Text("Einen Ort antippen, um ihn zu benennen oder als „Kein Halt“ auszublenden.")
                }
            }
        }
    }

    private func ortZeile(_ aufenthalt: Ortstag.Aufenthalt, tag: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.kachel) {
            Image(systemName: aufenthalt.ort == "Zuhause" ? "house.fill" : "mappin.circle.fill")
                .foregroundStyle(Color.orte)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Abstand.eng) {
                    Text(aufenthalt.ort)
                    if aufenthalt.neu == true {
                        Text("neu")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.flaeche2, in: Capsule())
                            .foregroundStyle(Color.text2)
                    }
                }
                Text(Zeitpunkt.spanne(aufenthalt.beginn, aufenthalt.ende, tag: tag))
                    .font(.footnote)
                    .foregroundStyle(Color.text2)
                    .monospacedDigit()
            }
            Spacer(minLength: Abstand.eng)
            if let minuten = aufenthalt.minuten {
                Text(Dauertext.minuten(minuten))
                    .monospacedDigit()
                    .foregroundStyle(Color.text2)
            }
        }
        .foregroundStyle(Color.text)
        .accessibilityElement(children: .combine)
    }

    private func fahrtZeile(_ fahrt: Ortstag.Fahrt) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Abstand.kachel) {
            Image(systemName: "car.fill")
                .font(.footnote)
                .foregroundStyle(Color.text3)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(fahrt.start) → \(fahrt.ziel)")
                    .font(.subheadline)
                    .foregroundStyle(Color.text2)
                Text(fahrtText(fahrt))
                    .font(.footnote)
                    .foregroundStyle(Color.text3)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }

    private func fahrtText(_ fahrt: Ortstag.Fahrt) -> String {
        var teile: [String] = []
        if let von = Zeitpunkt.lesen(fahrt.abfahrt) { teile.append(von.formatted(date: .omitted, time: .shortened)) }
        if let dauer = fahrt.dauerMin { teile.append(Dauertext.minuten(dauer)) }
        if let km = fahrt.streckeKm { teile.append(Dauertext.kilometer(km)) }
        if fahrt.korrigiert == true { teile.append("von Hand korrigiert") }
        return teile.joined(separator: " · ")
    }

    // MARK: Laden

    private func laden() async {
        if zustand.demo {
            ortstag = Ortstag.demo(tag: tag)
            return
        }
        let merkname = "orte-\(tag)"
        await bekannteLaden()
        do {
            let neu = try await zustand.api().lesen(Ortstag.self, "GET", "/api/dashboard/karte?tag=\(tag)")
            ortstag = neu
            standVon = nil
            fehler = nil
            schlange.merken(neu, als: merkname)
        } catch {
            if Task.isCancelled { return }
            if let (alt, wann) = schlange.gemerkt(Ortstag.self, merkname) {
                ortstag = alt
                standVon = wann
            } else {
                ortstag = nil
                fehler = Api.text(error)
            }
        }
    }

    private func bekannteLaden() async {
        do {
            let neu = try await zustand.api().lesen([BekannterOrt].self, "GET", "/api/orte")
            bekannte = neu
            schlange.merken(neu, als: "orte-liste")
        } catch {
            if bekannte.isEmpty, let (alt, _) = schlange.gemerkt([BekannterOrt].self, "orte-liste") {
                bekannte = alt
            }
        }
    }
}

// MARK: Karte

/// Die Karte des Tages als Vorschau in der Liste: nicht verschiebbar, damit Wischen weiter die Tabs wechselt.
struct Kartenvorschau: View {
    let tag: String

    @EnvironmentObject private var zustand: AppZustand
    @State private var fehler: String?
    @State private var laedt = true

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.flaeche2
            if zustand.demo {
                platzhalter("In der Demo gibt es keine Karte.")
            } else if let verbindung = zustand.verbindung,
                      let adresse = try? Server.url(verbindung.adresse, "/karte?tag=\(tag)") {
                Kartenfenster(adresse: adresse, fingerabdruck: verbindung.fingerabdruck, vorschau: true,
                              fehler: $fehler, laedt: $laedt)
                    .allowsHitTesting(false)
                if let fehler {
                    platzhalter(fehler)
                } else if laedt {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                platzhalter("Kein Server gekoppelt.")
            }
            Label("Karte öffnen", systemImage: "arrow.up.left.and.arrow.down.right")
                .font(.footnote.weight(.semibold))
                .padding(.horizontal, Abstand.kachel)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .padding(Abstand.kachel)
        }
        .contentShape(Rectangle())
    }

    private func platzhalter(_ text: String) -> some View {
        Label(text, systemImage: "map")
            .font(.footnote)
            .foregroundStyle(Color.text2)
            .multilineTextAlignment(.center)
            .padding(Abstand.rand)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Die Offline-Karte des Servers (`/karte`): Kacheln, Strecken und Orte kommen vom eigenen Server, nichts von Apple
/// oder anderen Kartendiensten. Eine eigene Seite, weil Wischen auf der Karte sonst den Tab wechseln würde.
struct KarteView: View {
    let tag: String

    @EnvironmentObject private var zustand: AppZustand
    @State private var fehler: String?
    @State private var laedt = true

    var body: some View {
        ZStack {
            Color.grund.ignoresSafeArea()
            if zustand.demo {
                hinweis("In der Demo gibt es keine Karte. Sie kommt von deinem eigenen Server.")
            } else if let verbindung = zustand.verbindung, let adresse = try? Server.url(verbindung.adresse, "/karte?tag=\(tag)") {
                Kartenfenster(adresse: adresse, fingerabdruck: verbindung.fingerabdruck, vorschau: false,
                              fehler: $fehler, laedt: $laedt)
                    .ignoresSafeArea(edges: .bottom)
                if let fehler {
                    hinweis(fehler)
                } else if laedt {
                    ProgressView()
                }
            } else {
                hinweis("Kein Server gekoppelt.")
            }
        }
        .navigationTitle(Kalendertag.name(tag, heute: Kalendertag.heute()))
        .navigationBarTitleDisplayMode(.inline)
    }

    private func hinweis(_ text: String) -> some View {
        Label(text, systemImage: "map")
            .foregroundStyle(Color.text2)
            .multilineTextAlignment(.center)
            .padding(Abstand.abschnitt)
    }
}

/// Zeigt die Kartenseite des Servers. Kopf und Leiste des Dashboards werden ausgeblendet, Links zu anderen Seiten
/// bleiben zu: In der App gibt es dafür eigene Bildschirme. Bei HTTPS gilt nur der Fingerabdruck aus dem QR-Code.
struct Kartenfenster: UIViewRepresentable {
    let adresse: URL
    let fingerabdruck: String?
    /// Als Vorschau: ohne Knöpfe und Maßstab, nicht bedienbar.
    let vorschau: Bool
    @Binding var fehler: String?
    @Binding var laedt: Bool

    /// Blendet die Navigation des Dashboards aus, damit nur die Karte bleibt.
    static let einbetten = """
    (function () {
      var stil = document.createElement("style");
      stil.textContent = "#kopf, nav.leiste, #blatt-mehr { display: none !important; } " +
        "body { padding-bottom: 0 !important; }";
      document.documentElement.appendChild(stil);
    })();
    """

    /// In der Vorschau zusätzlich Zoom-Knöpfe und Maßstab weg. Der Hinweis auf OpenStreetMap bleibt (Lizenz),
    /// aber klein, ohne Kasten und blass in der Ecke.
    static let vorschauStil = """
    (function () {
      var stil = document.createElement("style");
      stil.textContent = ".maplibregl-ctrl-top-right, .maplibregl-ctrl-bottom-left { display: none !important; } " +
        ".maplibregl-ctrl.maplibregl-ctrl-attrib { background: none !important; font-size: 8px !important; " +
        "line-height: 1.2 !important; padding: 0 8px 4px !important; margin: 0 !important; opacity: 0.75; } " +
        ".maplibregl-ctrl-attrib a { color: inherit !important; }";
      document.documentElement.appendChild(stil);
    })();
    """

    func makeCoordinator() -> Coordinator {
        Coordinator(adresse: adresse, fingerabdruck: fingerabdruck, fehler: $fehler, laedt: $laedt)
    }

    func makeUIView(context: Context) -> WKWebView {
        let einstellungen = WKWebViewConfiguration()
        // Nichts auf dem iPhone speichern: Die Seite lädt jedes Mal frisch vom Server.
        einstellungen.websiteDataStore = .nonPersistent()
        einstellungen.userContentController.addUserScript(
            WKUserScript(source: Self.einbetten, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        if vorschau {
            einstellungen.userContentController.addUserScript(
                WKUserScript(source: Self.vorschauStil, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        let fenster = WKWebView(frame: .zero, configuration: einstellungen)
        fenster.navigationDelegate = context.coordinator
        fenster.isOpaque = false
        fenster.backgroundColor = UIColor(named: Farbe.grund.rawValue)
        fenster.scrollView.bounces = false
        fenster.allowsBackForwardNavigationGestures = false
        if vorschau {
            fenster.isUserInteractionEnabled = false
            fenster.scrollView.isScrollEnabled = false
        }
        fenster.load(URLRequest(url: adresse))
        return fenster
    }

    func updateUIView(_ fenster: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let adresse: URL
        let erwartet: String?
        var fehler: Binding<String?>
        var laedt: Binding<Bool>

        init(adresse: URL, fingerabdruck: String?, fehler: Binding<String?>, laedt: Binding<Bool>) {
            self.adresse = adresse
            self.erwartet = fingerabdruck?.lowercased().replacingOccurrences(of: ":", with: "")
            self.fehler = fehler
            self.laedt = laedt
        }

        /// Nur die Kartenseite selbst; Links zu „Meine Orte“ und Co. bleiben zu.
        func webView(_ webView: WKWebView, decidePolicyFor aktion: WKNavigationAction) async -> WKNavigationActionPolicy {
            guard let ziel = aktion.request.url else { return .cancel }
            let gleicherServer = ziel.host == adresse.host && ziel.port == adresse.port && ziel.scheme == adresse.scheme
            return gleicherServer && ziel.path == adresse.path ? .allow : .cancel
        }

        func webView(_ webView: WKWebView,
                     respondTo challenge: URLAuthenticationChallenge) async -> (URLSession.AuthChallengeDisposition, URLCredential?) {
            guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
                  let trust = challenge.protectionSpace.serverTrust else {
                return (.performDefaultHandling, nil)
            }
            guard let erwartet, challenge.protectionSpace.host == adresse.host,
                  let blatt = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first else {
                return (.cancelAuthenticationChallenge, nil)
            }
            let abdruck = SHA256.hash(data: SecCertificateCopyData(blatt) as Data).map { String(format: "%02x", $0) }.joined()
            return abdruck == erwartet ? (.useCredential, URLCredential(trust: trust)) : (.cancelAuthenticationChallenge, nil)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            laedt.wrappedValue = false
            fehler.wrappedValue = nil
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            gescheitert(error)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            gescheitert(error)
        }

        private func gescheitert(_ error: Error) {
            // Abgebrochene Links (siehe oben) sind kein Fehler.
            if (error as NSError).code == NSURLErrorCancelled { return }
            laedt.wrappedValue = false
            fehler.wrappedValue = "Die Karte lässt sich nicht laden: \(Server.beschreibung(error))"
        }
    }
}
