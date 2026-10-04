# MRSC website

Static page, no build step: `index.html`, `styles.css`, `app.js`, `assets/`.

Run it locally:

```bash
python3 -m http.server 8777 --directory website
```

Add `?nosplash` to the URL to skip the startup animation while you work on it.

## Screenshots

The raw iPhone screenshots live in `screenshots/` (about 100 MB, not needed online). The page uses the small WebP copies in `img/` (about 1.3 MB). After adding or replacing screenshots, map the file in `MAP` in `tools/build_shots.py` and run:

```bash
python3 website/tools/build_shots.py
```

It erases the real status bar (time, battery, "◂ Instagram") so the page can draw a clean 9:41 one, and writes `img/shots.json`. Theme cards use `img/home-<theme>.webp` on the front and `img/player-<theme>.webp` on the back. If an image is missing, the phone draws the screen itself.

## Animoji

The skull and the boar in "all in one app btw" are Apple's 3D Animoji stickers (`exploding_head` and `pouting_face`), rendered on a Mac with `tools/render_animoji.swift` (instructions at the top of the file), then cropped and saved as WebP in `img/animoji/`.

## Links

Set `LINKS.testflight` at the top of `app.js`. Until then the buttons say "Coming soon to TestFlight".

The Discord invite appears in the nav, the hero, under the theme carousel, as cards in the reviews band, in two FAQ answers, in the finale, the footer and on the 404 page. To swap it everywhere:

```bash
python3 website/tools/set_discord.py https://discord.gg/NEWCODE
```

The member count on the Discord cards ("there are 2 of us. be number 3.") is fetched when you run `build_dist.py` (via `tools/discord_counts.py`), so visitors never connect to Discord. The card lines are in `DISCORD` in `app.js`.

GitHub and Ko-fi live on their own page, `open-source.html` (linked in the nav and the footers). The GitHub icon in the nav, the glance list, the FAQ and `llms.txt` link to them too. They start as placeholders; set the real ones everywhere with:

```bash
python3 website/tools/set_links.py --github https://github.com/NAME/mrsc --kofi https://ko-fi.com/NAME
```

The page only links to GitHub and Ko-fi and embeds nothing from them, so the Datenschutz page needs no changes.

`impressum.html` is the imprint (same operator as criticaize.app). The page loads no fonts or scripts from other servers, so there is nothing to declare there.

## SEO and AI search

- `index.html` has the title, description, canonical URL, share image (`img/og-image.jpg`) and structured data (MobileApplication, FAQPage) for Google and AI assistants.
- `llms.txt` is a plain summary for ChatGPT, Claude, Perplexity and co. `robots.txt` lets every crawler in, `sitemap.xml` lists the page.
- The domain is a placeholder (`https://mrsc.app`). Once you know the real one:

```bash
python3 website/tools/set_domain.py https://your-domain.tld
```

- Share image and PNG icons come from `tools/build_social.py`.
- When something changes in the app, update the facts in three places: the "MRSC at a glance" list and the FAQ in `index.html` (the FAQ is mirrored in the structured data at the top of the same file), and `llms.txt`.

## Logo

The stamp animation uses the brushed letters from `Branding/wordmark/wordmark.svg`. After changing the logo, run:

```bash
python3 website/tools/build_assets.py
```
