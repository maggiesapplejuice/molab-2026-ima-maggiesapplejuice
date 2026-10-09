import SwiftUI
import UIKit
import PhotosUI

// 2 tabs: the SOS button and the profile
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
    @AppStorage("name") var name = ""                       // NEW (Week 05): used to sign the text
    @AppStorage("contactName") var contactName = ""
    @AppStorage("contactPhone") var contactPhone = ""
    @AppStorage("alertMessage") var alertMessage = "I need help!"
    @AppStorage("bloodType") var bloodType = ""
    @AppStorage("allergies") var allergies = ""
    @AppStorage("medications") var medications = ""         // NEW (Week 05): now shown on alert screen

    @State var showAlert = false        // NEW (Week 05): was  @State var screen = "home"
    @State var isHolding = false
    @State var holdCount = 3
    @State var holdTimer: Task<Void, Never>?

    var body: some View {
        // NEW (Week 05): wrapped in a Group so haptics can be added
        Group {
            if showAlert {
                alertScreen
            } else {
                homeScreen
            }
        }
        // NEW (Week 05): strong buzz when the alert screen opens
        .sensoryFeedback(.warning, trigger: showAlert) { _, newValue in newValue }
    }

    //  Screen 1: the big red button
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
            // NEW (Week 05): small buzz on each count: 3, 2, 1
            .sensoryFeedback(.impact, trigger: holdCount)
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

    //Screen 2: get help
    var alertScreen: some View {
        VStack(spacing: 20) {
            Text("🚨")
                .font(.system(size: 80))
            Text("Get help now")
                .font(.largeTitle)
                .bold()

            // NEW (Week 05): always show 911, even if there is no contact saved
            Link(destination: URL(string: "tel:911")!) {
                bigButton("Call 911")
            }

            // NEW (Week 05): checks phoneDigits instead of contactPhone,
            // so a number with no digits in it doesn't make a broken button
            if phoneDigits.isEmpty {
                Text("No emergency contact saved. Add one in Profile.")
            } else {
                Link(destination: URL(string: "tel:\(phoneDigits)")!) {
                    bigButton(" Call \(contactName)")      // NEW (Week 05): uses bigButton
                }

                Link(destination: textURL) {
                    bigButton(" Text \(contactName)")      // NEW (Week 05): uses bigButton
                }
            }

            if !bloodType.isEmpty {
                Text("Blood type: \(bloodType)")
            }
            if !allergies.isEmpty {
                Text("Allergies: \(allergies)")
            }
            // NEW (Week 05): medications were saved in Profile but never shown
            if !medications.isEmpty {
                Text("Medications: \(medications)")
            }

            Button("I'm safe") {
                showAlert = false               // NEW (Week 05): was  screen = "home"
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

    // NEW (Week 05): one helper for the white buttons instead of copying the styling.
    // Also uses .clipShape instead of .cornerRadius (which is deprecated).
    func bigButton(_ title: String) -> some View {
        Text(title)
            .font(.title2)
            .bold()
            .foregroundStyle(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(.white)
            .clipShape(.rect(cornerRadius: 15))
    }

    //  Functions 

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
            showAlert = true                       // NEW (Week 05): was  screen = "alert"
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

    // NEW (Week 05): the text message, signed with your name if you added one
    var fullMessage: String {
        if name.isEmpty {
            return alertMessage
        } else {
            return "\(alertMessage) - \(name)"
        }
    }

    // Opens Messages with the number and the alert message filled in
    var textURL: URL {
        // NEW (Week 05): also encode & = ? + so they don't cut the message off
        var allowed = CharacterSet.urlQueryAllowed
        allowed.remove(charactersIn: "&=?+")
        let message = fullMessage.addingPercentEncoding(withAllowedCharacters: allowed) ?? ""
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
                    if let data = try? await pickedPhoto?.loadTransferable(type: Data.self),
                       let image = UIImage(data: data) {
                        // NEW (Week 05): shrink the photo to 300 px wide before saving,
                        // because @AppStorage is meant for small data
                        let size = CGSize(width: 300, height: 300 * image.size.height / image.size.width)
                        let small = UIGraphicsImageRenderer(size: size).image { _ in
                            image.draw(in: CGRect(origin: .zero, size: size))
                        }
                        photoData = small.jpegData(compressionQuality: 0.8) ?? Data()
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
