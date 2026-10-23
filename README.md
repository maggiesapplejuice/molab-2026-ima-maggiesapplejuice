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
**`week 7/week 7/LockScreenView.swift`**: added a new **Lock screen** tab to my SOS app that turns one of your photos into a Medical ID lock screen wallpaper.

- Pick a background photo from your library with `PhotosPicker`
- Choose a style made with Core Image filters, like the 07-Instafilter demo: **Calm** (blur), **Noir** (black and white), **Night** (dark blue tint) and **Vivid** (vibrance + vignette). Each one darkens the photo a bit so the white text stays easy to read
- Your name, blood type, allergies, medications and first emergency contact (from the Safety kit tab) are shown on top of the photo, placed between the lock screen clock and the flashlight/camera buttons
- "Save to Photos" uses `ImageRenderer` to turn the SwiftUI view into a full-resolution image, then saves it with `PHPhotoLibrary`. It asks for **add-only** access, so the app can save photos but can never see your library
- Then you set it as your wallpaper from the Photos app. Now a first responder can see your medical info without unlocking your phone
- Also cleaned up the file names: `MyApp.swift` is now just the `@main` file and `ContentView.swift` has the app's views (they were swapped in Week 6)

**Concepts used:** `PhotosPicker`, `CIFilter` / `CoreImage.CIFilterBuiltins`, `CIContext`, `ImageRenderer`, `PHPhotoLibrary` add-only permission, `NSPhotoLibraryAddUsageDescription`

**Issues/errors:**
- My first try at darkening the photo used `colorControls` brightness. It subtracts the same amount from every color, so dark green cliffs turned completely black and the colors looked wrong. Switching to `exposureAdjust` fixed it, because exposure darkens by a percentage instead.
- `UIGraphicsImageRenderer` uses the screen's 3x scale by default, so my "1200 px" photo was really 3600 px and in a wide-color format. Setting `format.scale = 1` and `preferredRange = .standard` made the filters faster and the colors correct.

**Plans:** add photos to each emergency contact so you can recognize them faster on the alert screen.

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
