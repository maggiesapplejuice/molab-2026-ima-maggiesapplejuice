// xcode: set sdk=iOS

import SwiftUI
import UIKit
import PhotosUI

struct EmergencyContact: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var phone: String
    var relationship: String
    // The photo is its own JPEG file in Documents. contacts.json only keeps its name.
    var photoFileName: String?

    var digits: String {
        phone.filter { $0.isNumber }
    }

    var initials: String {
        name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined().uppercased()
    }

    init(id: UUID = UUID(), name: String, phone: String, relationship: String = "Emergency contact", photoFileName: String? = nil) {
        self.id = id
        self.name = name
        self.phone = phone
        self.relationship = relationship
        self.photoFileName = photoFileName
    }

    enum CodingKeys: String, CodingKey {
        case id, name, phone, relationship, photoFileName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decode(String.self, forKey: .name)
        phone = try container.decode(String.self, forKey: .phone)
        relationship = try container.decodeIfPresent(String.self, forKey: .relationship) ?? "Emergency contact"
        photoFileName = try container.decodeIfPresent(String.self, forKey: .photoFileName)
    }
}

func fileURL(_ fileName: String) -> URL {
    URL.documentsDirectory.appending(path: fileName)
}

func saveJSON<T: Encodable>(_ value: T, to fileName: String) {
    do {
        let data = try JSONEncoder().encode(value)
        try data.write(to: fileURL(fileName), options: .atomic)
    } catch {
        print("Save error:", error)
    }
}

func loadJSON<T: Decodable>(_ type: T.Type, from fileName: String) -> T? {
    guard let data = try? Data(contentsOf: fileURL(fileName)) else { return nil }
    return try? JSONDecoder().decode(type, from: data)
}

@Observable
@MainActor
final class ContactStore {
    var contacts: [EmergencyContact] = []
    let fileName = "contacts.json"

    init() {
        if let saved = loadJSON([EmergencyContact].self, from: fileName) {
            contacts = saved
        } else {
            let oldName = UserDefaults.standard.string(forKey: "contactName") ?? ""
            let oldPhone = UserDefaults.standard.string(forKey: "contactPhone") ?? ""
            if !oldPhone.isEmpty {
                contacts = [EmergencyContact(name: oldName, phone: oldPhone)]
                save()
            }
        }
    }

    // Only one emergency contact. Remove the current one to add someone else.
    var canAddContact: Bool {
        contacts.isEmpty
    }

    func add(name: String, phone: String, relationship: String, photo: UIImage?) {
        guard canAddContact else { return }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedRelationship = relationship.trimmingCharacters(in: .whitespacesAndNewlines)
        let contact = EmergencyContact(
            name: trimmedName,
            phone: phone,
            relationship: trimmedRelationship.isEmpty ? "Emergency contact" : trimmedRelationship
        )
        contacts.append(contact)
        save()
        if let photo {
            setPhoto(photo, for: contact.id)
        }
    }

    func setPhoto(_ image: UIImage, for contactID: UUID) {
        guard let index = contacts.firstIndex(where: { $0.id == contactID }),
              let data = resizedImage(image, maxWidth: 300).jpegData(compressionQuality: 0.8) else { return }
        // A new file name each time, so SwiftUI notices the change and redraws.
        let newFileName = "contact-\(UUID().uuidString).jpg"
        do {
            try data.write(to: fileURL(newFileName), options: .atomic)
            removePhoto(of: contacts[index])
            contacts[index].photoFileName = newFileName
            save()
        } catch {
            print("Photo save error:", error)
        }
    }

    func remove(_ contact: EmergencyContact) {
        removePhoto(of: contact)
        contacts.removeAll { $0.id == contact.id }
        save()
    }

    private func removePhoto(of contact: EmergencyContact) {
        if let photoFileName = contact.photoFileName {
            try? FileManager.default.removeItem(at: fileURL(photoFileName))
        }
    }

    func save() {
        saveJSON(contacts, to: fileName)
    }
}

struct ContentView: View {
    @State private var store = ContactStore()
    @State private var evidence = EvidenceStore()

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("SOS", systemImage: "sos.circle.fill") }

            ProfileView()
                .tabItem { Label("Safety kit", systemImage: "person.crop.circle.fill") }

            LockScreenView()
                .tabItem { Label("Lock screen", systemImage: "lock.iphone") }
        }
        .tint(.red)
        .environment(store)
        .environment(evidence)
    }
}

struct HomeView: View {
    @Environment(ContactStore.self) private var store

    @AppStorage("name") private var name = ""
    @AppStorage("alertMessage") private var alertMessage = "I need help!"

    @State private var showAlert = false
    @State private var isHolding = false
    @State private var holdCount = 3
    @State private var holdTimeRemaining = 3.0
    @State private var holdTimer: Task<Void, Never>?

    var body: some View {
        SOSHomeScreen(
            needsContacts: store.contacts.isEmpty,
            isHolding: isHolding,
            holdCount: holdCount,
            holdTimeRemaining: holdTimeRemaining,
            startHolding: startHolding,
            stopHolding: stopHolding
        )
        // The alert slides up as a card. Swiping it down ends the alert, so the
        // screen itself only has ways to get help on it.
        .sheet(isPresented: $showAlert) {
            AlertScreen(contacts: store.contacts, message: fullMessage)
                .presentationDragIndicator(.visible)
                .presentationBackground(.black)
        }
        .sensoryFeedback(.warning, trigger: showAlert) { _, value in value }
    }

    private var fullMessage: String {
        name.isEmpty ? alertMessage : "\(alertMessage) - \(name)"
    }

    private func startHolding() {
        isHolding = true
        holdCount = 3
        holdTimeRemaining = 3
        holdTimer = Task {
            let deadline = Date().addingTimeInterval(3)
            while true {
                if Task.isCancelled { return }
                let remaining = max(0, deadline.timeIntervalSinceNow)
                holdTimeRemaining = remaining
                let nextCount = Int(ceil(remaining))
                if holdCount != nextCount {
                    holdCount = nextCount
                }
                // The display rounds to three decimal places, so activate at the
                // same instant it reaches the visible 0.000 state.
                if remaining < 0.0005 {
                    holdTimeRemaining = 0
                    isHolding = false
                    showAlert = true
                    return
                }
                try? await Task.sleep(for: .milliseconds(1))
            }
        }
    }

    private func stopHolding() {
        holdTimer?.cancel()
        isHolding = false
    }
}

struct SOSHomeScreen: View {
    let needsContacts: Bool
    let isHolding: Bool
    let holdCount: Int
    let holdTimeRemaining: Double
    let startHolding: () -> Void
    let stopHolding: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.08, green: 0.1, blue: 0.12), Color(red: 0.13, green: 0.07, blue: 0.06)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Color.red
                .opacity(isHolding ? 0.72 + (Double(3 - holdCount) * 0.09) : 0)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.18), value: isHolding)
                .animation(.easeInOut(duration: 0.32), value: holdCount)

            VStack(spacing: 30) {
                ZStack {
                    Circle()
                        .stroke(.red.opacity(0.18), lineWidth: 24)
                        .frame(width: 270, height: 270)
                    // Fills up clockwise while you hold, so you can see at a glance
                    // that SOS is activating without reading any numbers.
                    Circle()
                        .trim(from: 0, to: isHolding ? 1 - holdTimeRemaining / 3 : 0)
                        .stroke(.white, style: StrokeStyle(lineWidth: 24, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .frame(width: 270, height: 270)
                    Circle()
                        .fill(
                            LinearGradient(colors: [.red, Color(red: 0.72, green: 0.03, blue: 0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        )
                        .frame(width: 218, height: 218)
                        .shadow(color: .red.opacity(0.55), radius: isHolding ? 28 : 16)
                    VStack(spacing: 4) {
                        Image(systemName: isHolding ? "hand.tap.fill" : "exclamationmark.shield.fill")
                            .font(.title)
                        Text("SOS")
                            .font(.system(size: 54, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(.white)
                }
                .scaleEffect(isHolding ? 0.93 : 1)
                .animation(.easeInOut(duration: 0.18), value: isHolding)
                .animation(.spring(response: 0.28, dampingFraction: 0.58), value: holdCount)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { _ in
                            if !isHolding { startHolding() }
                        }
                        .onEnded { _ in stopHolding() }
                )
                .accessibilityLabel("Emergency SOS")
                .accessibilityHint("Press and hold for three seconds to open emergency actions.")

                Text(isHolding ? "Activating SOS…" : "Hold to activate")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.white.opacity(isHolding ? 1 : 0.6))
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.18), value: isHolding)

                if needsContacts {
                    Text("Add your emergency contact in Safety kit")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            .padding(24)
        }
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.85), trigger: isHolding) { _, isHolding in
            isHolding
        }
        .sensoryFeedback(trigger: holdCount) { _, count in
            count == 0 ? .success : .impact(weight: .heavy, intensity: 1)
        }
    }
}

struct AlertScreen: View {
    let contacts: [EmergencyContact]
    let message: String

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 18) {
                    contactCards

                    // The spacers keep Call 911 in the middle of the screen.
                    Spacer(minLength: 12)
                    Call911Button()
                    Spacer(minLength: 12)

                    EvidenceCaptureSection(contacts: contacts, message: message)
                }
                .padding(24)
                // At least as tall as the screen, so the spacers have room to center it.
                .frame(minHeight: geometry.size.height)
            }
        }
        .foregroundStyle(.white)
        .background(Color.black)
    }

    private var contactCards: some View {
        ForEach(contacts) { contact in
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    ContactAvatar(contact: contact, size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(contact.name)
                            .font(.headline)
                        Text(contact.relationship)
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                HStack {
                    Link(destination: URL(string: "tel:\(contact.digits)")!) {
                        EmergencyActionLabel(title: "Call", symbol: "phone.fill", tint: .urgentAction)
                    }
                    Link(destination: textURL(to: contact.digits, message: message)) {
                        EmergencyActionLabel(title: "Text", symbol: "message.fill", tint: .urgentAction)
                    }
                }
            }
            .padding()
            .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
    }

    private func textURL(to digits: String, message: String) -> URL {
        let encodedMessage = message.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "sms:\(digits)&body=\(encodedMessage)")!
    }
}

// A wide button like Call and Text, just bigger. It's a rectangle on purpose:
// in this app circles are held (SOS) and rectangles are tapped.
struct Call911Button: View {
    var body: some View {
        Link(destination: URL(string: "tel:911")!) {
            Label("Call 911", systemImage: "phone.fill")
                .font(.system(size: 34, weight: .black, design: .rounded))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 30)
                .background(Color.urgentAction, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
                .shadow(color: Color.urgentAction.opacity(0.5), radius: 18)
        }
        .accessibilityLabel("Call 911")
    }
}

// On the black alert screen, red buttons are the urgent ones (calling and
// texting for help). Everything else is dark gray so the red stands out.
extension Color {
    static let urgentAction = Color.red
    static let secondaryAction = Color(white: 0.2)
}

struct EmergencyActionLabel: View {
    let title: String
    let symbol: String
    let tint: Color

    var body: some View {
        Label(title, systemImage: symbol)
            .font(.headline)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

struct ProfileView: View {
    @Environment(ContactStore.self) private var store

    @AppStorage("name") private var name = ""
    @AppStorage("photo") private var photoData = Data()
    @AppStorage("bloodType") private var bloodType = ""
    @AppStorage("allergies") private var allergies = ""
    @AppStorage("medications") private var medications = ""
    @AppStorage("alertMessage") private var alertMessage = "I need help!"

    @State private var pickedPhoto: PhotosPickerItem?
    @State private var isShowingContactSheet = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    SafetyProgressCard(completedSteps: completedSteps)
                    ProfileIdentityCard(name: $name, photoData: photoData, pickedPhoto: $pickedPhoto)
                    ContactsSection(contacts: store.contacts, canAdd: store.canAddContact) {
                        isShowingContactSheet = true
                    } onRemove: { contact in
                        store.remove(contact)
                    }
                    SavedEvidenceSection()
                    MedicalSection(
                        bloodType: $bloodType,
                        allergies: $allergies,
                        medications: $medications,
                        alertMessage: $alertMessage
                    )
                }
                .padding()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Safety kit")
            .sheet(isPresented: $isShowingContactSheet) {
                AddContactView { name, phone, relationship, photo in
                    store.add(name: name, phone: phone, relationship: relationship, photo: photo)
                }
            }
            .onChange(of: pickedPhoto) {
                loadSelectedPhoto()
            }
        }
    }

    private var completedSteps: Int {
        [!name.isEmpty, !store.contacts.isEmpty, !bloodType.isEmpty || !allergies.isEmpty || !medications.isEmpty].filter { $0 }.count
    }

    private func loadSelectedPhoto() {
        Task {
            if let data = try? await pickedPhoto?.loadTransferable(type: Data.self),
               let image = UIImage(data: data) {
                photoData = resizedImage(image, maxWidth: 300).jpegData(compressionQuality: 0.8) ?? Data()
            }
        }
    }
}

struct SafetyProgressCard: View {
    let completedSteps: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("SAFETY SCORE", systemImage: "shield.lefthalf.filled")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.75))
                Spacer()
                Text("\(completedSteps)/3")
                    .font(.headline.monospacedDigit())
            }
            Text(completedSteps == 3 ? "You’re all set" : "Build your safety kit")
                .font(.title2.bold())
            ProgressView(value: Double(completedSteps), total: 3)
                .tint(.mint)
            Text(completedSteps == 3 ? "Your essentials are ready when you need them." : "Add a few details to make your SOS more useful.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.78))
        }
        .foregroundStyle(.white)
        .padding(20)
        .background(
            LinearGradient(colors: [.teal, Color(red: 0.03, green: 0.30, blue: 0.27)], startPoint: .topLeading, endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: 24, style: .continuous)
        )
    }
}

struct ProfileIdentityCard: View {
    @Binding var name: String
    let photoData: Data
    @Binding var pickedPhoto: PhotosPickerItem?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("About you")
                .font(.headline)
            HStack(spacing: 16) {
                PhotosPicker(selection: $pickedPhoto, matching: .images) {
                    Group {
                        if let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                        } else {
                            Image(systemName: "person.fill")
                                .font(.title)
                                .foregroundStyle(.teal)
                        }
                    }
                    .frame(width: 64, height: 64)
                    .background(Color.teal.opacity(0.12), in: Circle())
                    .clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "camera.fill")
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .padding(6)
                            .background(.teal, in: Circle())
                    }
                }
                TextField("Your name", text: $name)
                    .textContentType(.name)
                    .font(.title3.weight(.medium))
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ContactsSection: View {
    let contacts: [EmergencyContact]
    let canAdd: Bool
    let addContact: () -> Void
    let onRemove: (EmergencyContact) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Your emergency contact")
                        .font(.headline)
                    Text("The person to call and text in an emergency.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                // Only one contact, so the + button goes away once it's added.
                if canAdd {
                    Button(action: addContact) {
                        Image(systemName: "plus")
                            .font(.headline)
                            .padding(10)
                            .background(.teal, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .accessibilityLabel("Add emergency contact")
                }
            }

            if contacts.isEmpty {
                Button(action: addContact) {
                    Label("Add your emergency contact", systemImage: "person.badge.plus")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                }
                .buttonStyle(.bordered)
                .tint(.teal)
            } else {
                ForEach(contacts) { contact in
                    ContactRow(contact: contact) {
                        onRemove(contact)
                    }
                }
            }
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct ContactRow: View {
    @Environment(ContactStore.self) private var store
    let contact: EmergencyContact
    let onRemove: () -> Void

    @State private var pickedPhoto: PhotosPickerItem?

    var body: some View {
        HStack(spacing: 12) {
            // Tap the circle to add or change this person's photo.
            PhotosPicker(selection: $pickedPhoto, matching: .images) {
                ContactAvatar(contact: contact, size: 44)
                    .overlay(alignment: .bottomTrailing) {
                        if contact.photoFileName == nil {
                            Image(systemName: "camera.fill")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(4)
                                .background(.teal, in: Circle())
                        }
                    }
            }
            .accessibilityLabel("Change photo for \(contact.name)")
            .onChange(of: pickedPhoto) {
                Task {
                    if let data = try? await pickedPhoto?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        store.setPhoto(image, for: contact.id)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.headline)
                Text("\(contact.relationship) · \(contact.phone)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            // Opening the menu first means one stray tap can't remove the contact.
            Menu {
                Button("Remove contact", systemImage: "trash", role: .destructive, action: onRemove)
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Options for \(contact.name)")
        }
        .padding(.vertical, 4)
    }
}

struct MedicalSection: View {
    @Binding var bloodType: String
    @Binding var allergies: String
    @Binding var medications: String
    @Binding var alertMessage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Medical essentials", systemImage: "cross.case.fill")
                .font(.headline)
                .foregroundStyle(.red)
            TextField("Blood type", text: $bloodType)
                .textInputAutocapitalization(.characters)
            Divider()
            TextField("Allergies", text: $allergies)
            Divider()
            TextField("Medications", text: $medications)
            Divider()
            TextField("SOS message", text: $alertMessage, axis: .vertical)
                .lineLimit(2...4)
        }
        .padding(18)
        .background(.background, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }
}

struct AddContactView: View {
    @Environment(\.dismiss) private var dismiss

    let onSave: (String, String, String, UIImage?) -> Void
    @State private var name = ""
    @State private var phone = ""
    @State private var relationship = ""
    @State private var pickedPhoto: PhotosPickerItem?
    @State private var photo: UIImage?

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        phone.filter(\.isNumber).count >= 3 &&
        !relationship.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 6) {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        Group {
                            if let photo {
                                Image(uiImage: photo)
                                    .resizable()
                                    .scaledToFill()
                            } else {
                                Image(systemName: "person.crop.circle.badge.plus")
                                    .font(.system(size: 46))
                                    .foregroundStyle(.teal)
                            }
                        }
                        .frame(width: 64, height: 64)
                        .clipShape(Circle())
                    }
                    .accessibilityLabel("Add a photo")
                    Text(photo == nil ? "Tap to add their photo, so you can spot them fast." : "Looking good.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Add your emergency contact")
                        .font(.title2.bold())
                    Text("Each detail helps you reach the right person faster.")
                        .foregroundStyle(.secondary)
                }

                VStack(spacing: 0) {
                    ContactField(title: "Name", symbol: "person.fill", placeholder: "e.g. Jordan Lee", text: $name)
                    Divider().padding(.leading, 48)
                    ContactField(title: "Phone number", symbol: "phone.fill", placeholder: "(555) 123-4567", text: $phone)
                        .keyboardType(.phonePad)
                    Divider().padding(.leading, 48)
                    ContactField(title: "Relationship", symbol: "heart.fill", placeholder: "e.g. Parent, roommate, friend", text: $relationship)
                }
                .padding(.horizontal, 16)
                .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20, style: .continuous))

                Spacer()

                Button {
                    onSave(name, phone, relationship, photo)
                    dismiss()
                } label: {
                    Label("Add contact", systemImage: "checkmark.circle.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
                .buttonStyle(.borderedProminent)
                .tint(.teal)
                .disabled(!canSave)
            }
            .padding(24)
            .navigationTitle("New contact")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: pickedPhoto) {
                Task {
                    if let data = try? await pickedPhoto?.loadTransferable(type: Data.self) {
                        photo = UIImage(data: data)
                    }
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

struct ContactField: View {
    let title: String
    let symbol: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: symbol)
                .foregroundStyle(.teal)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                TextField(placeholder, text: $text)
                    .textContentType(title == "Name" ? .name : nil)
            }
        }
        .padding(.vertical, 14)
    }
}

#Preview {
    ContentView()
}
