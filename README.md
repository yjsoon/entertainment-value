# Entertainment Value

Entertainment Value (EVal) is an iPhone app for logging what you watch, read, play and listen to, and for seeing what your entertainment subscriptions cost you per hour of use.

It is built with SwiftUI and SwiftData for iOS 26, with no third-party dependencies and no backend.

## The app

- **Today** is a daily check-in. Everything you're in the middle of gets one row and one control: "+" for an episode of a show or podcast (so "Andor ×2", with no episode numbers), "Read", "+5%" or a typed percentage for a book, "Played" for a game and "Watched" for a film. Tapping again undoes it. A row you've logged takes a tint of its medium's colour, and the dots in the header fill in as you go. Finishing something opens a half-star rating dial and an optional one-line note.
- **Log** (from Today, or inside Library) shows each day's chips ("Andor ×2", "Piranesi 38 → 43%", "Glass Onion finished"), a strip of the month's days coloured by what you did most, and the month's flower in the six colours of the app icon. Empty days fold into a line with an "Add" button, which opens the check-in for that day.
- **Value** shows what your subscriptions cost per hour you used them this month, a bar split by what each one cost, and each service as a card, cheapest per hour first. Annual plans are spread across twelve months, shared plans count only your share, trials cost nothing, and foreign prices use the exchange rate you entered at the time. Services you paid for and didn't use are marked "Idle". Things you bought outright show what they've cost per hour so far.
- **Library** is a shelf of everything you've added, filtered by status, with each title in a fixed two-line slot so the rows line up.
- Tapping any item opens its **edit screen**: the title, how a book counts progress (just "read", a percentage or pages), where it's from (a subscription, bought, the library, borrowed, a gift or free), its status and its history, where any day can be removed.
- **+** searches films, TV, books, games and podcasts at once. Anything missing can be added by hand.

There is one log per item per day. Each records how its time was worked out: measured (you picked a length), derived (from runtime or page count) or estimated (a typical length for the medium, or a reading speed of 40 pages an hour). Logs are linked to a service automatically, using the item's own service first and then the service you last used for that kind of thing.

The typeface is [Bricolage Grotesque](https://github.com/ateliertriay/bricolage), bundled as static cuts under the SIL Open Font License (`EntertainmentValue/Resources/Fonts/OFL.txt`).

## Requirements

- Xcode 26
- iOS 26

Open `EntertainmentValue.xcodeproj`, choose the `EntertainmentValue` scheme and an iOS 26 simulator, then run.

Film and TV search uses TMDB, and game search uses RAWG. Copy `Configuration/Secrets.xcconfig.local.example` to `Configuration/Secrets.xcconfig.local` and fill in `TMDB_READ_ACCESS_TOKEN` and `RAWG_API_KEY`. Books (Open Library) and podcasts (Apple Podcasts) need no keys, and manual entry always works.

## Tests

The value maths, logging rules and store are covered by unit tests in `EntertainmentValueTests`. Every push runs the build and tests on a macOS runner (`.github/workflows/ios-build.yml`).

## Data

Everything is stored on the device. CloudKit is switched off for now; the model gives every stored property a default so that private sync can be turned on later.

## License

Entertainment Value is available under the MIT License.
