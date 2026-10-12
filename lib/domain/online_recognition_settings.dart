class OnlineRecognitionSettings {
  const OnlineRecognitionSettings({
    this.consentAsked = false,
    this.consentGranted = false,
    this.enabled = false,
  });

  final bool consentAsked;
  final bool consentGranted;
  final bool enabled;

  OnlineRecognitionSettings copyWith({
    bool? consentAsked,
    bool? consentGranted,
    bool? enabled,
  }) => OnlineRecognitionSettings(
    consentAsked: consentAsked ?? this.consentAsked,
    consentGranted: consentGranted ?? this.consentGranted,
    enabled: enabled ?? this.enabled,
  );
}
