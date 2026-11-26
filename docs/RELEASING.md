# Releasing

Pith updates itself with [Sparkle](https://sparkle-project.org) from `pith.edoardobertoli.xyz` (decision 48).

## Once

- `make update-key` creates the key that signs updates, in your keychain, and puts its public half in
  `Support/Info.plist`. Commit that.
- `npx wrangler login` connects to the Cloudflare account that has the domain.
- `make certificate` creates the local certificate every build is signed with (decision 41), so permissions survive
  updates.

## Each release

A release is published from `main`, the release branch, and nothing else: changes go from a feature branch or the
milestone branch into `staging`, then from `staging` into `main`, each through a pull request. Claude takes a change
into `staging` on its own, and asks Edoardo before anything goes from `staging` into `main` (decision 75).

1. On the feature or milestone branch, raise the version in `Support/Info.plist` (0.\<milestone\>.\<patch\>) and
   commit.
2. Push the branch, open a pull request into `staging` and merge it.
3. Ask Edoardo; when Edoardo says so, open a pull request from `staging` into `main` and merge it.
4. Check out `main` as it is on GitHub. `make install` it and run the checks below. It takes ⌘P from every app, so
   Claude asks first.
5. Run `make publish` on `main`. It builds and signs the app, zips it for the feed, makes the installer (`Pith.dmg`),
   tags the commit `v<version>`, and puts the zip, the installer, the signed update feed and the landing page online.
6. Push the tag, and create the GitHub release with `Pith.dmg` and the release notes.

`make package` alone makes the zip and the installer without publishing them.

## Checks on the installed build

`make lint test` covers what runs off screen, the panel's focus rules around Quick Look included (`PanelFocusTests`,
with a fake preview). These are the rest: real windows, the keyboard moving between apps, the clipboard and
notifications, which broke before (0.3.7's ⌘Y, and Quick Look taking the keyboard until 0.3.11). A few minutes, from
another app in front, TextEdit for the pastes:

1. **⌘P and typing:** the panel opens on the screen under the pointer, results follow each key, ⏎ opens the first, and
   ⎋ closes it.
2. **⌘K:** on an app and on a file, the actions list; ⌘W runs the second action; ⎋ goes back to the results.
3. **⌘Y, then a click in another app:** ⌘Y on a file shows it; ↓ moves the preview to the next file and typing still
   goes to the search; ⌘Y closes it. Open it again and click in another app: both close. Open it again and ⌘Tab:
   both close.
4. **⌘⇧V and ⏎ paste:** an older clip pastes into TextEdit; ⌘K → Paste as Plain Text pastes without formatting.
5. **⌃⌥V:** after copying three texts, three presses in TextEdit paste the newest, then the two before it.
6. **Reopening Pith.app** (Finder or Spotlight) while it runs opens the launcher.
7. **A config save:** change `empty_state` in Open Config and save: the next ⌘P shows it. A wrong value shows a
   problem row; put it back.
8. **Check for Updates:** its notification says what it found ("Pith is up to date" before the publish, since the
   feed still has the last version), and the Quit Pith tile shows the new version.

## What people get

- A first install comes from the Terminal line (`site/install.sh`), or from `Pith.dmg`: a window to drag Pith into
  Applications from, which says how to get past the first open.
- After that, Pith checks at most once a day and downloads an update in the background. Update Pith in the launcher
  restarts into it; otherwise it installs when Pith quits.
- Check for Updates in the launcher checks right away.
- A notification says when it has updated, or why it couldn't.
- Settings, history and Accessibility access carry over.
- The Quit Pith tile shows the version, so a report can say which build it's about.

Pith isn't notarized (decision 46), so the installer's first open needs Open Anyway in System Settings, Privacy &
Security; the Terminal line doesn't. Their Mac needs macOS 26 and Apple Silicon.

## The landing page

The site's front page is `site/index.html`. `make publish` deploys it with each release. To change only the page,
`make page` assembles it in `.build/site` to look at, and `make site` deploys it, keeping the published feed and
builds.
