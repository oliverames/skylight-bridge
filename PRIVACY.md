# Skylight Bridge Privacy

Skylight Bridge moves the Apple Photos, Reminders, and Apple Notes items you select to your Skylight Calendar. It talks to Skylight's servers, to your private iCloud database for shared preferences and photo mappings, and to Sparkle's update feed on GitHub. The only other data that leaves your Mac is the crash and error reporting described below.

## Crash and error reports

Release builds send crash reports and sync error codes to the developer through [Sentry](https://sentry.io), so crashes can be found and fixed. Reporting is on by default and you can turn it off at any time in **Sync > Privacy > Share crash reports** in the main window. Turning it off stops the reporting SDK at once. Builds made from source have reporting off unless the developer adds the Sentry key at build time.

A report contains:

- For a crash: the exception type, and each thread's stack of function names and code addresses, with file paths reduced to a file name or a location inside the app or macOS.
- For a sync or account failure: a fixed description such as "Sync failed", plus the error's domain and number. Error messages are never sent, because they can name a list or an account. At most one report of each kind is sent an hour, and none for offline or cancelled requests.
- A few steps leading up to the problem, such as "Sync started", with counts of planned and applied changes.
- The app version and build, the macOS version, and the Mac's model, architecture, and memory and storage sizes.

A report never contains your Skylight email, password, or tokens; frame, device, or household member names; Reminders lists or items; recipes, notes, or meals; photo names, albums, or the photos themselves; calendar data; file names or folder paths; your Mac's name or your account name; your location, time zone, or language; or your IP address. The reporting SDK sends no usage analytics, sessions, performance traces, screenshots, or network requests, and the Sentry project discards IP addresses and user and location data on arrival.

Reports are cleaned twice before they leave your Mac: the app keeps only the allowlisted fields above, then removes anything in the remaining text that looks like a name in quotes, an email address, a web address, a file path, an identifier, or a token.
