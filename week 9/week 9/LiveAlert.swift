// xcode: set sdk=iOS

import SwiftUI
import MapKit
import FirebaseCore
import FirebaseAuth
import FirebaseFirestore

// MARK: - Firebase setup

enum FirebaseSetup {
    // GoogleService-Info.plist is not in the repo (each person makes their own
    // Firebase project). Without it, FirebaseApp.configure() would crash, so the
    // app still works and the Live alert parts just say they aren't set up.
    static var isConfigured: Bool {
        FirebaseApp.app() != nil
    }

    static func configure() {
        guard FirebaseApp.app() == nil,
              Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else { return }
        FirebaseApp.configure()
    }

    // Anonymous sign-in: no account or password. It gives this phone an ID, so the
    // security rules can tell who started an alert and who is answering it.
    static func signIn() async throws -> User {
        if let user = Auth.auth().currentUser { return user }
        return try await Auth.auth().signInAnonymously().user
    }
}

// MARK: - The alert as stored in Firestore

// One document per alert: alerts/{code}. The code is the document ID, so a
// contact only needs those 6 characters to find it.
struct LiveAlert {
    var name: String
    var message: String
    var isActive: Bool
    var startedAt: Date?
    var updatedAt: Date?
    var latitude: Double?
    var longitude: Double?
    var accuracy: Double?
    var responders: [Responder]

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(data: [String: Any]) {
        name = data["name"] as? String ?? ""
        message = data["message"] as? String ?? ""
        isActive = (data["status"] as? String) == "active"
        startedAt = (data["startedAt"] as? Timestamp)?.dateValue()
        updatedAt = (data["updatedAt"] as? Timestamp)?.dateValue()
        latitude = data["latitude"] as? Double
        longitude = data["longitude"] as? Double
        accuracy = data["accuracy"] as? Double
        let map = data["responders"] as? [String: [String: Any]] ?? [:]
        responders = map.map { id, value in
            Responder(
                id: id,
                name: value["name"] as? String ?? "Someone",
                status: Responder.Status(rawValue: value["status"] as? String ?? "") ?? .seen,
                at: (value["at"] as? Timestamp)?.dateValue()
            )
        }
        .sorted { ($0.at ?? .distantPast) < ($1.at ?? .distantPast) }
    }
}

struct Responder: Identifiable, Equatable {
    enum Status: String {
        case seen, onTheWay, cantCome

        var text: String {
            switch self {
            case .seen: "saw your alert"
            case .onTheWay: "is on the way"
            case .cantCome: "can't come, call someone else"
            }
        }

        var symbol: String {
            switch self {
            case .seen: "eye.fill"
            case .onTheWay: "figure.run"
            case .cantCome: "xmark.circle.fill"
            }
        }
    }

    let id: String
    let name: String
    let status: Status
    let at: Date?
}

func alertDocument(_ code: String) -> DocumentReference {
    Firestore.firestore().collection("alerts").document(code)
}

// No 0/O or 1/I/L, so a code read out over the phone can't be typed wrong.
func makeAlertCode() -> String {
    let letters = Array("ABCDEFGHJKMNPQRSTUVWXYZ23456789")
    return String((0..<6).map { _ in letters.randomElement()! })
}

func cleanedCode(_ text: String) -> String {
    String(text.uppercased().filter { $0.isLetter || $0.isNumber }.prefix(6))
}

// MARK: - Sharing your alert (the person who held SOS)

@Observable
@MainActor
final class LiveAlertSharer {
    enum State: Equatable {
        case notSetUp, starting, live, failed(String), ended
    }

    var state: State = FirebaseSetup.isConfigured ? .starting : .notSetUp
    var code: String?
    var responders: [Responder] = []

    private var listener: ListenerRegistration?
    private var lastSent: CLLocation?
    private var lastSentAt = Date.distantPast
    private var pendingLocation: CLLocation?

    // The line added to every text, so the contact knows how to follow along.
    var shareLine: String? {
        guard state == .live, let code else { return nil }
        return "Follow my live location in the SOS app: Follow tab, code \(code)"
    }

    func start(name: String, message: String) async {
        guard FirebaseSetup.isConfigured, code == nil else { return }
        state = .starting
        do {
            let user = try await FirebaseSetup.signIn()
            let newCode = makeAlertCode()
            try await alertDocument(newCode).setData([
                "ownerUID": user.uid,
                "name": name.isEmpty ? "Your friend" : name,
                "message": message,
                "status": "active",
                "startedAt": FieldValue.serverTimestamp(),
                "updatedAt": FieldValue.serverTimestamp(),
                "responders": [String: Any](),
            ])
            code = newCode
            state = .live
            listen(to: newCode)
            if let pendingLocation {
                send(pendingLocation)
            }
        } catch {
            print("Live alert error:", error)
            state = .failed(error.localizedDescription)
        }
    }

    // Called every time the phone gets a new location. Firestore writes cost
    // battery and data, so only send when you moved 15 m or 10 seconds passed.
    func locationChanged(_ location: CLLocation?) {
        guard let location else { return }
        guard state == .live else {
            pendingLocation = location
            return
        }
        let moved = lastSent.map { location.distance(from: $0) } ?? .infinity
        if moved > 15 || Date.now.timeIntervalSince(lastSentAt) > 10 {
            send(location)
        }
    }

    private func send(_ location: CLLocation) {
        guard let code else { return }
        lastSent = location
        lastSentAt = .now
        alertDocument(code).updateData([
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "accuracy": location.horizontalAccuracy,
            "updatedAt": FieldValue.serverTimestamp(),
        ])
    }

    private func listen(to code: String) {
        listener = alertDocument(code).addSnapshotListener { [weak self] snapshot, error in
            guard let self, let data = snapshot?.data() else { return }
            self.responders = LiveAlert(data: data).responders
        }
    }

    // Swiping the alert away stops sharing. The location stays in the document
    // so the contact can see the last place, but it says the alert ended.
    func end() {
        listener?.remove()
        listener = nil
        if let code, state == .live {
            alertDocument(code).updateData([
                "status": "ended",
                "updatedAt": FieldValue.serverTimestamp(),
            ])
        }
        if state != .notSetUp {
            state = .ended
        }
    }
}

// Shown at the top of the alert screen.
struct LiveAlertCard: View {
    let sharer: LiveAlertSharer

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch sharer.state {
            case .notSetUp:
                Label("Live alert is off", systemImage: "antenna.radiowaves.left.and.right.slash")
                    .font(.headline)
                Text("Add GoogleService-Info.plist to share your location live.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            case .starting:
                Label {
                    Text("Starting live alert…")
                } icon: {
                    ProgressView().tint(.white)
                }
                .font(.headline)
            case .failed(let reason):
                Label("Live alert couldn't start", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                Text(reason)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            case .live, .ended:
                HStack {
                    Label("Live alert on", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                        .symbolEffect(.variableColor.iterative, isActive: sharer.state == .live)
                    Spacer()
                    if let code = sharer.code {
                        Text(code)
                            .font(.title3.monospaced().weight(.bold))
                            .textSelection(.enabled)
                            .accessibilityLabel("Code \(code.map(String.init).joined(separator: " "))")
                    }
                }
                if sharer.responders.isEmpty {
                    Text("Your texts include this code. Waiting for someone to open it…")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                } else {
                    ForEach(sharer.responders) { responder in
                        ResponderRow(responder: responder)
                    }
                }
            }
        }
        .foregroundStyle(.white)
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        // A strong buzz when someone says they're coming, so you know without looking.
        .sensoryFeedback(.success, trigger: sharer.responders.filter { $0.status == .onTheWay }.count) { old, new in
            new > old
        }
    }
}

struct ResponderRow: View {
    let responder: Responder

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: responder.status.symbol)
                .frame(width: 24)
                .foregroundStyle(responder.status == .onTheWay ? .green : .white.opacity(0.8))
            VStack(alignment: .leading, spacing: 1) {
                Text("\(responder.name) \(responder.status.text)")
                    .font(.subheadline.weight(.semibold))
                if let at = responder.at {
                    Text("\(Text(at, style: .relative)) ago")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                }
            }
        }
    }
}

// MARK: - Following a friend's alert (the emergency contact)

@Observable
@MainActor
final class AlertFollower {
    var code = ""
    var alert: LiveAlert?
    var notFound = false
    var isLoading = false
    var errorText: String?

    private var listener: ListenerRegistration?
    private var myUID: String?

    var myStatus: Responder.Status? {
        alert?.responders.first { $0.id == myUID }?.status
    }

    func follow(_ code: String, myName: String) async {
        stop()
        self.code = code
        isLoading = true
        notFound = false
        errorText = nil
        do {
            let user = try await FirebaseSetup.signIn()
            myUID = user.uid
            let snapshot = try await alertDocument(code).getDocument()
            guard snapshot.exists else {
                notFound = true
                isLoading = false
                return
            }
            listener = alertDocument(code).addSnapshotListener { [weak self] snapshot, _ in
                guard let self, let data = snapshot?.data() else { return }
                self.alert = LiveAlert(data: data)
                self.isLoading = false
            }
            // Let them know someone has the alert open (unless I already answered).
            let existing = LiveAlert(data: snapshot.data() ?? [:])
            if !existing.responders.contains(where: { $0.id == user.uid }) {
                try await respond(.seen, myName: myName)
            }
        } catch {
            print("Follow error:", error)
            errorText = error.localizedDescription
            isLoading = false
        }
    }

    func respond(_ status: Responder.Status, myName: String) async throws {
        guard let myUID, !code.isEmpty else { return }
        // Only change my own entry, so two people answering at once don't
        // overwrite each other. The security rules check the same thing.
        try await alertDocument(code).updateData([
            "responders.\(myUID)": [
                "name": myName.isEmpty ? "Your contact" : myName,
                "status": status.rawValue,
                "at": FieldValue.serverTimestamp(),
            ]
        ])
    }

    func stop() {
        listener?.remove()
        listener = nil
        alert = nil
    }
}

struct FollowView: View {
    @AppStorage("name") private var myName = ""
    @AppStorage("lastFollowedCode") private var lastCode = ""
    @State private var follower = AlertFollower()
    @State private var typedCode = ""
    @State private var camera: MapCameraPosition = .automatic
    @FocusState private var codeFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if !FirebaseSetup.isConfigured {
                    ContentUnavailableView(
                        "Live alerts aren't set up",
                        systemImage: "antenna.radiowaves.left.and.right.slash",
                        description: Text("Add GoogleService-Info.plist from your Firebase project to follow a friend's alert.")
                    )
                } else if let alert = follower.alert {
                    followingView(alert)
                } else {
                    enterCodeView
                }
            }
            .navigationTitle("Follow a friend")
            .toolbar {
                if follower.alert != nil {
                    Button("Close") {
                        follower.stop()
                        typedCode = ""
                    }
                }
            }
        }
    }

    private var enterCodeView: some View {
        VStack(spacing: 18) {
            Image(systemName: "location.viewfinder")
                .font(.system(size: 54))
                .foregroundStyle(.red)
            Text("When a friend holds SOS, their text has a 6-letter code. Type it here to see where they are and tell them you're coming.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            TextField("Code", text: $typedCode)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .focused($codeFocused)
                .padding(.vertical, 12)
                .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .onChange(of: typedCode) {
                    let cleaned = cleanedCode(typedCode)
                    if cleaned != typedCode { typedCode = cleaned }
                }
                .onSubmit(follow)
            Button(action: follow) {
                Group {
                    if follower.isLoading {
                        ProgressView().tint(.white)
                    } else {
                        Text("Follow")
                    }
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .foregroundStyle(.white)
                .background(typedCode.count == 6 ? Color.red : Color.gray, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(typedCode.count != 6 || follower.isLoading)

            if follower.notFound {
                Text("No alert with code \(follower.code). Check the letters in the text.")
                    .foregroundStyle(.red)
            }
            if let errorText = follower.errorText {
                Text(errorText)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
            if !lastCode.isEmpty && lastCode != typedCode {
                Button("Open last alert (\(lastCode))") {
                    typedCode = lastCode
                    follow()
                }
                .font(.subheadline)
            }
            Spacer()
        }
        .padding(24)
    }

    @ViewBuilder
    private func followingView(_ alert: LiveAlert) -> some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                if let coordinate = alert.coordinate {
                    Map(position: $camera) {
                        Annotation(alert.name, coordinate: coordinate) {
                            Image(systemName: "sos.circle.fill")
                                .font(.title)
                                .foregroundStyle(.white, alert.isActive ? .red : .gray)
                                .background(Circle().fill(.white).padding(4))
                        }
                        if let accuracy = alert.accuracy, accuracy > 20 {
                            MapCircle(center: coordinate, radius: accuracy)
                                .foregroundStyle(.red.opacity(0.12))
                        }
                        UserAnnotation()
                    }
                } else {
                    ContentUnavailableView("Waiting for location…", systemImage: "location.slash")
                        .background(Color(uiColor: .secondarySystemBackground))
                }
                statusBadge(alert)
                    .padding(12)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text(alert.name)
                    .font(.title2.bold())
                Text(alert.message)
                    .font(.body)
                if let updated = alert.updatedAt {
                    Text("Location from \(Text(updated, style: .relative)) ago")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                if alert.isActive {
                    HStack {
                        responseButton("I'm on my way", symbol: "figure.run", status: .onTheWay, tint: .red)
                        responseButton("I can't come", symbol: "xmark", status: .cantCome, tint: Color(white: 0.35))
                    }
                }
                if let coordinate = alert.coordinate {
                    Button {
                        let item = MKMapItem(location: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude), address: nil)
                        item.name = alert.name
                        item.openInMaps(launchOptions: [MKLaunchOptionsDirectionsModeKey: MKLaunchOptionsDirectionsModeDefault])
                    } label: {
                        Label("Directions", systemImage: "arrow.triangle.turn.up.right.diamond.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func statusBadge(_ alert: LiveAlert) -> some View {
        Label(alert.isActive ? "LIVE" : "ALERT ENDED", systemImage: alert.isActive ? "dot.radiowaves.left.and.right" : "checkmark.circle.fill")
            .font(.caption.weight(.heavy))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(alert.isActive ? Color.red : Color.gray, in: Capsule())
    }

    private func responseButton(_ title: String, symbol: String, status: Responder.Status, tint: Color) -> some View {
        let chosen = follower.myStatus == status
        return Button {
            Task { try? await follower.respond(status, myName: myName) }
        } label: {
            Label(title, systemImage: chosen ? "checkmark" : symbol)
                .font(.headline)
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(tint.opacity(chosen ? 1 : 0.75), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    if chosen {
                        RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.white, lineWidth: 2)
                    }
                }
        }
        .sensoryFeedback(.selection, trigger: chosen)
    }

    private func follow() {
        let code = cleanedCode(typedCode)
        guard code.count == 6 else { return }
        codeFocused = false
        lastCode = code
        camera = .automatic
        Task { await follower.follow(code, myName: myName) }
    }
}
