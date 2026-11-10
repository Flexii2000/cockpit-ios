import SwiftUI

/// Die Blaetter des Tabs.
private enum FriendsSheet: Identifiable {
    case create, enter

    var id: Self { self }
}

/// Der Freunde-Tab (Vertrag §10.4, Felix 10.11.): je Freund eine Karte mit dem
/// Stand von heute, den vier Serien und den Schritten der Woche. Oben rechts
/// „+“: einen Code erstellen oder einen eingeben - ohne Freunde stehen nur
/// diese beiden Knoepfe da. Entfernt wird ueber langes Druecken.
struct FriendsTab: View {

    @State private var store = FriendsStore()
    @State private var sheet: FriendsSheet?
    @State private var removing: Friend?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    if let error = store.error {
                        ErrorBanner(message: error, isAccessProblem: store.accessProblem)
                    }
                    if !store.hasLoaded {
                        LoadingPlaceholder()
                    } else if store.missing {
                        // Ein Dienst von vor den Freunden: nichts anbieten.
                        EmptyView()
                    } else if store.overview != nil, store.friends.isEmpty {
                        NoFriends(onCreate: { open(.create) }, onEnter: { open(.enter) })
                    } else {
                        ForEach(store.friends) { friend in
                            FriendCard(friend: friend, today: .today(),
                                       isNudging: store.nudging.contains(friend.id),
                                       onNudge: { Task { await store.nudge(friend) } })
                                .contextMenu {
                                    Button("Entfernen", systemImage: "person.badge.minus", role: .destructive) {
                                        removing = friend
                                    }
                                }
                        }
                    }
                }
                .padding(16)
                // Platz fuer die schwebende Tab-Leiste, wie im Dashboard.
                .padding(.bottom, 60)
            }
            .safeAreaInset(edge: .top, spacing: 0) { OfflineBanner(backends: [.weight]) }
            .navigationTitle("Freunde")
            .toolbar {
                if !store.missing {
                    ToolbarItem(placement: .topBarTrailing) {
                        Menu {
                            Button("Code erstellen", systemImage: "number") { open(.create) }
                            Button("Code eingeben", systemImage: "keyboard") { open(.enter) }
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Freund hinzufügen")
                        .accessibilityIdentifier("friendsAdd")
                    }
                }
            }
            .sheet(item: $sheet) { which in
                switch which {
                case .create: InviteCodeSheet(store: store)
                case .enter:  EnterCodeSheet(store: store)
                }
            }
            // Ohne „Abbrechen“: daneben tippen tut dasselbe.
            .confirmationDialog(removing.map { "\($0.name) entfernen?" } ?? "",
                                isPresented: Binding(get: { removing != nil },
                                                     set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Entfernen", role: .destructive) {
                    if let friend = removing { Task { await store.remove(friend) } }
                    removing = nil
                }
            }
            .refreshable { await store.load() }
            .task { await store.load() }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { Task { await store.load() } }
            }
        }
    }

    /// Stupser und die Serien-Warnung kommen als Mitteilung - hier ist klar,
    /// wozu die Erlaubnis gut ist. Erst fragen, dann das Blatt: der Dialog des
    /// Systems laege sonst darueber.
    private func open(_ which: FriendsSheet) {
        Task {
            await Notifications.requestPermission()
            sheet = which
        }
    }
}

/// Ohne Freunde stehen nur die beiden Knoepfe da (Vertrag §10.4).
private struct NoFriends: View {

    let onCreate: () -> Void
    let onEnter: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Button(action: onCreate) {
                Text("Code erstellen").frame(width: 200)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("friendsCreate")
            Button(action: onEnter) {
                Text("Code eingeben").frame(width: 200)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("friendsEnter")
        }
        .controlSize(.large)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }
}
