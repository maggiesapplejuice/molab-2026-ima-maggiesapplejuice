## Week 10: Final project proposal

### SOS: a personal safety app

**The idea:** One big button you hold for 3 seconds when you feel unsafe. It gets you to the people who can help as fast as possible, lets them follow you live, and keeps a record of what happened.

**Who it's for:** People walking home alone at night, people on a first date, anyone who has ever held their keys between their fingers. And the friend or parent on the other end who wants to know "are you ok, where are you?"

**What already works (Weeks 4–9):**
- Hold SOS for 3 seconds, then call 911 or call/text my emergency contact in one tap
- Safety kit: name, photo, emergency contact, blood type, allergies, medications
- Evidence: photos and videos stamped with the time and GPS location on every frame
- Live alert (Firebase): my contact types a 6-letter code, follows my location on a map, and taps "I'm on my way". I see "Mom is on the way" on my screen.

**What I'm adding for the final:**

| | Feature | Why |
|---|---|---|
| Must | **Background location** | Right now sharing stops when the app is closed or the phone locks. In a real emergency the phone is in your pocket. |
| Must | **Check-in timer ("walk me home")** | Set 15 min for your walk. If you don't tap "I'm safe" in time, SOS starts by itself. Helps when you can't press anything. |
| Must | **Lock screen Live Activity** | Shows the alert status, the timer, and "Mom is on the way" without unlocking the phone. |
| Must | **Test with real people** | Friends on two phones, walking a real route, then fix what's confusing. |
| Should | **Upload evidence to Firebase Storage** | So photos/videos are safe even if someone takes or breaks my phone. |
| Stretch | **Push notifications to my contact** | So they get the alert in the app, not only as a text with a code. Needs Cloud Functions + APNs. |

**Not doing (cut on purpose):** a separate follower app or Apple Watch app. The Follow tab inside the same app is enough for the demo.

---

### Week-by-week plan

**Week 10: Proposal + background location**
- Write this proposal, make the `week 10` folder, move my Week 9 code in
- Pair up for feedback on the proposal
- Turn on background location (`allowsBackgroundLocationUpdates`, "Always" permission, the blue location bar). Test: start an alert, lock the phone, walk around the block. Does the follower's map keep moving?

**Week 11: Check-in timer**
- "Walk me home" screen: pick a time, start, big "I'm safe" button
- Local notification 1 minute before it runs out ("Are you ok?")
- If time runs out: start the live alert and text my contact automatically
- Decide on privacy: keep the 6-letter code, or let only my saved contact open the alert

**Week 12: Live Activity**
- Add a widget extension with ActivityKit
- Lock screen + Dynamic Island show: timer left, alert on/off, who is coming
- The app updates the Live Activity itself while it runs in the background (no server push needed)

**Week 13: Evidence upload + user testing**
- Upload photos/videos to Firebase Storage under the alert, show them on the follower's screen
- Test with 2–3 friends on two phones on a real walk. Write down every moment they hesitate.
- Stretch: push notifications with Firebase Cloud Messaging

**Week 14: Polish + present**
- Fix what came up in testing
- Make sure the app still works with no internet or no Firebase (calls and texts must never depend on it)
- Record a demo video, make the slides, present

---

### Biggest risks / questions
- **Background location:** Apple is strict about "Always" location. If it doesn't work well, the fallback is "While Using" + a Live Activity, which keeps the app alive in the background.
- **Privacy:** Is a 6-letter code enough, or should only my saved contact be able to open the alert?
- **Push notifications** need a paid Apple developer account and Firebase Cloud Functions (Blaze plan). That's why it's a stretch goal.
- **Code vs link in the text:** a tappable link is easier for a parent, but needs Universal Links and a website.

### Feedback from my pair
- Partner:
- What they liked:
- What was confusing:
- What I'm changing:

---

### Progress | Problems | Plans | Questions

- **Progress:** Wrote the final proposal and week-by-week plan. Week 9 live alert works between two phones.
- **Problems:** Location sharing stops when the phone locks, which is exactly when it matters most.
- **Plans:** Background location this week, then the check-in timer in Week 11.
- **Questions:** Is "Always" location worth it, or is a Live Activity enough to keep sharing going? Can a free Apple developer account do Live Activities?
