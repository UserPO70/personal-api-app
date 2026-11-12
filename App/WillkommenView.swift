import SwiftUI

/// Erster Start: Server einrichten oder Demo ansehen.
struct WillkommenView: View {
    @EnvironmentObject private var zustand: AppZustand
    @State private var koppeln = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "chart.bar.fill")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(spacing: 8) {
                Text("Personal API")
                    .font(.largeTitle.bold())
                Text("Deine Daten liegen auf deinem eigenen Server im Heimnetz. Die App zeigt sie an und schickt neue dorthin, sonst nirgendwohin.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Spacer()
            VStack(spacing: 12) {
                Button {
                    koppeln = true
                } label: {
                    Text("Server einrichten")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("Demo ansehen") {
                    zustand.demo = true
                }
                .controlSize(.large)
            }
        }
        .padding(24)
        .sheet(isPresented: $koppeln) {
            KoppelnView(einladung: nil)
        }
    }
}
