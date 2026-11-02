import AppKit
import SwiftUI

/// Das Ausklappfenster unter dem Strahlen-Zeichen. Oben die Woche als Ring, darunter
/// die Limits einzelner Modelle und wie sich die Woche verteilt, unten Stand und
/// Knöpfe. Karten und Knöpfe in Liquid Glass (macOS 26).
struct PopoverView: View {

    let model: UsageModel

    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            switch model.phase {
            case .starting:
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 120)
            case .signedOut:
                signIn
            case .challenged:
                challenge
                if let usage = model.usage { content(usage) }
            case .signedIn:
                if let usage = model.usage {
                    content(usage)
                } else {
                    ProgressView()
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, minHeight: 120)
                }
            }
            if let error = model.error {
                Label(error, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
            footer
        }
        .padding(14)
        .frame(width: 320)
        .onAppear {
            model.readLaunchAtLogin()
            Task { await model.refresh(ifOlderThan: 30) }
        }
    }

    // MARK: - Kopf

    private var header: some View {
        HStack(spacing: 7) {
            ClaudeMark(color: ClaudePalette.accent)
                .frame(width: 16, height: 16)
            Text("Claude")
                .font(.headline)
            Spacer()
            if model.isLoading {
                ProgressView()
                    .controlSize(.mini)
            }
        }
    }

    // MARK: - Anmelden

    private var signIn: some View {
        VStack(spacing: 14) {
            ClaudeMark(color: ClaudePalette.accent)
                .frame(width: 44, height: 44)
                .padding(.top, 6)
            Button {
                openLogin()
            } label: {
                Text("Bei Claude anmelden")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .tint(ClaudePalette.accent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity)
        .padding(16)
        .glassCard(cornerRadius: 20)
    }

    private var challenge: some View {
        HStack {
            Label("Browser-Prüfung", systemImage: "checkmark.shield")
                .font(.callout)
            Spacer()
            Button("Öffnen", action: openLogin)
                .buttonStyle(.glass)
        }
        .padding(12)
        .glassCard(cornerRadius: 16, tint: .orange.opacity(0.15))
    }

    private func openLogin() {
        openWindow(id: LoginView.windowID)
        NSApp.activate()
    }

    // MARK: - Inhalt

    @ViewBuilder
    private func content(_ usage: ClaudeUsage) -> some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 10) {
                if let weekly = usage.weekly {
                    WeekCard(limit: weekly, usage: usage)
                }
                let others = ([usage.session].compactMap { $0 } + usage.scoped)
                if !others.isEmpty {
                    VStack(spacing: 10) {
                        ForEach(others) { limit in
                            LimitRow(limit: limit)
                        }
                    }
                    .padding(12)
                    .glassCard(cornerRadius: 16)
                }
                if !usage.breakdown.isEmpty {
                    BreakdownCard(shares: usage.breakdown)
                }
                if let extra = usage.extra {
                    ExtraRow(extra: extra)
                }
            }
        }
    }

    // MARK: - Fuß

    private var footer: some View {
        HStack(spacing: 8) {
            if let lastFetch = model.lastFetch {
                Text("Stand \(ClaudeUsageFormat.time(lastFetch))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer()
            GlassEffectContainer(spacing: 6) {
                HStack(spacing: 6) {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .help("Aktualisieren")
                    .disabled(model.isLoading || model.phase != .signedIn)

                    Menu {
                        Toggle("Beim Anmelden starten", isOn: Binding(
                            get: { model.launchesAtLogin },
                            set: { model.setLaunchesAtLogin($0) }))
                        Button("Nutzung auf claude.ai") {
                            NSWorkspace.shared.open(URL(string: "https://claude.ai/settings/usage")!)
                        }
                        if model.phase == .signedIn || model.phase == .challenged {
                            Divider()
                            Button("Abmelden", role: .destructive) {
                                Task { await model.signOut() }
                            }
                        }
                        Divider()
                        Button("ClaudeUsageBar beenden") {
                            NSApplication.shared.terminate(nil)
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                    }
                    .menuIndicator(.hidden)
                    .help("Mehr")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .controlSize(.regular)
            }
        }
    }
}

// MARK: - Woche

/// Die große Karte: Ring mit Prozent, daneben Reset und wie weit die Woche ist.
/// Die Marke auf dem Ring zeigt, wie viel der Woche vorbei ist - liegt der Bogen
/// dahinter, reicht das Limit.
private struct WeekCard: View {
    let limit: ClaudeUsage.Limit
    let usage: ClaudeUsage

    var body: some View {
        HStack(spacing: 16) {
            UsageRing(percent: limit.percent, elapsed: usage.weekElapsed())
                .frame(width: 92, height: 92)
            VStack(alignment: .leading, spacing: 3) {
                Text("Woche")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                if let resetsAt = limit.resetsAt {
                    Text("Reset \(ClaudeUsageFormat.resetTime(resetsAt))")
                        .font(.callout.weight(.medium))
                    Text(ClaudeUsageFormat.remaining(until: resetsAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let day = ClaudeUsageFormat.weekDay(usage) {
                    Text(day)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .monospacedDigit()
            Spacer(minLength: 0)
        }
        .padding(14)
        .glassCard(cornerRadius: 20, tint: ClaudePalette.level(limit.percent).opacity(0.10))
        .accessibilityElement(children: .combine)
    }
}

private struct UsageRing: View {
    let percent: Double
    let elapsed: Double?

    private let lineWidth: CGFloat = 10

    var body: some View {
        let color = ClaudePalette.level(percent)
        let fraction = min(max(percent / 100, 0), 1)
        ZStack {
            Circle()
                .stroke(ClaudePalette.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(
                    AngularGradient(colors: [color.opacity(0.75), color], center: .center,
                                    startAngle: .degrees(0), endAngle: .degrees(360 * max(fraction, 0.01))),
                    style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
            if let elapsed {
                // Die Zeitmarke: ein kurzer Strich quer über den Ring.
                Capsule()
                    .fill(Color.primary.opacity(0.55))
                    .frame(width: 2, height: lineWidth + 6)
                    .offset(y: -46 + lineWidth / 2)
                    .rotationEffect(.degrees(360 * elapsed))
            }
            Text(ClaudeUsageFormat.percent(percent))
                .font(.system(size: 22, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .padding(lineWidth / 2)
        .accessibilityElement()
        .accessibilityLabel("Woche")
        .accessibilityValue(ClaudeUsageFormat.percent(percent))
    }
}

// MARK: - Weitere Limits

private struct LimitRow: View {
    let limit: ClaudeUsage.Limit

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(limit.title)
                    .font(.callout)
                Spacer()
                Text(ClaudeUsageFormat.percent(limit.percent))
                    .font(.callout.weight(.medium))
                    .foregroundStyle(limit.percent >= 75 ? ClaudePalette.level(limit.percent) : .primary)
            }
            CapsuleBar(fraction: limit.percent / 100, color: ClaudePalette.level(limit.percent))
            if let resetsAt = limit.resetsAt, limit.id == "five_hour" {
                Text("Reset \(ClaudeUsageFormat.resetTime(resetsAt)) · \(ClaudeUsageFormat.remaining(until: resetsAt))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }
}

private struct CapsuleBar: View {
    let fraction: Double
    let color: Color
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { geometry in
            Capsule()
                .fill(color)
                .frame(width: max(height, geometry.size.width * min(max(fraction, 0), 1)))
                .opacity(fraction > 0 ? 1 : 0)
        }
        .frame(height: height)
        .background(ClaudePalette.track, in: Capsule())
        .accessibilityHidden(true)
    }
}

// MARK: - Verteilung

/// Wie sich die Woche auf Claude Code, Chats, Cowork … verteilt - ein geteilter
/// Balken und darunter die Anteile.
private struct BreakdownCard: View {
    let shares: [ClaudeUsage.Share]

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("Verteilung")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            GeometryReader { geometry in
                let total = max(shares.map(\.percent).reduce(0, +), 1)
                let visible = shares.filter { $0.percent > 0 }
                let gaps = CGFloat(max(visible.count - 1, 0)) * 2
                HStack(spacing: 2) {
                    ForEach(visible) { share in
                        Rectangle()
                            .fill(ClaudePalette.share(share.key))
                            .frame(width: max(2, (geometry.size.width - gaps) * share.percent / total))
                    }
                }
            }
            .frame(height: 8)
            .clipShape(Capsule())
            .background(ClaudePalette.track, in: Capsule())
            LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                GridItem(.flexible(), alignment: .leading)],
                      alignment: .leading, spacing: 5) {
                ForEach(shares) { share in
                    HStack(spacing: 5) {
                        Circle()
                            .fill(ClaudePalette.share(share.key))
                            .frame(width: 7, height: 7)
                        Text(share.title)
                            .lineLimit(1)
                        Spacer(minLength: 2)
                        Text(ClaudeUsageFormat.percent(share.percent))
                            .foregroundStyle(.secondary)
                            .padding(.trailing, 8)
                    }
                    .font(.caption)
                    .monospacedDigit()
                }
            }
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }
}

// MARK: - Zusatznutzung

private struct ExtraRow: View {
    let extra: ClaudeUsage.Extra

    var body: some View {
        HStack {
            Label("Zusatznutzung", systemImage: "creditcard")
                .font(.callout)
            Spacer()
            Text(amount)
                .font(.callout.weight(.medium))
                .monospacedDigit()
        }
        .padding(12)
        .glassCard(cornerRadius: 16)
    }

    private var amount: String {
        let used = ClaudeUsageFormat.money(extra.used, currency: extra.currency)
        guard let limit = extra.limit else { return used }
        return "\(used) von \(ClaudeUsageFormat.money(limit, currency: extra.currency))"
    }
}
