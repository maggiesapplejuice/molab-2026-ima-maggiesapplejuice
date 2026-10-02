import SwiftUI
import Combine
import UIKit
import MessageUI
import CoreLocation
import PhotosUI
import AudioToolbox

// MARK: - Root view (tab bar)

struct ContentView: View {
    @StateObject private var store = ProfileStore()
    @StateObject private var location = LocationHelper()

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("SOS", systemImage: "sos.circle.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }
        }
        .tint(.red)
        .environmentObject(store)
        .environmentObject(location)
    }
}

// MARK: - Data

struct EmergencyContact: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var phone: String

    var digits: String { phone.filter { $0.isNumber || $0 == "+" } }
}

struct Profile: Codable {
    var name = ""
    var photo: Data? = nil
    var contacts: [EmergencyContact] = []
    var bloodType = "Unknown"
    var allergies = ""
    var medications = ""
    var alertMessage = "I need help. Please call me or come find me."
}

@MainActor
final class ProfileStore: ObservableObject {
    @Published var profile: Profile {
        didSet { save() }
    }

    private let key = "savedProfile"

    init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode(Profile.self, from: data) {
            profile = saved
        } else {
            profile = Profile()
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(profile) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

// MARK: - Location

@MainActor
final class LocationHelper: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    func requestPermission() {
        manager.requestWhenInUseAuthorization()
    }

    func refresh() {
        let status = manager.authorizationStatus
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.requestLocation()
        }
    }

    var mapsLink: String? {
        guard let c = coordinate else { return nil }
        return "https://maps.apple.com/?ll=\(c.latitude),\(c.longitude)"
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        refresh()
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        coordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error:", error.localizedDescription)
    }
}

// MARK: - Page 1: SOS button

enum SOSState: Equatable {
    case idle
    case alerted(Date)
}

struct HomeView: View {
    @EnvironmentObject var store: ProfileStore
    @EnvironmentObject var location: LocationHelper
    @Environment(\.openURL) private var openURL

    @State private var state: SOSState = .idle
    @State private var holdProgress: CGFloat = 0
    @State private var isHolding = false
    @State private var holdRemaining: Double = 1.0
    @State private var holdTask: Task<Void, Never>?
    @State private var showMessage = false
    @State private var showCantText = false

    private let holdSeconds = 1.0

    var body: some View {
        NavigationStack {
            Group {
                switch state {
                case .idle:
                    idleView
                case .alerted(let date):
                    alertedView(date)
                }
            }
            .navigationTitle("")
            .toolbar(state == .idle ? .visible : .hidden, for: .navigationBar)
            .toolbar(state == .idle ? .visible : .hidden, for: .tabBar)
        }
        .sheet(isPresented: $showMessage) {
            MessageComposer(recipients: store.profile.contacts.map(\.digits),
                            body: messageBody) {
                showMessage = false
            }
            .ignoresSafeArea()
        }
        .alert("Can't send texts here", isPresented: $showCantText) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Texting only works on a real iPhone with Messages set up, not in the simulator.")
        }
        .onAppear { location.requestPermission() }
    }

    // MARK: Idle - the big red button

    private var idleView: some View {
        VStack(spacing: 40) {
            Spacer()

            Text(isHolding ? "Keep holding..." : "Hold for 1 second to send an alert")
                .font(.headline)
                .foregroundStyle(.secondary)

            ZStack {
                Circle()
                    .stroke(Color.red.opacity(0.15), lineWidth: 12)
                    .frame(width: 290, height: 290)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Color.red, style: StrokeStyle(lineWidth: 12, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 290, height: 290)

                Circle()
                    .fill(Color.red.gradient)
                    .frame(width: 240, height: 240)
                    .shadow(color: .red.opacity(0.5), radius: isHolding ? 40 : 16)
                    .scaleEffect(isHolding ? 0.93 : 1)

                VStack(spacing: 4) {
                    if isHolding {
                        Text(String(format: "%.3f", holdRemaining))
                            .font(.system(size: 52, weight: .heavy, design: .rounded).monospacedDigit())
                    } else {
                        Image(systemName: "sos")
                            .font(.system(size: 64, weight: .heavy))
                        Text("HOLD")
                            .font(.headline)
                            .tracking(3)
                    }
                }
                .foregroundStyle(.white)
            }
            .contentShape(Circle())
            .onLongPressGesture(minimumDuration: holdSeconds, maximumDistance: 60) {
                holdTask?.cancel()
                holdTask = nil
                isHolding = false
                holdProgress = 0
                location.refresh()
                triggerAlert()
            } onPressingChanged: { pressing in
                isHolding = pressing
                if pressing {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.linear(duration: holdSeconds)) { holdProgress = 1 }
                    startHoldCountdown()
                } else {
                    holdTask?.cancel()
                    holdTask = nil
                    holdRemaining = holdSeconds
                    withAnimation(.easeOut(duration: 0.2)) { holdProgress = 0 }
                }
            }
            .animation(.spring(duration: 0.3), value: isHolding)

            contactSummary

            Spacer()
        }
        .padding()
    }

    @ViewBuilder
    private var contactSummary: some View {
        let contacts = store.profile.contacts
        if contacts.isEmpty {
            Label("Add an emergency contact in Profile", systemImage: "exclamationmark.circle")
                .font(.subheadline)
                .foregroundStyle(.orange)
        } else {
            Text("Will alert: " + contacts.map(\.name).joined(separator: ", "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: Alerted - call / text buttons

    private func alertedView(_ date: Date) -> some View {
        ScrollView {
            VStack(spacing: 18) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 56))
                    .padding(.top, 140)
                Text("Alert triggered")
                    .font(.largeTitle.bold())
                Text("at \(date.formatted(date: .omitted, time: .shortened))")
                    .opacity(0.85)

                if store.profile.contacts.isEmpty {
                    Text("No emergency contacts saved yet. Add them on the Profile page.")
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    ForEach(store.profile.contacts) { contact in
                        bigButton("Call \(contact.name)", icon: "phone.fill") { call(contact) }
                    }
                    bigButton("Text all contacts", icon: "message.fill") { sendText() }
                }

                medicalCard
                    .padding(.bottom, 40)
            }
            .padding(.horizontal, 24)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.red.ignoresSafeArea())
    }

    private func bigButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.title3.bold())
                .foregroundStyle(.red)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 18)
                .background(RoundedRectangle(cornerRadius: 18).fill(.white))
        }
    }

    @ViewBuilder
    private var medicalCard: some View {
        let p = store.profile
        if p.bloodType != "Unknown" || !p.allergies.isEmpty || !p.medications.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Label("Medical info", systemImage: "cross.case.fill").font(.headline)
                if !p.name.isEmpty { Text("Name: \(p.name)") }
                if p.bloodType != "Unknown" { Text("Blood type: \(p.bloodType)") }
                if !p.allergies.isEmpty { Text("Allergies: \(p.allergies)") }
                if !p.medications.isEmpty { Text("Medications: \(p.medications)") }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(RoundedRectangle(cornerRadius: 18).fill(.white.opacity(0.18)))
        }
    }

    // MARK: Actions

    private func startHoldCountdown() {
        holdRemaining = holdSeconds
        holdTask = Task {
            let clock = ContinuousClock()
            let start = clock.now
            var lastBeep = Int(holdSeconds)
            while true {
                if Task.isCancelled { return }
                let elapsed = start.duration(to: clock.now)
                let seconds = Double(elapsed.components.seconds)
                    + Double(elapsed.components.attoseconds) / 1e18
                let remaining = max(0, holdSeconds - seconds)
                holdRemaining = remaining
                if remaining <= 0 { return }
                // Beep once as we cross each whole second.
                let whole = Int(remaining)
                if whole < lastBeep {
                    lastBeep = whole
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                    AudioServicesPlaySystemSound(1057)
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func triggerAlert() {
        state = .alerted(Date())
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
        if !store.profile.contacts.isEmpty { sendText() }
    }

    private func sendText() {
        if MFMessageComposeViewController.canSendText() {
            showMessage = true
        } else {
            showCantText = true
        }
    }

    private func call(_ contact: EmergencyContact) {
        if let url = URL(string: "tel://\(contact.digits)") {
            openURL(url)
        }
    }

    private var messageBody: String {
        var lines = [store.profile.alertMessage]
        if !store.profile.name.isEmpty { lines.append("- \(store.profile.name)") }
        if let link = location.mapsLink { lines.append("My location: \(link)") }
        return lines.joined(separator: "\n")
    }
}

// MARK: - Text message sheet

struct MessageComposer: UIViewControllerRepresentable {
    let recipients: [String]
    let body: String
    let onFinish: () -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    func makeUIViewController(context: Context) -> MFMessageComposeViewController {
        let vc = MFMessageComposeViewController()
        vc.recipients = recipients
        vc.body = body
        vc.messageComposeDelegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: MFMessageComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMessageComposeViewControllerDelegate {
        let onFinish: () -> Void
        init(onFinish: @escaping () -> Void) { self.onFinish = onFinish }

        func messageComposeViewController(_ controller: MFMessageComposeViewController,
                                          didFinishWith result: MessageComposeResult) {
            onFinish()
        }
    }
}

// MARK: - Page 2: Profile

struct ProfileView: View {
    @EnvironmentObject var store: ProfileStore
    @State private var photoItem: PhotosPickerItem?
    @State private var showAddContact = false

    private let bloodTypes = ["Unknown", "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-"]

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 16) {
                        PhotosPicker(selection: $photoItem, matching: .images) {
                            avatar
                        }
                        VStack(alignment: .leading) {
                            TextField("Your name", text: $store.profile.name)
                                .font(.title3)
                            Text("Tap the photo to change it")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 6)
                }

                Section {
                    ForEach(store.profile.contacts) { contact in
                        VStack(alignment: .leading) {
                            Text(contact.name)
                            Text(contact.phone)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .onDelete { store.profile.contacts.remove(atOffsets: $0) }
                    .onMove { store.profile.contacts.move(fromOffsets: $0, toOffset: $1) }

                    Button {
                        showAddContact = true
                    } label: {
                        Label("Add contact", systemImage: "plus.circle.fill")
                    }
                } header: {
                    Text("Emergency contacts")
                } footer: {
                    Text("Swipe left to delete. Tap Edit to reorder.")
                }

                Section("Medical info") {
                    Picker("Blood type", selection: $store.profile.bloodType) {
                        ForEach(bloodTypes, id: \.self) { Text($0) }
                    }
                    TextField("Allergies", text: $store.profile.allergies, axis: .vertical)
                    TextField("Medications", text: $store.profile.medications, axis: .vertical)
                }

                Section {
                    TextField("Message", text: $store.profile.alertMessage, axis: .vertical)
                        .lineLimit(3...6)
                } header: {
                    Text("Alert message")
                } footer: {
                    Text("Sent to your contacts. Your location is added if you allow it.")
                }
            }
            .navigationTitle("Profile")
            .toolbar { EditButton() }
            .sheet(isPresented: $showAddContact) {
                AddContactView { store.profile.contacts.append($0) }
            }
            .onChange(of: photoItem) { _, item in
                Task { await loadPhoto(item) }
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let data = store.profile.photo, let image = UIImage(data: data) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 76, height: 76)
                .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 60))
                .foregroundStyle(.red)
                .frame(width: 76, height: 76)
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item,
              let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else { return }
        let width: CGFloat = 300
        let size = CGSize(width: width, height: width * image.size.height / image.size.width)
        let small = UIGraphicsImageRenderer(size: size).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        store.profile.photo = small.jpegData(compressionQuality: 0.7)
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var phone = ""
    let onSave: (EmergencyContact) -> Void

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty &&
        phone.filter(\.isNumber).count >= 3
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField("Name", text: $name)
                    .textContentType(.name)
                TextField("Phone number", text: $phone)
                    .keyboardType(.phonePad)
                    .textContentType(.telephoneNumber)
            }
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(EmergencyContact(name: name.trimmingCharacters(in: .whitespaces),
                                                phone: phone))
                        dismiss()
                    }
                    .disabled(!isValid)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

#Preview {
    ContentView()
}
