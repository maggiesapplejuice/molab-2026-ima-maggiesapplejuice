import SwiftUI
import UIKit
import PhotosUI

// The app has 2 tabs: the SOS button and the profile
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("SOS", systemImage: "sos.circle.fill") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.circle") }
        }
        .tint(.red)
    }
}

// PAGE 1: the SOS button
struct HomeView: View {
    // These come from the Profile page (@AppStorage saves them on the phone)
    @AppStorage("contactName") var contactName = ""
    @AppStorage("contactPhone") var contactPhone = ""
    @AppStorage("alertMessage") var alertMessage = "I need help!"
    @AppStorage("bloodType") var bloodType = ""
    @AppStorage("allergies") var allergies = ""

    @State var screen = "home"      // "home" or "alert"
    @State var isHolding = false
    @State var holdCount = 3
    @State var holdTimer: Task<Void, Never>?

    var body: some View {
        if screen == "home" {
            homeScreen
        } else {
            alertScreen
        }
    }

    // ---------- Screen 1: the big red button ----------
    var homeScreen: some View {
        VStack(spacing: 40) {
            Text("Hold for 3 seconds")
                .font(.title2)
                .bold()

            ZStack {
                Circle()
                    .fill(.red)
                    .frame(width: 250, height: 250)

                if isHolding {
                    Text("\(holdCount)")
                        .font(.system(size: 120, weight: .bold))
                        .foregroundStyle(.white)
                } else {
                    Text("SOS")
                        .font(.system(size: 60, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .scaleEffect(isHolding ? 0.9 : 1)
            .animation(.easeInOut, value: isHolding)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        if isHolding == false {
                            startHolding()      // finger went down
                        }
                    }
                    .onEnded { _ in
                        stopHolding()           // finger came up
                    }
            )

            if contactName.isEmpty {
                Text("Add an emergency contact in Profile")
                    .foregroundStyle(.gray)
            } else {
                Text("Will contact: \(contactName)")
                    .foregroundStyle(.gray)
            }
        }
    }

    // ---------- Screen 2: get help ----------
    var alertScreen: some View {
        VStack(spacing: 20) {
            Text("🚨")
                .font(.system(size: 80))
            Text("Get help now")
                .font(.largeTitle)
                .bold()

            if contactPhone.isEmpty {
                Text("No emergency contact saved. Add one in Profile.")
            } else {
                Link(destination: URL(string: "tel:\(phoneDigits)")!) {
                    Text("📞 Call \(contactName)")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .cornerRadius(15)
                }

                Link(destination: textURL) {
                    Text("💬 Text \(contactName)")
                        .font(.title2)
                        .bold()
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.white)
                        .cornerRadius(15)
                }
            }

            if !bloodType.isEmpty {
                Text("Blood type: \(bloodType)")
            }
            if !allergies.isEmpty {
                Text("Allergies: \(allergies)")
            }

            Button("I'm safe") {
                screen = "home"
            }
            .font(.title3)
            .bold()
            .padding(.top, 20)
        }
        .padding(30)
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.red)
    }

    // ---------- Functions ----------

    // Count 3, 2, 1 on the button while the finger is down
    func startHolding() {
        isHolding = true
        holdCount = 3

        holdTimer = Task {
            while holdCount > 0 {
                try? await Task.sleep(for: .seconds(1))
                if Task.isCancelled { return }     // let go early
                holdCount -= 1
            }
            isHolding = false
            screen = "alert"                       // held all 3 seconds
        }
    }

    func stopHolding() {
        holdTimer?.cancel()
        isHolding = false
    }

    // The phone number with only the numbers (no spaces or dashes)
    var phoneDigits: String {
        contactPhone.filter { $0.isNumber }
    }

    // Opens Messages with the number and the alert message filled in
    var textURL: URL {
        let message = alertMessage.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
        return URL(string: "sms:\(phoneDigits)&body=\(message)")!
    }
}

// PAGE 2: the profile
struct ProfileView: View {
    // @AppStorage saves each one on the phone automatically
    @AppStorage("name") var name = ""
    @AppStorage("photo") var photoData = Data()
    @AppStorage("contactName") var contactName = ""
    @AppStorage("contactPhone") var contactPhone = ""
    @AppStorage("bloodType") var bloodType = ""
    @AppStorage("allergies") var allergies = ""
    @AppStorage("medications") var medications = ""
    @AppStorage("alertMessage") var alertMessage = "I need help!"

    @State var pickedPhoto: PhotosPickerItem?

    var body: some View {
        NavigationStack {
            Form {
                Section("Me") {
                    PhotosPicker(selection: $pickedPhoto, matching: .images) {
                        if let image = UIImage(data: photoData) {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 100, height: 100)
                                .clipShape(Circle())
                        } else {
                            Image(systemName: "person.circle.fill")
                                .font(.system(size: 100))
                                .foregroundStyle(.gray)
                        }
                    }
                    TextField("Your name", text: $name)
                }

                Section("Emergency contact") {
                    TextField("Name", text: $contactName)
                    TextField("Phone number", text: $contactPhone)
                        .keyboardType(.phonePad)
                }

                Section("Medical info") {
                    TextField("Blood type", text: $bloodType)
                    TextField("Allergies", text: $allergies)
                    TextField("Medications", text: $medications)
                }

                Section("Alert message") {
                    TextField("Message", text: $alertMessage)
                }
            }
            .navigationTitle("Profile")
            .onChange(of: pickedPhoto) {
                // Load the photo the user picked and save it
                Task {
                    if let data = try? await pickedPhoto?.loadTransferable(type: Data.self) {
                        photoData = data
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
