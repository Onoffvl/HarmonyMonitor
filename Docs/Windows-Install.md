# Build on GitHub and install from Windows 11

You need your Windows PC, iPhone 17 Pro, a USB data cable, GitHub account and Apple Account. GitHub’s macOS runner compiles the app and produces an IPA. AltServer on Windows signs it to your Apple Account and installs it on your iPhone. An ordinary iPhone requires the device-specific signing step before it can open the app.

## 1. Put the project on GitHub

1. In File Explorer, right-click `HarmonyMonitor.zip` and select **Extract All**. Open the extracted **HarmonyMonitor** folder that contains `README.md`, `HarmonyMonitor.xcodeproj` and `.github`. This folder is the repository root.
2. Install [GitHub Desktop](https://desktop.github.com/) and sign in to your GitHub account.
3. In GitHub Desktop, choose **File → Add local repository** and select that **HarmonyMonitor** folder. When prompted, select **create a repository here instead**. Confirm the path ends at the folder with the existing README. Leave the options for generating a README, license and ignore file unchecked or set to **None**. The project includes them already.
4. If Desktop shows files on **Changes**, enter `Add Harmony Monitor` as the commit summary and choose **Commit to main**. Check that `.github/workflows/build-ios.yml` is part of the commit. Desktop may create the initial commit automatically.
5. Choose **Publish repository**, enter `HarmonyMonitor` and choose the visibility. A private repository uses your included Actions allowance. Public repositories have free standard GitHub-hosted runners and make the source visible. Open the published repository on GitHub and check that **Code** shows both the Xcode project and `.github/workflows`. [Publish an existing project](https://docs.github.com/en/desktop/adding-and-cloning-repositories/adding-an-existing-project-to-github-using-github-desktop) · [GitHub-hosted runner usage](https://docs.github.com/en/actions/reference/runners/github-hosted-runners)

If Desktop does not offer to create the repository, install [Git for Windows](https://git-scm.com/install/windows). Open PowerShell in the extracted project folder and run `git init -b main`. Then add that folder in GitHub Desktop and continue with the commit and publish steps.

## 2. Run the workflow and download the IPA

1. In your GitHub repository, open **Actions** and select **Build Harmony Monitor for iOS** in the left sidebar.
2. Publishing `main` may have started a run already. Open that run or click **Run workflow**, select `main`, and click the green **Run workflow** button.
3. Open the run and wait for the green check. It selects a preinstalled Xcode on `macos-26`, runs the packet and telemetry XCTest suite on an iPhone simulator, builds the arm64 iPhone app, and uploads the IPA. It needs no Apple secrets in GitHub. [Runner image and Xcode versions](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md)
4. At the bottom of the successful run, under **Artifacts**, click **HarmonyMonitor-iOS-unsigned**. Extract the downloaded artifact ZIP on Windows. Inside it is `HarmonyMonitor-unsigned.ipa`. Keep the IPA intact.
5. Save that IPA on your PC for signing and renewal. GitHub keeps this workflow's artifact for 14 days. You can run the workflow again for another copy. [GitHub artifact downloads](https://docs.github.com/en/actions/how-tos/manage-workflow-runs/download-workflow-artifacts)

## 3. Sign and install using AltServer

AltServer’s direct IPA option works from Windows without installing another app on the phone. Use the current Windows AltServer release. Windows release 1.7.4 includes a fix for sideloaded apps crashing on iOS 26.4. [AltServer release notes](https://faq.altstore.io/release-notes/altserver)

1. On the PC, install desktop **iTunes** and **iCloud for Windows** from the Apple download links in the official AltStore guide. Use its alternate iCloud steps if you already have the Microsoft Store edition. [AltStore’s Windows setup guide](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows)
2. Download **AltServer for Windows** from that guide. Extract the download, run **Setup.exe**, then start **AltServer** as administrator. Its icon appears in the system tray, possibly under the hidden-icons arrow. Allow private-network access if Windows asks and you want Wi-Fi sync.
3. Unlock your iPhone and connect it over USB. Tap **Trust** if iOS asks whether to trust the computer, then enter your iPhone passcode. Check that iTunes detects the iPhone. Sign in to iTunes with your Apple Account if prompted.
4. Hold **Shift** while clicking the AltServer tray icon. Choose **Sideload .ipa…** and select your iPhone. In the file picker choose **HarmonyMonitor-unsigned.ipa**. Use your Apple Account when AltServer prompts for signing, and complete any two-factor prompt. Keep your credentials in the local AltServer/Apple sign-in dialogs. Wait for the installation notification. [Direct IPA sideloading](https://faq.altstore.io/release-notes/altserver#direct-ipa-sideloading)
5. On the iPhone, if you see **Untrusted Developer**, go to **Settings → General → VPN & Device Management**, select the developer entry for your Apple Account and tap **Trust**. Follow any restart or confirmation the phone requests.
6. Open **Settings → Privacy & Security → Developer Mode**. Turn it on, choose **Restart**, then unlock and confirm **Turn On** after the restart. If the setting was hidden previously, check again after the signed app has been installed. [Apple’s Developer Mode guide](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device) · [AltStore’s iOS setup steps](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows#enable-developer-mode-ios-16)
7. Open **Harmony Monitor** on the Home Screen or in App Library. Tap **Connect** and allow Bluetooth access when iOS asks. Select your Harmony 16 from **VESC UART**. If your BMS is awake and appears only under **Show other Bluetooth devices**, tap its name and choose **Connect as Harmony 16**. Use its existing BLE PIN if iOS asks for it.
8. On **Battery**, wait for **Live telemetry** and a moving **Last successful update** timestamp. Compare pack voltage and S1–S7 with a known reference as described in the [hardware check](Hardware-Check.md).

## 4. Renew before seven days

A free Apple Account’s Personal Team provisioning expires seven days after issuance. Apple documents up to three installed development apps per device, up to ten active App IDs and up to three registered devices for a Personal Team. Direct AltServer installation uses one app slot for Harmony Monitor. [Apple developer account limits](https://developer.apple.com/help/account/basics/about-your-developer-account)

For direct installation, reconnect the phone over USB and repeat the **Shift → Sideload .ipa…** step with the same IPA and Apple Account before expiry or after the app stops opening. Use the saved IPA for renewal. Recompiling is needed only when the source changes or you need a fresh copy of the binary.

For in-app refresh, install **AltStore Classic** with **Install AltStore** from the AltServer Windows tray menu, trust it and enable Developer Mode as above. AltStore Classic counts as an additional app slot. Copy the IPA to **Files** on your iPhone, open **AltStore → My Apps → +**, and choose it. Use **Refresh All** before expiry with AltServer running and the iPhone connected over USB or on the same network with iTunes Wi-Fi sync enabled. If AltStore itself expires, reinstall it from AltServer before refreshing Harmony Monitor. [AltStore Classic](https://faq.altstore.io/altstore-classic/your-altstore) · [How AltServer refreshes apps](https://faq.altstore.io/altstore-classic/altserver)

## Build and installation troubleshooting

| What you see | What to check |
| --- | --- |
| No Actions workflow in the sidebar | Confirm `.github/workflows/build-ios.yml` is on your default branch, alongside the Xcode project in the repository root. Enable Actions if GitHub displays an enable prompt. |
| The job stays queued or reports an allowance error | Open the job details for the runner status. For a private repository, check your GitHub Actions allowance. |
| Xcode or simulator error | Open the failed step and copy the first error plus the output of **Select Xcode**. The workflow chooses an available iPhone simulator by UDID. Compare the installed runtimes with the [runner image listing](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md). |
| Signing required in a local Xcode build | Use the workflow’s device build settings `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=` to package a binary for AltServer. Device installation still requires signing. |
| Artifact is missing | Check that **Upload unsigned iPhone build** passed and the run is less than 14 days old. Re-run the workflow after fixing a failing step or to get an expired artifact. |
| AltServer cannot see the iPhone | Use a USB data cable, unlock the phone, approve **Trust**, and confirm the device appears in iTunes. Restart AltServer and iTunes after installing Apple’s Windows components. |
| AltServer cannot authenticate or sign | Check the installed AltServer release, Apple Account sign-in, two-factor prompts and active app/App ID limits. Use the domain and error code from AltServer to find the matching entry in the [official troubleshooting guide](https://faq.altstore.io/altstore-classic/troubleshooting-guide). |
| iOS says the app is untrusted or Developer Mode is off | Confirm the developer trust entry and the Developer Mode restart prompt in steps 5–6. |
| The app worked and now will not launch | Check the profile's seven-day window. Re-sideload the saved IPA using the same account or refresh it with AltStore Classic. |
