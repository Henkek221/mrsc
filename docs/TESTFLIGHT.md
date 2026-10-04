# TestFlight

## Upload

1. In App Store Connect: **Apps → + → New App**. Platform iOS, Bundle ID `com.ecki.mrsc`, SKU frei wählbar (z. B. `mrsc`). Der Name muss im Store noch frei sein.
2. Archiv bauen (oder das vorhandene `build/MRSC.xcarchive` nehmen):
   ```bash
   xcodegen generate && xcodebuild -project MRSC.xcodeproj -scheme MRSC -configuration Release -destination 'generic/platform=iOS' -archivePath build/MRSC.xcarchive -allowProvisioningUpdates archive
   ```
3. `open build/MRSC.xcarchive` → Organizer → **Distribute App → App Store Connect → Upload**. Xcode legt dabei das Apple-Distribution-Zertifikat an, falls es fehlt.
4. Nach 10 bis 30 Minuten erscheint der Build unter **TestFlight**. Interne Tester (bis 100 aus dem Team) können sofort testen, ohne Review.

**Jeder weitere Upload braucht eine höhere Build-Nummer:** `CURRENT_PROJECT_VERSION` in `project.yml` hochzählen. App und Widget teilen sich die Nummer.

## Test Information (App Store Connect → TestFlight)

**Beta App Description**

> MRSC is a free, customizable music player for the music you own. It plays files on your iPhone, folders from iCloud Drive and songs from your own Jellyfin, Navidrome or Subsonic server, online or offline. No ads, no account.

**What to Test** (pro Build)

> First beta. Please try:
> - Onboarding and the demo library
> - Importing your own files or connecting your Jellyfin / Navidrome server
> - Playback, queue, crossfade and the equalizer
> - Lyrics, themes and the player layout editor
> - Widgets, Live Activity and Lock Screen controls
>
> To send feedback, take a screenshot and tap "Share Beta Feedback".

**Feedback Email:** deine Support-Adresse.

**Marketing URL:** https://mrsc.app
**Privacy Policy URL:** https://mrsc.app/datenschutz.html (erst nach dem Hochladen der Website erreichbar)

## Beta App Review (nur für externe Tester)

Sign-in required: **No**.

**Review Notes**

> MRSC is a local music player. No account is needed.
> To try it without your own music, tap "Or start with the demo library" at the end of onboarding. The demo songs are generated on the device.
> Server playback works with any Jellyfin or Subsonic-compatible server, for example the public Navidrome demo (https://demo.navidrome.org, user "demo", password "demo").
> NSAllowsArbitraryLoads is set because many self-hosted music servers run on plain HTTP in the user's home network.
