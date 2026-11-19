# MG EV for iOS

An iPhone companion for MG electric cars sold in India: battery, range, charging, locks, doors, tyres and remote
controls from your own MG i-SMART owner account. Trip planning, live alerts, home-charging cost, smart pre-cool, tyre
watch and Exicom charger control follow in later milestones (see the plan document).

There is no server: the app talks to MG's i-SMART servers with your own login, and your login stays in the iPhone
Keychain.

## Status: milestone 1

| Part | State |
| --- | --- |
| MG i-SMART client (`MGKit`): sign-in, vehicle list, status, charging, lock/unlock/AC/find, PIN check | Done, 31 tests pass, byte-exact with the original Python client |
| Car models and battery profile (`EVCore`): model detection, learned battery size, flat-road range | Done, 13 tests pass |
| Weather (`OpenMeteo`): current air temperature and sunshine from Open-Meteo, no API key, cached 15 min per ~1 km | Done, 6 tests pass |
| Hot-day AC suggestion (`EVCore/Precool.swift`): estimated cabin temperature, Volta's pre-cool rules | Done, 9 tests pass |
| App: outside and cabin temperature card, "Turn AC on?" card on hot days, settings for it | Written, not yet built in Xcode |
| App: sign-in, dashboard (battery, range, charging, controls, doors/windows, 12 V, tyres), control PIN, settings | Written, not yet built in Xcode |

## Build and run on your iPhone

You need a Mac with Xcode 15 or newer, and your iPhone with a USB cable.

1. Copy this `mg-ev-ios` folder to your Mac.
2. Install XcodeGen, which turns `project.yml` into an Xcode project:
   ```
   brew install xcodegen
   ```
   (No Homebrew? Get it from https://brew.sh first.)
3. In Terminal, in the `mg-ev-ios` folder:
   ```
   xcodegen
   open MGEV.xcodeproj
   ```
   Xcode fetches the `swift-crypto` package on first open; wait for it to finish.
4. In Xcode, select the **MGEV** target, then **Signing & Capabilities**:
   - Team: your Apple ID (add it under Xcode > Settings > Accounts if it isn't listed).
   - Bundle Identifier: change `com.example.mgev.app` to something unique, such as `com.yourname.mgev`.
5. Plug in your iPhone, pick it as the run destination at the top of Xcode, and press Run (Cmd-R).
   - First time only: on the iPhone, turn on **Settings > Privacy & Security > Developer Mode** and restart, then
     trust your developer certificate under **Settings > General > VPN & Device Management**.
6. Sign in with your i-SMART mobile number and password.

With a free Apple ID the app stops opening after 7 days; press Run in Xcode again to renew it. A paid Apple Developer
account ($99 a year) makes it last a year and allows TestFlight.

### Things to know

- Signing in here signs the official MG app out (MG allows one session at a time), and the reverse. The app limits
  itself to 3 logins an hour so the two apps don't keep kicking each other out.
- If multi-factor login is on for your MG account, sign-in fails. Turn it off in the MG app's security settings.
- Commands (lock, unlock, AC, find) ask for Face ID, and the first time for your 4-digit MG control PIN. Only a hash
  of the PIN is stored.

## Run the logic tests

The packages build and test on their own, without a phone:

```
cd Packages/MGEVKit
swift test
```

## Layout

```
project.yml                 XcodeGen spec for the app
App/Sources/App             app entry and AppModel (state, sign-in, refresh, commands)
App/Sources/Data            Keychain storage and saved car data
App/Sources/Features        Sign-in, Dashboard, Settings screens
Packages/MGEVKit            Swift package: MGKit (MG client) and EVCore (car models, battery)
```

## Licence

Apache 2.0. Parts are ported from [Volta](https://github.com/irshadm/volta-android) and
[mg-ismart-india-client](https://github.com/john-lazarus/mg-ismart-india-client); see [NOTICE.md](NOTICE.md).
