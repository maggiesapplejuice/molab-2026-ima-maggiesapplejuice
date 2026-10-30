# molab-2026-ima-maggiesapplejuice
---
- Midterm checklist
  - [yes] weekly description of homework progress/challenges in your wiki page
  - [yes] added jht9629-nyu as collab on your repo
  - [yes] uploaded at least one photo in MoGallery TestFlight App
  - [yes] able to build and run example apps own iPhone
  - [yes] installed Xcode 27
  - [yes] watched at least one WWDC video
  - [ ] uploaded profile photo to HOS-Lobby app
---
## Week 8

### Part 1: Studying Swift/SwiftUI
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Topics:** [fill in the days/topics you did this week]
- **Time spent:** [fill in] hours
- Past assignments: Weeks 1–7 all have folders in this repo already.

### Part 2: Homework (video manipulation app)
**Project:** [`week 8/`](./week%208): `VideoEvidence.swift` (new), `Evidence.swift`

I added evidence videos to my SOS app. My twist on the 08-CameraRecorder demo is that the "filter" isn't a look. It writes the time and GPS location onto every frame, so the video itself shows when and where it was filmed.

- **Record video:** the alert screen now has Photo, Video and Choose. Video opens a full screen camera (the back camera, since you want to film what's happening, not your face).
- Like 08-CameraRecorder, every camera frame goes through Core Image before it's shown and recorded (`AVCaptureVideoDataOutput` → `CIImage` → `AVAssetWriter`). The preview shows the processed frame, so what you see is exactly what gets saved.
- **Time and location stamp on every frame:** the same see-through black bar from my Week 7 photos, but drawn onto the video. The time updates every second while recording.
- To reuse the bar, I moved it into its own `stampBar` function. Photos draw it once, and videos turn it into a `CIImage` and put it on top of each frame with `composited(over:)`.
- Making the bar image is slow, and the text only changes once a second, so I keep the last one and reuse it for the ~30 frames in between (`StampCache`).
- **Night boost:** the moon button brightens dark scenes with `exposureAdjust` and `noiseReduction`. I used exposure instead of brightness because of what I learned in Week 7: it multiplies, so dark areas don't turn gray or black.
- **Sound:** records the microphone too (`AVCaptureAudioDataOutput`). If you say no to the microphone, it still records video without sound.
- **One minute max** so the video is small enough to text. The timer at the top counts up to 1:00 and it stops on its own. The screen also won't auto-lock while you're recording.
- **Closing the camera while recording still saves the video**, so evidence isn't lost by swiping the wrong way.
- **Library videos:** Choose now lets you pick videos too. They get the same "Added to SOS" stamp on every frame using `AVVideoComposition` with a Core Image handler, then get exported at 720p. A spinner says "Stamping video…" while it works.
- Videos are saved in Documents with the same `.completeFileProtection` as photos, and get a still-frame thumbnail with a ▶ and their length (like the Photos app).
- **Watch evidence:** tap any photo or video (on the alert screen or in Safety kit → Saved evidence) to view it full size. Videos play with `VideoPlayer`.
- The send button counts both now ("Send 1 photo and 1 video to Mom") and attaches the videos to the text.
- I kept my Week 7 design rule: the record button is a wide rectangle, not a round shutter, because in this app circles are held (SOS) and rectangles are tapped.

**Concepts used:** `AVCaptureSession`, `AVCaptureVideoDataOutput` / `AVCaptureAudioDataOutput`, `AVAssetWriter` and pixel buffer adaptors, `CIImage` compositing, Core Image filters (`exposureAdjust`, `noiseReduction`), `AVVideoComposition` with a Core Image handler, `AVAssetExportSession`, `AVAssetImageGenerator`, `Transferable` for picked videos, `VideoPlayer`, `nonisolated` and locks for background threads

**Issues/errors:**
- My project makes everything run on the main thread by default (`MainActor`), but camera frames arrive on a background thread about 30 times a second. I had to mark the recorder `nonisolated` and put the settings that both threads change (location, night boost) behind a lock.
- `AVMutableVideoComposition` is deprecated in iOS 26. The new replacement (`AVVideoComposition(applyingFiltersTo:)`) only exists in iOS 27, and my app supports iOS 26, so I used `AVVideoComposition.videoComposition(with:applyingCIFiltersWithHandler:)` instead.
- iPhone videos are often saved sideways with a "rotate me" flag. I made a test video like that to make sure the stamp still ends up on the bottom of the upright video, and it does.
- For the camera, I turned the frames upright first (`videoRotationAngle = 90`), so the stamp goes along the bottom instead of up the side.
- At first, closing the camera mid-recording could lose when the video started, because the screen was already gone when the file finished saving. Now the recorder remembers the start time itself.
- The new simulator shows a camera, so the Photo and Video buttons appear, but recording fails (error -12782) and the screen just showed a spinner forever. Now it says "The camera couldn't start" so you know to use something else.

**Plans:** test the live camera, microphone, night boost and texting a video on my iPhone, since the simulator can't record. Maybe add a Live Activity so the alert shows on the lock screen.

**Final project research:** [fill in your notes so far]

**Questions:** [fill in]

**Time spent:** [fill in] hours

---
## Week 7

### Part 1: 100 Days of SwiftUI (Days 43–49)
- **Resource:** https://www.hackingwithswift.com/100/swiftui
- **Topics:** Drawing (shapes, paths, `Canvas`-style drawing)
- **Time spent:** 10 hours

### Part 2: Homework
**`week 7/week 7/Evidence.swift`, `ContentView.swift`, `PhotoHelpers.swift`**: added photos to my SOS app and made the alert screen simpler.

- **Contact photos:** you can add a photo to your emergency contact with `PhotosPicker`, either when you add them or by tapping their circle later. When you're panicking, a face is faster to recognize than a name. Without a photo it shows their initials.
- Each contact photo is shrunk to 300 px and saved as its own JPEG in the Documents folder, and `contacts.json` only keeps the file name. Every new photo gets a new random file name, so SwiftUI notices the change and redraws. Older contacts without a photo still load because of `decodeIfPresent`.
- **Evidence photos:** the alert screen has a "Record what's happening" section where you can take a photo with the camera or choose up to 5 from your library.
- SwiftUI doesn't have a camera view, so I wrapped UIKit's `UIImagePickerController` with `UIViewControllerRepresentable`, like the 07-PhotoPickBlender demo. The Coordinator passes the photo back to SwiftUI.
- Every evidence photo gets the time and GPS location drawn onto it with `UIGraphicsImageRenderer` (a see-through black bar with white text), so whoever receives it can see when and where it was taken. Library photos say "Added to SOS" instead of "Taken" because they might be older.
- The location comes from `CLLocationUpdate.liveUpdates()` with a `CLServiceSession`. It starts when the alert opens and stops when it closes, so it isn't tracking you the rest of the time.
- "Send to [contact]" opens Messages (`MFMessageComposeViewController`) with my contact, my SOS message, an Apple Maps link to my location, and the photos already filled in. If the phone can't send texts, it shows the share sheet instead.
- Evidence photos are saved with `.completeFileProtection` so they're encrypted while the phone is locked. They stay in a new "Saved evidence" section in Safety kit after the alert ends, where you can long-press to share or delete them.
- Made a `resizedImage` helper that shrinks photos and fixes ones taken sideways. Both contact photos and evidence photos use it.
- **One emergency contact:** went back to just one contact so there's no decision to make in an emergency. The + button hides once you've added someone, and the ⋯ menu next to them removes them. This also replaces the Week 6 swipe-to-delete, which didn't actually work because `.onDelete` only works inside a `List`.
- **SOS button:** replaced the 3, 2, 1 countdown with a white ring that fills up while you hold (`Circle().trim(from:to:)`) and text that says "Activating SOS…", so you can tell it's working at a glance.
- **Alert screen:** it now slides up as a card (`.sheet`) that you swipe down to end, instead of an "I'm safe" button. I took off the warning icon, the "Get help now" title and the medical info, so it only has ways to get help.
- The alert screen is black, and only the most urgent buttons are red: a big Call 911 in the middle of the screen, and Call and Text for my contact. Everything else is dark gray, so your eye goes straight to the red.
- My first idea this week was a lock screen wallpaper with your medical info on it, made with Core Image filters like the 07-Instafilter demo. I built it, but then removed it because it would show your name, health details and a contact's number to anyone who sees your phone, all the time. Evidence photos only happen during a real emergency.

**Concepts used:** `PhotosPicker`, `UIViewControllerRepresentable` and Coordinators, `UIImagePickerController`, `MFMessageComposeViewController`, `ShareLink`, `UIGraphicsImageRenderer`, `CLLocationUpdate` / `CLServiceSession`, file protection, `.sheet`, `Circle().trim`

**Issues/errors:**
- The dark bar behind the time and location stamp came out solid gray and erased the bottom of the photo. That's because `context.fill(rect)` uses the `.copy` blend mode by default, which replaces the pixels instead of drawing over them. I fixed it with `blendMode: .normal`.
- `UIGraphicsImageRenderer` uses the screen's 3x scale by default, so a "1200 px" photo was really 3600 px and the colors came out wrong. I fixed it by setting `format.scale = 1` and `preferredRange = .standard`.
- In the lock screen version, darkening the photo with `colorControls` brightness turned dark green areas completely black, because it subtracts the same amount from every color. `exposureAdjust` fixed it because it darkens by a percentage instead.
- I first made Call 911 a big circle like the SOS button, but it looked like you had to hold it too. I changed it to a wide button, so the only circle is the SOS button you hold.
- The simulator's camera can't actually take a picture and the simulator can't send texts, so I still need to test those on my iPhone.

**Plans:** test the camera and texting on my iPhone, and maybe add a Live Activity so the alert shows on the lock screen while it's active.

**Time spent:** 12 hours

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
