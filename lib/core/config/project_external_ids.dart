enum ProjectExternalIds {
  release(
    projectName: 'parkinworkin',
    gcsBucketName: 'parkinworkin-storage',
    webClientId:
        '87171076301-obvlgmokctsqmskeutmjlccpunftaqg5.apps.googleusercontent.com',
  ),
  develop(
    projectName: 'easyDev',
    gcsBucketName: 'easydev-image',
    webClientId:
        '470236709494-kgk29jdhi8ba25f7ujnqhpn8f22fhf25.apps.googleusercontent.com',
  );

  const ProjectExternalIds({
    required this.projectName,
    required this.gcsBucketName,
    required this.webClientId,
  });

  final String projectName;
  final String gcsBucketName;
  final String webClientId;

  static ProjectExternalIds get current {
    return ProjectExternalIds.develop;
  }

  String publicGcsUrl(String objectName) {
    return 'https://storage.googleapis.com/$gcsBucketName/$objectName';
  }
}
