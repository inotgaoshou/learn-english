# 小鹿学习

iPhone-only SwiftUI app for scanning printed English vocabulary lists, interactive word study, and randomized dictation for children.

## Features

- Scan printed word lists with the iOS document camera.
- Extract English words and phrases offline with Apple's Vision OCR.
- Ignore numbering, Chinese definitions, and common part-of-speech markers such as `n.`.
- Save editable local word lists as JSON in the app documents directory.
- Organize each unit by category, such as KET.
- Open any word in a five-stage learn, read, select, spell, and write flow with curated offline phonics guides.
- Tap syllables and phonics units for pronunciation, then complete shuffled and typed spelling exercises.
- Scan, import, or paste English articles for Chinese translation and American English playback.
- Randomize each dictation round without repeats.
- Speak words with a persistent American or British system voice through `AVSpeechSynthesizer`.
- Check typed answers case-insensitively and tolerate extra spaces in phrases.
- Complete missing phonetics and examples with an offline-first local cache and optional Free Dictionary API lookup.

## Open the App

Open `KidsWordDictation.xcodeproj` in Xcode, select the `KidsWordDictation` scheme, then run on an iPhone with iOS 18 or later. Camera scanning requires a real device.

The bundle identifier is `com.xiaolu.english`, and the display name is `小鹿学习`. Set your Apple development team in Xcode before installing on a device or creating a distribution archive.

## Verify

Run the core tests:

```sh
swift test
```

Build the iOS app without code signing:

```sh
xcodebuild -project KidsWordDictation.xcodeproj \
  -scheme KidsWordDictation \
  -configuration Debug \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  CODE_SIGNING_ALLOWED=NO \
  build
```

## Privacy and release preparation

The home screen includes an offline privacy notice. OCR runs on-device, word metadata and illustrations are bundled with the app, and speech uses Apple's system voices. Optional Apple Translation may download language resources. When bundled data and the local cache are insufficient, optional online completion sends only one normalized English word or short phrase to `api.dictionaryapi.dev`; it never uploads scanned images, articles, entire word lists, or dictation answers. The app has no developer-operated user-data server, online image search, ads, analytics, or tracking.

The public bilingual privacy policy and support pages live in [`docs/`](docs/) and are published at [`https://inotgaoshou.github.io/learn-english/`](https://inotgaoshou.github.io/learn-english/). The current release candidate is version 1.0, build 7.
