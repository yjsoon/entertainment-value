# Entertainment Value

Entertainment Value (EVal) is an iPhone app for logging what you watch, read, play and listen to, and for seeing what your entertainment subscriptions cost you per hour of use.

It is built with SwiftUI and SwiftData for iOS 26, with no third-party dependencies and no backend.

## The app

- **Now** shows what you are in the middle of. Each card has one button for the obvious next step: "Finished", "Watched S2 E6", "+25 pages" or "Played". Every log drops a petal into this month's flower, which uses the six colours of the app icon (comics, films, podcasts, games, TV and books). Finishing something opens a half-star rating dial and an optional one-line note.
- **Money** shows the month's total spend and the cost per hour for each service. Annual plans are spread across twelve months, shared plans count only your share, trials cost nothing, and foreign prices use the exchange rate you entered at the time. Services you didn't use that month are marked "Idle" in grey. Figures based partly on estimated time are marked "roughly".
- **Library** is everything you've added, as a cover grid, plus a diary of every log grouped by month.
- **+** searches films, TV, books, games and podcasts at once. Anything missing can be added by hand.

Each log records how its time was worked out: measured (you picked a length), derived (from runtime or page count) or estimated (a typical length for the medium). Logs are linked to a service automatically, using the item's own service first and then the service you last used for that kind of thing.

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
