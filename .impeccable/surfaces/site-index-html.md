---
version: 1
slug: "site-index-html"
primary_target: "site/index.html"
related_targets: ["Makefile"]
---

# Surface: the landing page

Scope: the front page of pith.edoardobertoli.xyz. Mode: Persuade.

- **Audience:** Edoardo's friends and people online, arriving from a shared link, mostly on a Mac.
- **Job and action:** decide to try Pith; copy `curl -fsSL https://pith.edoardobertoli.xyz/install.sh | sh` and paste it in Terminal, with no Open Anyway: the page's main action (decisions 57, 67). The other way is quieter: Pith.dmg (decision 56), dragged into Applications, then opened once with Open Anyway. The setup section shows the line, then the installer's steps as they will look, and says how settings change and updates arrive.
- **Proof:** the real panel snapshots from `docs/snapshots/`, light and dark; measured numbers only, with the machine
  and the method in one quiet line under the reasons (step 8, 2026-11-24, an M4 Pro MacBook Pro): 62 MB and 0 % CPU an
  hour into use, under 3 ms of work per keystroke over 35,800 files, a month of clipboard opening in 1.4 ms and adding
  about 7 MB. A FAQ before the close answers what a first visit asks (curl | sh, notarization, the alternatives, safety,
  Claude as a pair programmer).
- **Constraints:** static files served by the Worker in `Support/wrangler.toml`, beside the update feed; no claims
  beyond `FEATURES.md` and the measurements; no Raycast text, logo or artwork. The repo is public (decision 65): the bar has the GitHub mark beside Download, and the footer says Source on GitHub.
- **Answers (Edoardo, 2026-11-23):** the headline leads with fast and small; Edoardo's first-person "why" names
  Raycast once; features are what ships (launcher, ⌘K, clipboard, updates), and the calculator is one line under
  "coming next".
- **Memorable moment:** the page is driven like Pith: its keys press themselves once through a tour, and ⌘P, ⌘K, ⌘⇧V or typing "te" switch the hero panel in one frame.
- **Phones:** below 600 px the drawn keyboard becomes a list of the same keys and meanings.

## Direction contract

THESIS: Pith's page is driven like Pith: the visitor presses ⌘P, ⌘K or ⌘⇧V and the real panel changes state in one frame. It refuses the category's glowing gradient hero and looping product video: the proof is the actual panel at its actual size, and quiet everywhere else.

OWN-WORLD: Stage carried to the web. macOS window neutrals only: ground #141414 / #ECECEC, the panel's #1E1E1E / #FFFFFF, label at 85 %, quiet #A1A1A1 / #666666; no accent and no brand hue, and the main action (Copy beside the Terminal line, the bar's Install) is the label color itself. SF Pro (the system face, as in the app) at display sizes with tight tracking; SF Mono only for the config file. Key caps (7 px corners, an edge and a soft offset shadow) are the one component language: buttons, the demo and the keyboard are keys. The panel snapshots change in one frame, as the app does; the motion lives in the keys (Edoardo asked for animation, 2026-11-23): keys press down and ease up, the hero plays its tour once, the ⌘K and ⌘⇧V rows press their own keys as they arrive, the config block retypes a value, the drawn keyboard plays chords. Nothing fades a panel or loops, and Reduce Motion plays nothing by itself.

STORY: A friend's link opens. In one viewport they read that Pith is a fast, small launcher, see the real panel, and press a key to watch it work. Scrolling, they learn the keys and four reasons (fast, small, private, native), then the launcher, ⌘K, the clipboard and the config file, read Edoardo's why, and download knowing about Open Anyway.

FIRST VIEWPORT: A sticky bar: the Pith wordmark left, with a quiet "Beta" beside it (decision 69); Keys, Features, Clipboard, Config, Why; the GitHub mark (quiet, the label on hover) and an Install key right, to the setup. Centered below: the one-line H1 "Fast, small, and out of your way." at about 4.5rem, one sentence under it, "Install it with one line in Terminal" over the command and its label-colored Copy, "Free · Beta · macOS 26 or later · Apple Silicon" beneath (free: decision 52; beta: decision 69), and a quiet "Or download Pith.dmg" line (decision 67); then four key-cap buttons (⌘P Launcher, te Search, ⌘K Actions, ⌘⇧V Clipboard) above the 680 px panel snapshot at its real size. Adaptation (finish review): the keys sit above the panel so they are in the first viewport on a laptop, and the panel's bottom may cross the fold. The primary action, the Terminal line, sits above both.

FORM: Raycast's landing structure, pinned by Edoardo: a hero with a short claim and Download, a keyboard of key caps with four callouts, alternating feature rows, a personal note, a closing call to action and a footer, minus the store, AI, extensions, testimonials, community and developer sections. Translation: Raycast's red glow and artwork become Pith's monochrome Stage, and its keyboard becomes the map of Pith's own keys. seed: none (pinned) "look at raycast landing page and basically copy it for pith, removing what we dont have/need"

FINISH: unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance
