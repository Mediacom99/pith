# Releasing

Pith updates itself with [Sparkle](https://sparkle-project.org) from `pith.edoardobertoli.xyz` (decision 48).

## Once

- `make update-key` creates the key that signs updates, in your keychain, and puts its public half in
  `Support/Info.plist`. Commit that.
- `npx wrangler login` connects to the Cloudflare account that has the domain.
- `make certificate` creates the local certificate every build is signed with (decision 41), so permissions survive
  updates.

## Each release

1. Raise the version in `Support/Info.plist`: 0.\<milestone\>.\<patch\>.
2. Commit.
3. Run `make publish`. It builds and signs the app, zips it for the feed, makes the installer (`Pith.dmg`), tags the
   commit `v<version>`, and puts the zip, the installer, the signed update feed and the landing page online.
4. Push the branch and the tag, and create the GitHub release with `Pith.dmg` and the release notes.

`make package` alone makes the zip and the installer without publishing them.

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
