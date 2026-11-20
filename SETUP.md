# Sift setup

Sift is an iPhone app that shows Instagram DMs and YouTube Subscriptions and nothing else.
It loads the mobile websites in its own browser and filters them (the same approach SocialLite uses).
GitHub Actions builds the app on a Mac in the cloud and uploads it to TestFlight.

Do these steps once, in this order.

## 1. Register the bundle ID

1. Go to https://developer.apple.com/account/resources/identifiers/list
2. Click **+**, choose **App IDs**, then **App**.
3. Description: `Sift`. Bundle ID: **Explicit**, `com.shawnzhu.sift`.
4. Don't tick any capabilities. Click **Continue**, then **Register**.

## 2. Create the app in App Store Connect

1. Go to https://appstoreconnect.apple.com/apps
2. Click **+**, then **New App**.
3. Platform **iOS**, name `Sift` (if taken, try `Sift Focus`), language English, bundle ID `com.shawnzhu.sift`, SKU `sift`.
4. Choose **Full Access** and click **Create**.

## 3. Create an App Store Connect API key

1. Go to https://appstoreconnect.apple.com/access/integrations/api
2. If asked, click **Request Access** first and accept.
3. Click **+** (Generate API Key). Name it `GitHub Sift`, access **Admin**. Admin lets the cloud build create its own signing certificate.
4. Download the `.p8` file. Apple only lets you download it once.
5. Note the **Key ID** (on the key's row) and the **Issuer ID** (above the table).
6. Find your **Team ID** at https://developer.apple.com/account under Membership details.

## 4. Give the keys to GitHub

Run these in Git Bash, replacing the values and the .p8 path:

```bash
cd ~/Programming/sift
gh secret set ASC_KEY_ID --body "YOUR_KEY_ID"
gh secret set ASC_ISSUER_ID --body "YOUR_ISSUER_ID"
gh secret set APPLE_TEAM_ID --body "YOUR_TEAM_ID"
gh secret set ASC_KEY_P8 < ~/Downloads/AuthKey_YOUR_KEY_ID.p8
```

Then move the .p8 file somewhere safe (not Downloads). Anyone with it can manage your Apple apps.

## 5. Build and install

1. Start a build: `gh workflow run iOS` (or push any change). Watch it with `gh run watch`.
2. When the run is green, wait 5-15 minutes for Apple to process the build.
3. In App Store Connect, open Sift, then **TestFlight**. Under **Internal Testing**, create a group, add yourself, and add the build.
4. On your iPhone, open the **TestFlight** app and install Sift.
5. If App Store Connect asks about export compliance, the app already says it uses no non-exempt encryption.

## 6. First run

1. Open Sift. The Connect screen has a **Connect** button for Instagram and for YouTube. In each login form, tap the password box, then **Passwords** above the keyboard, to fill your saved password with Face ID.
2. Swipe left or right anywhere to switch between Messages, Subscriptions and Settings. Settings shows whether each account is connected.
3. Delete the native Instagram and YouTube apps, or block them (next section). If they stay, nothing stops you opening them.

## 7. Blocking the native apps

**Now (no code needed):** Settings, then Screen Time, then App Limits. Add a limit of 1 minute a day for Instagram and YouTube. Turn on **Block at End of Limit**. Let a friend set the Screen Time passcode so you can't just tap "Ignore Limit".

Optional: also block the websites in Safari, so Safari isn't a way around Sift. Go to Screen Time, then Content & Privacy Restrictions, then App Store, Media, Web & Games, then Web Content, and choose **Limit Adult Websites**. Under **Never Allow**, add `instagram.com` and `youtube.com`. Check that Sift still loads after this. If it doesn't, remove them from the list.

**Later (Sift does it itself):** Sift has code to block the native apps with Apple's Screen Time API. Apple has to approve the Family Controls entitlement first:

1. Go to https://developer.apple.com/contact/request/family-controls-distribution
2. App: Sift, bundle ID `com.shawnzhu.sift`. Paste this as the description:

   > Sift is a personal digital wellbeing app. The user picks apps they want to stop opening (for example Instagram and YouTube) with FamilyActivityPicker. Sift shields those apps with ManagedSettings so the user can only reach messages and subscriptions through Sift's filtered view. Authorization is individual (`.individual`), on the user's own device. No data leaves the device and nothing is shared with us or third parties.

3. When Apple approves it (days to weeks), ask Claude to turn on `SHIELD` for the TestFlight build. The code is in `Sift/Shield/ShieldManager.swift`. CI already compile-checks it.

## Fixing filters later

YouTube and Instagram change their pages. If something sneaks back in (for example a Shorts row), the fix is a selector in `Sift/Resources/youtube.css`, `youtube.js`, `instagram.css` or `instagram.js`. URL rules live in `Sift/Router.swift`, and their tests are in `SiftTests/RouterTests.swift`. Push to `main` and a new TestFlight build is uploaded.

## Known limits

- No push notifications for DMs. Only the native Instagram app gets those.
- Any self-blocker can be bypassed (delete Sift, change Screen Time). The goal is friction, not a prison.
- GitHub's free plan gives a private repo about 200 macOS minutes a month. One build uses about 10.

## Friends beta (TestFlight public link)

Friends install Sift through one TestFlight link. Apple reviews the first build for outside testers (usually within a day); later builds of the same version often go through faster.

**One-time setup.** Set these once from Git Bash in this folder (they stay out of the code):

```
gh variable set BETA_FEEDBACK_EMAIL --body "you@example.com"
gh variable set BETA_CONTACT_FIRST --body "First"
gh variable set BETA_CONTACT_LAST --body "Last"
gh variable set BETA_CONTACT_EMAIL --body "you@example.com"
gh secret set BETA_CONTACT_PHONE --body "+1 555 555 5555"
```

`BETA_PRIVACY_URL` is already set; it points to a secret gist made from `PRIVACY.md`. Optional: `gh variable set BETA_LINK_LIMIT --body 50` caps how many people can join through the link.

Apple shows the contact details only to its reviewers, never to testers.

**Each time you want friends on a new build:**

1. Push to `main`. CI uploads the build. Wait until it finishes processing in App Store Connect (5-15 min).
2. Run `gh workflow run beta.yml`, or open the repo's **Actions** tab, choose **Friends beta**, then **Run workflow**. To send a specific build, pass `-f build=12`.
3. The run fills in the test information, adds the build to the **Friends** group and submits it to Beta App Review.
4. Once Apple approves the build, run it once more. The run's summary prints the public link (`https://testflight.apple.com/join/...`). Text that link to friends. They install the TestFlight app, tap the link, then tap **Install**.

Friends sign in with their own Instagram and Google accounts. Sift has no account of its own.
