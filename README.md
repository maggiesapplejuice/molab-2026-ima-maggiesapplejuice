# molab-2026-ima-maggiesapplejuice
week 5

Continued with 100 Days of SwiftUI, Days 29–35 — https://www.hackingwithswift.com/100/swiftui
Topics: Word Scramble (List, loading files from the bundle, UITextChecker), animations
Time spent: 10 hours

Part 2 — HW

week 5/ContentView.swift — updated my two-tab SOS app from week 4.
- Added haptics: a small buzz on each count (3, 2, 1) and a strong warning buzz when the alert screen opens.
- Added a "Call 911" button that always shows, even if no emergency contact is saved.
- The text message is now signed with your name from the Profile tab.
- Medications now show on the alert screen (they were saved before but never displayed).
- Made one bigButton() helper for the white buttons instead of copying the same styling three times.
- Switched from a string (screen = "home"/"alert") to a Bool (showAlert) to switch screens.
- The profile photo is now shrunk to 300 px wide before saving.

Concepts used: .sensoryFeedback, helper functions that return views, computed properties, CharacterSet / percent-encoding, UIGraphicsImageRenderer

Issues/errors: The text message was getting cut off if it had symbols like & or ? in it, because those have special meanings in a URL. I fixed it by removing them from the allowed characters so they get encoded too. Xcode also warned that .cornerRadius is deprecated, so I switched to .clipShape(.rect(cornerRadius:)). I also realized saving a full-size photo in @AppStorage was a bad idea since it's meant for small data, so I resized it first. Finally, the call button could break if the phone number had no digits in it, so I made it check phoneDigits instead of contactPhone.
Time spent: 12 hours

week 4 

Continued with 100 Days of SwiftUI, Days 22–28 — https://www.hackingwithswift.com/100/swiftui
Topics: finished Guess the Flag, views and modifiers, the Rock Paper Scissors milestone, and started BetterRest
Time spent: 10 hours

Part 2 — HW

week 4/ContentView.swift — a two-tab emergency app built in SwiftUI.
- SOS tab: a big red button you have to hold for 3 seconds. It counts down 3, 2, 1, and if you let go early it cancels. After 3 seconds it opens a red alert screen with buttons to call or text your emergency contact. The text opens Messages with your alert message already filled in. The screen also shows your blood type and allergies.
- Profile tab: a form for your name, photo, emergency contact, medical info (blood type, allergies, medications), and a custom alert message. Everything is saved on the phone with @AppStorage, so the SOS tab can use it right away.

Concepts used: TabView, @AppStorage, @State, DragGesture, Task for the countdown timer, PhotosPicker, Link with tel: and sms: URLs

Issues/errors: The hardest part was getting the hold-to-count-down button to work. onLongPressGesture didn't let me show a countdown, so I used DragGesture with minimumDistance 0 to tell when the finger went down and came up, and cancelled the timer Task if they let go early. I also had to strip spaces and dashes out of the phone number and percent-encode the message so the call and text links would work.
Time spent: 8 hours

week 3 

Continued with 100 Days of SwiftUI, Days 15-21 — https://www.hackingwithswift.com/100/swiftui
Time spent: 7 hours

Part 2 
Apple juice tabs 

Issues/errors: Nothing much, getting used to swiftui 
Time spent: 6 hours

Week 2

Continued with 100 Days of SwiftUI, Days 8–14 — https://www.hackingwithswift.com/100/swiftui

Day	Topic	Hours	Issues / errors
8	Default values, throwing functions, and checkpoint 
9	Closures, passing functions into functions, and checkpoint
10	Structs, computed properties, and property observers	
11	Access control, static properties and methods, and checkpoint
12	Classes, inheritance, and checkpoint
13	Protocols, extensions, and checkpoint
14	Optionals, nil coalescing, and checkpoint
Total hours: 7

Part 2 — Text art playground

Week02/week2.playground — apple ASCII art using variables, loops, and string manipulation.

Issues / errors: None major — usual learning curve while getting comfortable with newer Swift concepts like classes and protocols.

resource: https://www.hackingwithswift.com/100/swiftui
progress: covered days 8-14 of swiftUI (closures, structs, classes, protocols, and optionals)
time spent: 7 hours
project: [your github link to week2.playground]
issues: no major issues — mostly just the normal learning curve of getting more comfortable with newer Swift concepts like classes and protocols

Week 1 
Started 100 Days of SwiftUI, Days 1-7 — https://www.hackingwithswift.com/100/swiftui
Hours Spent: 7 Hours
Issues / errors: Rough learning curve with learning swift fundementals, but I think I'll get the hang of it over time. 

Part 2: 
Homework was surprisingly easier than I expected. No troubles with it.


