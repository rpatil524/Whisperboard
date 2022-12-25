<div align="center">
  <a href="https://github.com/Saik0s/Whisperboard">
    <img src="Whisperboard/Resources/Assets.xcassets/AppIcon.appiconset/ios-marketing.png" width="80">
  </a>

  <h3 align="center">Whisperboard</h3>

  <p align="center">
    An iOS app for recording and transcribing audio on the go, based on OpenAI's Whisper model.
  </p>
</div>
<hr />

<div align="center">
<img src=".github/screenshot1.jpg" width="200">
<img src=".github/screenshot2.jpg" width="200">
</div>

## Features

- Easy-to-use voice recording and playback
- Automatic transcription of recorded audio using Whisper from OpenAI
- Custom keyboard with a button to quickly access the app for recording and transcription
- Ability to save and share your recordings

## Future Plans

- Split recorded audio into chunks separated by silence for on the fly transcription
- Allow downloading different models for transcription
- History of transcriptions
- Organize recordings in folders
- Watch app
- Customizable recording settings, including the ability to select microphone

## Installation

1. Clone this repository
2. Run `git submodule update --init --recursive` to clone whisper.cpp submodule
3. Run `make` to download the model
4. Open the project in Xcode

## Contribution

If you have an idea for a new feature or have found a bug, please open an issue or submit a pull request.

## License

This project is licensed under the MIT license.

## Links

- [whisper.cpp](https://github.com/ggerganov/whisper.cpp)
- [OpenAI Whisper](https://github.com/openai/whisper)
