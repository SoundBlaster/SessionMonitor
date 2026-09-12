# Third-party dependencies

Runtime/build package versions are recorded in Package.resolved and
Apps/MonitorMac/Package.resolved (copied into the generated Xcode workspace).
The GUI pins SpecificationKit 4.0.0 in project.yml.

| Dependency | Version | License / source |
| --- | --- | --- |
| SpecificationCore | 1.0.0 + local compatibility patch | [MIT](Dependencies/SpecificationCore/LICENSE), [provenance](Dependencies/README.md) |
| SpecificationKit | 4.0.0 | [MIT](https://github.com/SoundBlaster/SpecificationKit/blob/4.0.0/LICENSE) |
| GRDB.swift | 7.11.1 | [MIT](https://github.com/groue/GRDB.swift/blob/v7.11.1/LICENSE) |
| swift-argument-parser | 1.8.2 | [Apache 2.0 with Runtime Library Exception](https://github.com/apple/swift-argument-parser/blob/1.8.2/LICENSE.txt) |
| swift-syntax | 510.0.3, macros build dependency | [Apache 2.0 with Runtime Library Exception](https://github.com/swiftlang/swift-syntax/blob/510.0.3/LICENSE.txt) |

Developer tooling is not bundled into the app: [XcodeGen](https://github.com/yonaskolb/XcodeGen),
[SwiftLint](https://github.com/realm/SwiftLint), [FSD](https://github.com/SoundBlaster/FSD)
and [XcodeBuildMCP](https://github.com/getsentry/XcodeBuildMCP) are MIT licensed.
Apple SDK/frameworks are supplied by Xcode/macOS under their respective terms.

NavigationSplitViewKit was inspected as a behavior reference; its source is not
included in the app. The locally copied SpecificationCore retains its complete
license. Distribution packaging must retain the notices required by all bundled
components; distribution/notarization has not been implemented in this slice.
