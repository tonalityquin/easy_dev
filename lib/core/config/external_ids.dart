import 'project_external_ids.dart';

String get kWebClientId {
  return ProjectExternalIds.current.webClientId;
}

String get kBucketName {
  return ProjectExternalIds.current.gcsBucketName;
}

String publicGcsUrl(String objectName) {
  return ProjectExternalIds.current.publicGcsUrl(objectName);
}
