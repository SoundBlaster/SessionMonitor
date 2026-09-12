# SpecificationCore compatibility snapshot

Source: https://github.com/SoundBlaster/SpecificationCore
Version: 1.0.0, commit `af5b0642282541ae36baffd1328a5dd7c5e61146`. MIT license retained in `SpecificationCore/LICENSE`.
Only Package.swift, Sources, Tests and LICENSE are copied; no local user checkout is modified.

Swift 6.4 (Xcode 27 beta) rejects FirstMatchSpec.Builder.build() with ambiguous
`init(_:includeMetadata:)`: its erased tuple array matches two public overloads.
The only source change adds a private `init(erasedPairs:includeMetadata:)` and
uses its explicit label in Builder.build(). Public initializers and behavior remain.
A SessionMonitor regression test exercises the builder and its fallback.

This local SwiftPM dependency takes precedence over SpecificationKit's remote
SpecificationCore dependency. Replace it with an upstream fixed release after
that release passes the same CLI/app build and tests. Keep this exception visible;
other dependencies remain pinned remote SwiftPM packages.
