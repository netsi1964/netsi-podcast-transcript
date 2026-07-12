import SwiftUI

/// About window: credits, author bio, links, and a Buy Me a Coffee button.
struct AboutView: View {
    private let repoURL = URL(string: "https://github.com/netsi1964/netsi-podcast-transcript")!
    private let websiteURL = URL(string: "https://netsi.dk")!
    private let coffeeURL = URL(string: "https://buymeacoffee.com/netsi1964")!
    private let linkedInURL = URL(string: "https://www.linkedin.com/in/stenhougaard/")!
    private let xURL = URL(string: "https://x.com/netsi1964")!

    var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: AppIcon.image(size: 128))
                .resizable()
                .frame(width: 96, height: 96)
                .clipShape(RoundedRectangle(cornerRadius: 21))
                .shadow(radius: 4, y: 2)

            VStack(spacing: 4) {
                Text("Podcast Transcript Studio").font(.title2.bold())
                Text("Version 0.9.5 · lokal-first macOS-app").font(.caption).foregroundStyle(.secondary)
            }

            Text("Lavet med **Claude Code** af **Sten Hougaard** (netsi1964).")
                .multilineTextAlignment(.center)

            Divider()

            VStack(spacing: 6) {
                Text("Om Sten").font(.headline)
                Text("Softwareudvikler og AI-specialist med 20+ års erfaring, baseret i Aarhus. "
                     + "Arbejder med LLM-baserede assistenter, prompt engineering, MCP-servere og "
                     + "AI-integrerede løsninger — med fokus på bæredygtig, etisk og menneske-centreret AI.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Buy Me a Coffee — matches the button on netsi.dk/blog.
            Link(destination: coffeeURL) {
                HStack(spacing: 8) {
                    Text("☕️").font(.title3)
                    Text("Buy me a coffee").fontWeight(.semibold)
                }
                .padding(.horizontal, 18).padding(.vertical, 10)
                .foregroundStyle(.black)
                .background(Color(red: 1.0, green: 0.86, blue: 0.13), in: Capsule())
            }
            .buttonStyle(.plain)
            .help("Støt udvikleren på Buy Me a Coffee")

            HStack(spacing: 18) {
                Link("GitHub-repo", destination: repoURL)
                Link("netsi.dk", destination: websiteURL)
                Link("LinkedIn", destination: linkedInURL)
                Link("X", destination: xURL)
            }
            .font(.callout)

            Text("© \(Calendar.current.component(.year, from: .now)) Sten Hougaard")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(28)
        .frame(width: 440)
    }
}
