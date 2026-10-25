/// The app's version, as in `pubspec.yaml` (a test keeps them in step).
const appVersion = '0.1.0';

/// The build number a release is made with
/// (`--dart-define=PIUMA_BUILD=396`), 0 when none was given.
const appBuild = int.fromEnvironment('PIUMA_BUILD');

/// The version as Settings shows it: "0.1.0 (396)" for a numbered build.
const appVersionShown = appBuild > 0 ? '$appVersion ($appBuild)' : appVersion;
