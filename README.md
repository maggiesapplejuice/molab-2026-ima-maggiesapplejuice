# molab-2026-ima-maggiesapplejuice
---
- Midterm checklist
  - [yes] weekly description of homework progress/challenges in your wiki page
  - [yes] added jht9629-nyu as collab on your repo
  - [yes] uploaded at least one photo in MoGallery TestFlight App
  - [yes] able to build and run example apps own iPhone
  - [yes] installed Xcode 27
  - [yes] watched at least one WWDC video
---
## Week 7

### Part 2: Homework
Added two photo features to my SOS app, and simplified it.

**Simpler SOS:**
- The app now has **one emergency contact** instead of a list, so there's no decision to make in an emergency. The + button disappears once you've added someone, and the **⋯** menu next to them has "Remove contact" if you want to switch to someone else. (This also replaces Week 6's swipe-to-delete, which didn't actually work because `.onDelete` only works inside a `List`.)
- **SOS button:** instead of a countdown in seconds, a white ring fills up around the button while you hold and the text changes to "Activating SOS…". You can tell it's working at a glance, without reading numbers (`Circle().trim(from:to:)`).
- **The alert screen only shows ways to get help.** I removed the warning icon, the "Get help now" title, the blood type / allergies / medications list and the "I'm safe" button. (Your medical info is still saved in Safety kit.)
- **Ending the alert:** the alert now slides up as a card (`.sheet` with `.presentationDragIndicator(.visible)`), and you swipe it down to end it, like closing any iOS sheet. I tried a "Hold to end alert" button first, but a button for *ending* the alert doesn't belong on a screen that's for getting help.
- **Black background, red for what's urgent:** only the most urgent buttons are red: a big **Call 911** in the middle of the screen, and Call and Text for your contact. Everything else (Take photo, Choose, Send) is dark gray, so your eye goes straight to the red.
- **Circles are held, rectangles are tapped.** I first made Call 911 a big circle like the SOS button, but it looked like you had to hold it too. Now it's a wide rectangle like the other tap buttons, and the only circle in the app is the SOS button you hold.

**1. Contact photos** (`week 7/week 7/ContentView.swift`, `PhotoHelpers.swift`): when you're panicking, a face is faster to recognize than a name.

- Add a photo when you create the contact, or tap their circle to set or change it (`PhotosPicker`)
- The alert screen shows their face next to the Call and Text buttons. Without a photo it shows their initials
- Each photo is shrunk to 300 px and saved as its own JPEG in the Documents folder. `contacts.json` only stores the file name, so the JSON stays small. Older `contacts.json` files without a photo still load (`decodeIfPresent`)

**2. Evidence capture** (`week 7/week 7/Evidence.swift`): a "Record what's happening" section on the alert screen.

- **Take photo** opens the camera (`UIImagePickerController` wrapped in `UIViewControllerRepresentable`, like the 07-PhotoPickBlender demo). **Choose** picks up to 5 photos from the library
- Every photo gets the time and GPS location drawn onto it with `UIGraphicsImageRenderer`, so whoever receives it sees them too. Library photos say "Added to SOS" instead of "Taken", because they might be older
- Location comes from `CLLocationUpdate.liveUpdates()` and `CLServiceSession`, and only runs while the alert screen is open
- **Send to [contact]** opens Messages (`MFMessageComposeViewController`) with your emergency contact filled in, the photos attached, and an Apple Maps link to your location. If the phone can't send texts, it shows the normal share sheet instead
- Photos are saved with `.completeFileProtection` (encrypted while the phone is locked). They stay in a **Saved evidence** section in Safety kit after the alert ends, where you can share or delete them
- This only collects photos during an actual emergency. My first idea was a lock screen wallpaper showing your medical info, made with Core Image filters (like the 07-Instafilter demo) and saved with `PHPhotoLibrary`. I built it, then removed it because it would show your name, health details and a contact's number to anyone who sees your phone, all the time

Also cleaned up the file names: `MyApp.swift` is now just the `@main` file and `ContentView.swift` has the app's views (they were swapped in Week 6).

**Concepts used:** `PhotosPicker` (single and multiple selection), `UIViewControllerRepresentable` with a Coordinator, `UIImagePickerController`, `MFMessageComposeViewController`, `ShareLink`, `UIGraphicsImageRenderer`, `CLLocationUpdate` / `CLServiceSession`, file protection, `.sheet` presentation, camera / location usage descriptions

**Issues/errors:**
- In the lock screen version, darkening photos with `colorControls` brightness turned dark green areas completely black, because it subtracts the same amount from every color. `exposureAdjust` fixed it, because it darkens by a percentage instead.
- `UIGraphicsImageRenderer` uses the screen's 3x scale by default, so a "1200 px" photo was really 3600 px and in a wide-color format, which made Core Image slow and the colors wrong. Setting `format.scale = 1` and `preferredRange = .standard` in my resize helper fixed it.
- The dark bar behind the time/location stamp came out solid gray and erased the bottom of the photo. `context.fill(rect)` on a `UIGraphicsImageRenderer` uses the `.copy` blend mode by default, which replaces pixels instead of drawing over them. Passing `blendMode: .normal` fixed it.
- The simulator's camera opens but can't actually take a picture, and the simulator can't send texts, so those two parts need to be tested on a real iPhone.

**Plans:** test the camera and texting on my iPhone, and maybe a Live Activity so the alert stays on the lock screen while it's active.

---
## Week 6

### Part 1: 100 Days of SwiftUI (Days 36–42)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Topics:** iExpense (`@Observable`, sheets, deleting items with `onDelete`, saving with `UserDefaults` and `Codable`) and Moonshot (loading JSON, scroll views, composing smaller views)
- **Time spent:** 10 hours

### Part 2: Homework
**`week 6/ContentView.swift`**: added a new way of saving data to my SOS app.

- You can now save **multiple emergency contacts** instead of just one. Before, I used `@AppStorage`, which can only hold single values like one name and one phone number, not a list.
- Each contact is a `Codable` struct, and the whole list is saved as a JSON file (`contacts.json`) in the app's Documents folder, like the 06-ImageEditDemoJSON demo from class
- Wrote generic `saveJSON` and `loadJSON` functions that work with any Codable type
- Made a `ContactStore` class with `@Observable` and shared it with both tabs using `.environment`, so a contact added in Profile shows up on the SOS tab right away
- Profile tab: add contacts with a button, swipe left to delete one
- Alert screen: a Call and a Text button for every contact, inside a ScrollView so a long list still fits
- The first time the new version runs, it moves the one contact saved by the old version into the new list, so nothing gets lost
- Everything else (name, photo, medical info, alert message) still uses `@AppStorage`, since those are single small values

**Concepts used:** `Codable`, `JSONEncoder` / `JSONDecoder`, generic functions, the Documents directory, `@Observable`, `.environment`, `ForEach` with `.onDelete`, ScrollView

**Issues/errors:**
- I was editing in VS Code at first, but it can't run iPhone apps, so I had to switch to Xcode to test.
- When I opened my Swift file by itself in Xcode, I got "No such module 'UIKit'". That's because a loose file gets built as Mac code. I fixed it by creating a real iOS App project and putting the code inside it.
- Then I got "Invalid redeclaration of 'ContentView'" because I pasted the code into `MyApp.swift` instead of `ContentView.swift`, so there were two ContentViews. I fixed it by putting the code in ContentView.swift and keeping MyApp.swift as just the small `@main` file that starts the app.

**Plans:** let users edit a contact after adding it, and maybe add the user's location to the text message.

**Time spent:** 12 hours

## Week 5

### Part 1: 100 Days of SwiftUI (Days 29–35)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Topics:** Word Scramble (List, loading files from the bundle, UITextChecker), animations
- **Time spent:** 10 hours

### Part 2: Homework
**`week 5/ContentView.swift`**: updated my two-tab SOS app from Week 4.

- Added haptics: a small buzz on each count (3, 2, 1) and a strong warning buzz when the alert screen opens
- Added a "Call 911" button that always shows, even if no emergency contact is saved
- The text message is now signed with your name from the Profile tab
- Medications now show on the alert screen (they were saved before but never displayed)
- Made one `bigButton()` helper for the white buttons instead of copying the same styling three times
- Switched from a string (`screen = "home"/"alert"`) to a Bool (`showAlert`) to switch screens
- The profile photo is now shrunk to 300 px wide before saving

**Concepts used:** `.sensoryFeedback`, helper functions that return views, computed properties, CharacterSet / percent-encoding, UIGraphicsImageRenderer

**Issues/errors:**
- The text message was getting cut off if it had symbols like `&` or `?`, because those have special meanings in a URL. I fixed it by removing them from the allowed characters so they get encoded too.
- Xcode warned that `.cornerRadius` is deprecated, so I switched to `.clipShape(.rect(cornerRadius:))`.
- Saving a full-size photo in `@AppStorage` was a bad idea since it's meant for small data, so I resized it first.
- The call button could break if the phone number had no digits in it, so I made it check `phoneDigits` instead of `contactPhone`.

**Time spent:** 12 hours

---

## Week 4

### Part 1: 100 Days of SwiftUI (Days 22–28)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Topics:** finished Guess the Flag, views and modifiers, the Rock Paper Scissors milestone, and started BetterRest
- **Time spent:** 10 hours

### Part 2: Homework
**`week 4/ContentView.swift`**: a two-tab emergency app built in SwiftUI.

- **SOS tab:** a big red button you have to hold for 3 seconds. It counts down 3, 2, 1, and if you let go early it cancels. After 3 seconds it opens a red alert screen with buttons to call or text your emergency contact. The text opens Messages with your alert message already filled in. The screen also shows your blood type and allergies.
- **Profile tab:** a form for your name, photo, emergency contact, medical info (blood type, allergies, medications), and a custom alert message. Everything is saved on the phone with `@AppStorage`, so the SOS tab can use it right away.

**Concepts used:** TabView, `@AppStorage`, `@State`, DragGesture, Task for the countdown timer, PhotosPicker, Link with `tel:` and `sms:` URLs

**Issues/errors:**
- The hardest part was getting the hold-to-count-down button to work. `onLongPressGesture` didn't let me show a countdown, so I used `DragGesture` with `minimumDistance: 0` to tell when the finger went down and came up, and cancelled the timer Task if they let go early.
- I had to strip spaces and dashes out of the phone number and percent-encode the message so the call and text links would work.

**Time spent:** 8 hours

---

## Week 3

### Part 1: 100 Days of SwiftUI (Days 15–21)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Time spent:** 7 hours

### Part 2: Homework
**Apple juice tabs**

**Issues/errors:** Nothing much, just getting used to SwiftUI.

**Time spent:** 6 hours

---

## Week 2

### Part 1: 100 Days of SwiftUI (Days 8–14)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Time spent:** 7 hours

| Day | Topic |
| --- | --- |
| 8 | Default values, throwing functions, and checkpoint |
| 9 | Closures, passing functions into functions, and checkpoint |
| 10 | Structs, computed properties, and property observers |
| 11 | Access control, static properties and methods, and checkpoint |
| 12 | Classes, inheritance, and checkpoint |
| 13 | Protocols, extensions, and checkpoint |
| 14 | Optionals, nil coalescing, and checkpoint |

### Part 2: Text art playground
**`Week02/week2.playground`**: apple ASCII art using variables, loops, and string manipulation.

**Project link:** [your github link to week2.playground]

**Issues/errors:** No major issues, mostly the normal learning curve of getting comfortable with newer Swift concepts like classes and protocols.

---

## Week 1

### Part 1: 100 Days of SwiftUI (Days 1–7)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Time spent:** 7 hours

**Issues/errors:** Rough learning curve with Swift fundamentals, but I think I'll get the hang of it over time.

### Part 2: Homework
Homework was surprisingly easier than I expected. No troubles with it.
