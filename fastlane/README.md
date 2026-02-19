fastlane documentation
----

# Installation

Make sure you have the latest version of the Xcode command line tools installed:

```sh
xcode-select --install
```

For _fastlane_ installation instructions, see [Installing _fastlane_](https://docs.fastlane.tools/#installing-fastlane)

# Available Actions

## iOS

### ios create_app

```sh
[bundle exec] fastlane ios create_app
```

Create the app on App Store Connect if it doesn't exist

### ios test

```sh
[bundle exec] fastlane ios test
```

Run all tests

### ios screenshots

```sh
[bundle exec] fastlane ios screenshots
```

Capture App Store screenshots on all devices

### ios build

```sh
[bundle exec] fastlane ios build
```

Build the app for release

### ios beta

```sh
[bundle exec] fastlane ios beta
```

Upload a new build to TestFlight

### ios release

```sh
[bundle exec] fastlane ios release
```

Submit a new build to App Store Connect with metadata and screenshots

### ios submit

```sh
[bundle exec] fastlane ios submit
```

Submit the latest build for App Store review

### ios metadata

```sh
[bundle exec] fastlane ios metadata
```

Upload metadata and screenshots only

### ios setup_store

```sh
[bundle exec] fastlane ios setup_store
```

Set age rating (all NONE) and pricing (Free) on App Store Connect

### ios set_privacy

```sh
[bundle exec] fastlane ios set_privacy
```

Set app privacy data usage declarations (requires Apple ID session auth with 2FA)

### ios set_privacy_api

```sh
[bundle exec] fastlane ios set_privacy_api
```

Set app privacy data usage declarations (API key - deprecated endpoint)

### ios submit_api

```sh
[bundle exec] fastlane ios submit_api
```

Submit for review via direct API call

### ios diagnose

```sh
[bundle exec] fastlane ios diagnose
```

Check what is blocking App Store submission

----

This README.md is auto-generated and will be re-generated every time [_fastlane_](https://fastlane.tools) is run.

More information about _fastlane_ can be found on [fastlane.tools](https://fastlane.tools).

The documentation of _fastlane_ can be found on [docs.fastlane.tools](https://docs.fastlane.tools).
