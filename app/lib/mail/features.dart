/// The switches of Settings › Features (`OptionalFeaturesToApprove`): whole
/// features a person can turn off. All on to begin with. A feature that is
/// off is not there at all: no sidebar item, phone tile or ⌘K entry, and
/// no work in the background. Nothing is deleted.
class FeatureSettings {
  const FeatureSettings({
    this.newsletters = true,
    this.vault = true,
    this.attachments = true,
    this.inShort = true,
    this.translate = true,
    this.foundDates = true,
  });

  final bool newsletters;
  final bool vault;
  final bool attachments;

  /// "In short" above long conversations.
  final bool inShort;
  final bool translate;

  /// "Add to calendar" for dates found in the text.
  final bool foundDates;

  /// How many are off, for the phone's list of sections.
  int get off => [
    newsletters,
    vault,
    attachments,
    inShort,
    translate,
    foundDates,
  ].where((on) => !on).length;

  FeatureSettings copyWith({
    bool? newsletters,
    bool? vault,
    bool? attachments,
    bool? inShort,
    bool? translate,
    bool? foundDates,
  }) => FeatureSettings(
    newsletters: newsletters ?? this.newsletters,
    vault: vault ?? this.vault,
    attachments: attachments ?? this.attachments,
    inShort: inShort ?? this.inShort,
    translate: translate ?? this.translate,
    foundDates: foundDates ?? this.foundDates,
  );

  @override
  bool operator ==(Object other) =>
      other is FeatureSettings &&
      other.newsletters == newsletters &&
      other.vault == vault &&
      other.attachments == attachments &&
      other.inShort == inShort &&
      other.translate == translate &&
      other.foundDates == foundDates;

  @override
  int get hashCode => Object.hash(
    newsletters,
    vault,
    attachments,
    inShort,
    translate,
    foundDates,
  );
}
