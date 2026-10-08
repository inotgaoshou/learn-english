# 小鹿英语

iPhone-only SwiftUI app for scanning printed English vocabulary lists, interactive word study, and randomized dictation for children.

## Features

- Scan printed word lists with the iOS document camera.
- Extract English words and phrases offline with Apple's Vision OCR.
- Ignore numbering, Chinese definitions, and common part-of-speech markers such as `n.`.
- Save editable local word lists as JSON in the app documents directory.
- Organize each unit by category, such as KET.
- Open any word in an interactive learn, read, and spell flow with curated offline phonics guides.
- Tap syllables and IPA units for pronunciation, then arrange shuffled spelling chunks to check the answer.
- Scan, import, or paste English articles for Chinese translation and American English playback.
- Randomize each dictation round without repeats.
- Speak words with a persistent American or British system voice through `AVSpeechSynthesizer`.
- Check typed answers case-insensitively and tolerate extra spaces in phrases.

## Open the App

Open `KidsWordDictation.xcodeproj` in Xcode, select the `KidsWordDictation` scheme, then run on an iPhone with iOS 18 or later. Camera scanning requires a real device.

The bundle identifier is `com.xiaolu.english`, and the display name is `小鹿英语`. Register this identifier with your Apple developer team before distribution; availability in Apple's developer portal has not yet been verified. Set your Apple development team in Xcode before installing on a device.

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
