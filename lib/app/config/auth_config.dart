class AuthConfig {
  AuthConfig._();

  // static const String webClientId =
  //     '87171076301-obvlgmokctsqmskeutmjlccpunftaqg5.apps.googleusercontent.com';

  // static const String gcsBucketName = 'parkinworkin-storage';

  static const String webClientId =
      '470236709494-6dr8dug3vugaj2nrf3v6qi6tfu10sipd.apps.googleusercontent.com';

  static const String gcsBucketName = 'easydev-image';

  static void validate() {
    final missing = <String>[];

    if (webClientId.trim().isEmpty) {
      missing.add('webClientId');
    }

    if (gcsBucketName.trim().isEmpty) {
      missing.add('gcsBucketName');
    }

    if (missing.isNotEmpty) {
      throw StateError(
        'Missing required auth config: ${missing.join(', ')}.',
      );
    }
  }
}
