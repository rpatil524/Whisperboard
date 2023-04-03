import Foundation
import ProjectDescription

let version = "1.7.1"

let projectSettings: SettingsDictionary = [
  "GCC_TREAT_WARNINGS_AS_ERRORS": "YES",
  "SWIFT_TREAT_WARNINGS_AS_ERRORS": "YES",
  "CODE_SIGN_STYLE": "Automatic",
  "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
  "MARKETING_VERSION": SettingValue(stringLiteral: version),
  "OTHER_LDFLAGS": "-lc++ $(inherited)",
]

let debugSettings: SettingsDictionary = [
  "OTHER_SWIFT_FLAGS": "-D DEBUG $(inherited) -Xfrontend -warn-long-function-bodies=500 -Xfrontend -warn-long-expression-type-checking=500 -Xfrontend -debug-time-function-bodies -Xfrontend -enable-actor-data-race-checks",
  "OTHER_LDFLAGS": "-Xlinker -interposable $(inherited)",
  "SWIFT_OBJC_BRIDGING_HEADER": "$SRCROOT/App/Sources/Common/Bridging.h",
]

let releaseSettings: SettingsDictionary = [
  "SWIFT_OBJC_BRIDGING_HEADER": "$SRCROOT/App/Sources/Common/Bridging.h",
]

func appTarget() -> Target {
  Target(
    name: "WhisperBoard",
    platform: .iOS,
    product: .app,
    bundleId: "me.igortarasenko.Whisperboard",
    deploymentTarget: .iOS(targetVersion: "16.0", devices: [.iphone, .ipad]),
    infoPlist: .extendingDefault(with: [
      "CFBundleShortVersionString": InfoPlist.Value.string(version),
      "CFBundleURLTypes": [
        [
          "CFBundleTypeRole": "Editor",
          "CFBundleURLName": .string("WhisperBoard"),
          "CFBundleURLSchemes": [
            .string("whisperboard"),
          ],
        ],
      ],
      "UIApplicationSceneManifest": [
        "UIApplicationSupportsMultipleScenes": false,
        "UISceneConfigurations": [
        ],
      ],
      "ITSAppUsesNonExemptEncryption": false,
      "UILaunchScreen": [
        "UILaunchScreen": [:],
      ],
      "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationPortrait",
      ],
      "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight",
      ],
      "NSMicrophoneUsageDescription": "WhisperBoard uses the microphone to record voice and later transcribe it.",
      "UIUserInterfaceStyle": "Dark",
      "UIBackgroundModes": [
        "audio",
        "processing",
      ],
    ]),
    sources: .paths([.relativeToManifest("App/Sources/**")]),
    resources: [
      "App/Resources/Assets.xcassets",
      "App/Resources/ggml-tiny.bin",
    ],
    entitlements: "App/Resources/app.entitlements",
    dependencies: [
      .external(name: "AppDevUtils"),
      .external(name: "Inject"),

      .external(name: "DSWaveformImage"),
      .external(name: "DSWaveformImageViews"),
      .external(name: "DynamicColor"),
      .external(name: "Setting"),
      // .external(name: "Lottie"),
      // .external(name: "LottieUI"),

      .external(name: "AudioKit"),
      .external(name: "whisper"),

      .external(name: "ComposableArchitecture"),
      // .external(name: "ComposablePresentation"),
    ]
  )
}

let project = Project(
  name: "WhisperBoard",
  options: .options(
    disableShowEnvironmentVarsInScriptPhases: true,
    textSettings: .textSettings(
      indentWidth: 2,
      tabWidth: 2
    )
  ),
  settings: .settings(
    base: projectSettings,
    debug: debugSettings,
    release: releaseSettings,
    defaultSettings: .recommended
  ),
  targets: [
    appTarget(),
  ],
  resourceSynthesizers: [
    .files(extensions: ["bin", "json"]),
  ]
)
