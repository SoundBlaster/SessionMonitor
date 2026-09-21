# SpecificationCore dependency provenance

SessionMonitor uses the upstream Swift package from
<https://github.com/SoundBlaster/SpecificationCore>, pinned to release `1.1.0`
(commit `f3ed68ce29db42de54a4ae905a304b61bdc50ce7`). The release carries the
Swift 6.4-compatible typed `FirstMatchSpec.Builder.build()` implementation that
replaces the local compatibility snapshot previously recorded here.

The package is pinned exactly in `Package.swift`; `Package.resolved` records the
resolved commit. The package retains its upstream MIT license. The vendored
`Dependencies/SpecificationCore` copy has been removed so CLI and GUI consumers
resolve the same upstream package identity.
