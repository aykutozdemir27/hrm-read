# HRM Read — first iPhone build

## Version 0.2.0

- Automatically reconnects to the same selected strap after an unexpected disconnection. Stop cancels retries; quitting the app ends the session. Initial connection/setup failures still report a message. Turning Bluetooth back on resumes a pending session.
- Settings → Keep screen awake (on by default) prevents automatic screen locking only while the app is visible and scanning, connecting, or connected. Disconnecting or leaving the app restores normal screen locking.
- Settings → Maximum HR alert lets you enter your own BPM limit and enable sound. No threshold is assumed; alerts are off by default. Two seconds of consecutive fresh readings strictly above the limit start a looping beep pattern that continues until HR drops strictly below the limit. Exactly at the limit, an active alarm continues but a new alarm does not start. Contact loss, stale data, disabling the alert, or leaving the app stop the sound and reset the delay. This is a training cue.
- Test sound uses the same alert. Audio uses media volume/current output and plays in silent mode, mixing with music. Bluetooth headset routing, volume, and interruptions need real-device testing. Background monitoring is still not implemented.
- Display and alert options save immediately; Save commits zone boundaries. Existing zone settings retain the same storage key.

### Version 0.2 device checks

1. Install over the existing app using the same Apple Account and bundle ID; confirm your zones remain.
2. Connect the strap, move it out of range or power-cycle it, then bring it back: BPM clears and reconnects without selecting a different strap. Tap Stop while reconnecting: it must not reconnect until you start again.
3. Turn phone Bluetooth off/on during a session; verify reconnection. Contact loss without a Bluetooth disconnection should show a contact message, not reconnect endlessly.
4. Keep screen awake on: wait past the normal auto-lock interval while connected. Turn it off or disconnect: normal auto-lock resumes. Leaving/reopening the app should also restore/reapply the appropriate behavior.
5. Set a temporary alert limit below your current resting HR to test without exercising harder. Enable the alert: continuous repeated beeps after two seconds. At exactly the threshold, an active alarm should continue; it stops when HR drops strictly below the threshold. Raise the limit above your current HR: sound stops. Turn the alert off: no sound. Restore your preferred limit afterwards.
6. Test sound with silent mode, headphones, music playing, and different media volumes. Remove the strap: no new HR alerts should occur. Locking the phone or changing apps is outside foreground alert support.

Tests in `Tests/MaxHRAlertTests.swift` cover sustained readings, exact-limit behavior, continued beeping, transient spikes, stale/missing samples, disabled alerts, and invalid limits. Cloud compilation and simulator tests are necessary; Windows cannot run Xcode.

A native iPhone app for live Bluetooth heart rate and five configurable zones. Designed for iPhone SE (2020); minimum iOS 16. No accounts, recording, or uploads inside the app. Uses the Bluetooth Heart Rate Service (180D) and notifications (2A37).

## Start here on Windows

You need a free GitHub account, a free Apple Account, your iPhone, and a USB cable. No personal Mac or paid Apple Developer membership is needed. GitHub supplies the cloud Mac that compiles the source. The public-repository route makes your source public; never upload passwords or signing credentials.

### 1. Create the GitHub repository

1. Sign in at https://github.com and choose **New repository**.
2. Name it **hrm-read**, choose **Public**, and create it. Do not initialize it with a README.
3. On the empty repository page choose **uploading an existing file**.
4. Upload the contents of this project (not the outer project folder). The repository root must contain `project.yml`, `Sources`, `Tests`, and `.github/workflows/ios.yml`. Windows hides dot folders sometimes: enable **View → Show → Hidden items** in File Explorer. Drag the `.github` folder as well as the other files into GitHub's upload area.
5. Commit the upload to `main`.
6. Open the repository's **Actions** tab. Choose **Build iPhone app**. If necessary enable Actions, then choose **Run workflow** on the `main` branch.
7. Wait for the run to finish. Open the completed run, find **Artifacts**, and download **HRMRead-iPhone**. Unzip it to obtain `HRMRead.ipa`.

If the run fails, open the red step and share its error text. This first source version has not yet been compiled: this Windows workspace has no Xcode or Swift compiler. The cloud workflow runs parser/zone tests on an iPhone simulator before packaging the device build. Simulator tests cannot verify real Bluetooth.

### 2. Install from Windows

1. Download Sideloadly only from https://sideloadly.io/ and follow its Windows prerequisites. Install the Apple device support components it specifies.
2. Connect the iPhone by USB, unlock it, and tap **Trust** if asked.
3. Open Sideloadly and select the phone. Drag `HRMRead.ipa` into it.
4. Enter your Apple Account in Sideloadly and complete Apple's authentication there. Do not put your password in GitHub, this project, or chat.
5. Start installation. If requested, trust the developer profile under **Settings → General → VPN & Device Management**.
6. If requested, enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm.
7. Open **HRM Read** on the phone.

Free signing expires after seven days. Enable Sideloadly's automatic refresh; its helper must be running and the phone reachable over USB or configured Wi-Fi. Refreshing an existing build does not require compiling it again. Free signing also limits the number of installed apps. Exact operation on your iOS version must be confirmed with the first installation.

### 3. Connect the Garmin strap

1. Put on the strap and moisten its electrodes.
2. Wake the HRM 200 with its button. Garmin documents a quick double press to change connection type; open mode flashes three times every five seconds. Use open mode for this first third-party app test.
3. Hold the button for four seconds to enter pairing mode if needed.
4. Tap **Find strap** in HRM Read and allow Bluetooth access.
5. Tap your strap in the results. Nearby heart rate straps may also appear; the app does not assume the first result is yours.
6. Check that the BPM updates. If the signal stops for over six seconds, the number clears rather than displaying an old reading.
7. Open the sliders button and enter the four lower boundaries for Zones 2–5 from your existing Garmin settings. Zones remain unset until you save valid boundaries.

Keep the app visible. Background monitoring and workout saving are not implemented. Version 0.2 automatically reconnects to the same strap after a dropped connection until you tap Stop. If you cannot discover the device, verify open mode and temporarily disconnect other apps/devices using the strap.

## First real-device check

- Allow Bluetooth; confirm discovery, select your strap, and see changing BPM.
- Deny Bluetooth once and verify the app explains how to allow it in Settings.
- Turn Bluetooth off: the BPM should clear.
- Remove or move away from the strap: old readings should disappear within about six seconds after the last notification.
- Reconnect through Find strap.
- Enter your zone boundaries; check the displayed zone against the same boundaries in Garmin.
- Close and reopen the app: zone settings should persist.

## References

- GitHub hosted runners: https://docs.github.com/en/actions/using-github-hosted-runners/about-github-hosted-runners
- Sideloadly installation and free-signing refresh: https://sideloadly.io/faq.html
- Garmin HRM 200 manual: https://static.garmin.com/pumac/hrm200.pdf
- Bluetooth Heart Rate Service: https://www.bluetooth.com/wp-content/uploads/Files/Specification/HTML/HRS_v1.0/out/en/index-en.html

## Project files

`Sources/` contains the app; `Tests/` verifies measurement formats, contact flags, malformed packets, and zone boundaries. `project.yml` generates the Xcode project using XcodeGen. `.github/workflows/ios.yml` builds, tests, and packages an unsigned IPA, which Sideloadly signs on Windows.
