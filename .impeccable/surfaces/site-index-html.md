---
version: 1
slug: "site-index-html"
primary_target: "site/index.html"
related_targets: ["Makefile"]
---

# Surface: the landing page

Scope: the front page of pith.edoardobertoli.xyz. Mode: Persuade.

- **Audience:** Edoardo's friends and people online, arriving from a shared link, mostly on a Mac.
- **Job and action:** decide to try Pith; Download for Mac (`/Pith.zip`), then open it once with Open Anyway.
- **Proof:** the real panel snapshots from `docs/snapshots/`, light and dark; measured numbers only: 44 MB and 0 % CPU
  idle (`make stats`, 2026-11-23), about 2 ms of work per keystroke over 111 apps and 35,000+ files (milestone 2).
- **Constraints:** static files served by the Worker in `Support/wrangler.toml`, beside the update feed; no claims
  beyond `FEATURES.md` and the measurements; no Raycast text, logo or artwork; the repo is private, so no source link.
- **Answers (Edoardo, 2026-11-23):** the headline leads with fast and small; Edoardo's first-person "why" names
  Raycast once; features are what ships (launcher, ⌘K, clipboard, updates), and the calculator is one line under
  "coming next".
- **Memorable moment:** the page is driven like Pith: ⌘P, ⌘K, ⌘⇧V or typing "te" switch the hero panel in one frame.
- **Phones:** below 600 px the drawn keyboard becomes a list of the same keys and meanings.

## Direction contract

THESIS: Pith's page is driven like Pith: the visitor presses ⌘P, ⌘K or ⌘⇧V and the real panel changes state in one frame. It refuses the category's glowing gradient hero and looping product video: the proof is the actual panel at its actual size, and quiet everywhere else.

OWN-WORLD: Stage carried to the web. macOS window neutrals only: ground #141414 / #ECECEC, the panel's #1E1E1E / #FFFFFF, label at 85 %, quiet #A1A1A1 / #666666; no accent and no brand hue, and the download button is the label color itself. SF Pro (the system face, as in the app) at display sizes with tight tracking; SF Mono only for the config file. Key caps (7 px corners, an edge and a soft offset shadow) are the one component language: buttons, the demo and the keyboard are keys. State changes are instant; nothing fades or slides.

STORY: A friend's link opens. In one viewport they read that Pith is a fast, small launcher, see the real panel, and press a key to watch it work. Scrolling, they learn the keys and four reasons (fast, small, private, native), then the launcher, ⌘K, the clipboard and the config file, read Edoardo's why, and download knowing about Open Anyway.

FIRST VIEWPORT: A sticky bar: the Pith wordmark left; Keys, Features, Clipboard, Why, Install; a Download key right. Centered below: the one-line H1 "Fast, small, and out of your way." at about 4.5rem, one sentence under it, the Download for Mac button with "Free · macOS 26 or later · Apple Silicon" beneath (free: decision 52); then four key-cap buttons (⌘P Launcher, te Search, ⌘K Actions, ⌘⇧V Clipboard) above the 680 px panel snapshot at its real size. Adaptation (finish review): the keys sit above the panel so they are in the first viewport on a laptop, and the panel's bottom may cross the fold. The primary action sits above both.

FORM: Raycast's landing structure, pinned by Edoardo: a hero with a short claim and Download, a keyboard of key caps with four callouts, alternating feature rows, a personal note, a closing call to action and a footer, minus the store, AI, extensions, testimonials, community and developer sections. Translation: Raycast's red glow and artwork become Pith's monochrome Stage, and its keyboard becomes the map of Pith's own keys. seed: none (pinned) "look at raycast landing page and basically copy it for pith, removing what we dont have/need"

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
