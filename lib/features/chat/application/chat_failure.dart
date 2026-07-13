import 'package:cloud_firestore/cloud_firestore.dart';

enum ChatFailureKind {
  invalidInput,
  network,
  timeout,
  indexRequired,
  resourceExhausted,
  cancelled,
  unknown,
}

enum ChatOperation {
  bind,
  watchChannel,
  watchMessages,
  loadOlder,
  sendMessage,
  pinNotice,
  clearPinnedNotice,
  searchMessages,
  indexSearchHistory,
  watchInbox,
}

class ChatFailure {
  const ChatFailure({
    required this.kind,
    required this.operation,
    required this.userMessage,
    required this.retryable,
    this.cause,
    this.stackTrace,
  });

  final ChatFailureKind kind;
  final ChatOperation operation;
  final String userMessage;
  final bool retryable;
  final Object? cause;
  final StackTrace? stackTrace;

  bool get isIndexRequired => kind == ChatFailureKind.indexRequired;

  String get signature {
    final causeText = cause?.toString() ?? '';
    return '${kind.name}|${operation.name}|$causeText';
  }

  static ChatFailure invalid({
    required ChatOperation operation,
    required String message,
  }) {
    return ChatFailure(
      kind: ChatFailureKind.invalidInput,
      operation: operation,
      userMessage: message,
      retryable: false,
    );
  }
}

ChatFailure classifyChatFailure({
  required ChatOperation operation,
  required Object error,
  StackTrace? stackTrace,
}) {
  if (error is FirebaseException) {
    final code = error.code.toLowerCase();
    final message = error.message?.toLowerCase() ?? '';
    final combined = '$code $message';

    if (code == 'failed-precondition' &&
        (combined.contains('index') ||
            combined.contains('create_composite') ||
            combined.contains('requires an index'))) {
      return ChatFailure(
        kind: ChatFailureKind.indexRequired,
        operation: operation,
        userMessage: 'Firestore 복합 인덱스가 필요합니다.',
        retryable: false,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (code == 'unavailable' ||
        code == 'network-request-failed' ||
        code == 'data-loss') {
      return ChatFailure(
        kind: ChatFailureKind.network,
        operation: operation,
        userMessage: '네트워크 연결을 확인해 주세요.',
        retryable: true,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (code == 'deadline-exceeded') {
      return ChatFailure(
        kind: ChatFailureKind.timeout,
        operation: operation,
        userMessage: '요청 시간이 초과되었습니다.',
        retryable: true,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (code == 'resource-exhausted') {
      return ChatFailure(
        kind: ChatFailureKind.resourceExhausted,
        operation: operation,
        userMessage: '요청이 많습니다. 잠시 후 다시 시도해 주세요.',
        retryable: true,
        cause: error,
        stackTrace: stackTrace,
      );
    }

    if (code == 'cancelled') {
      return ChatFailure(
        kind: ChatFailureKind.cancelled,
        operation: operation,
        userMessage: '요청이 취소되었습니다.',
        retryable: true,
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  return ChatFailure(
    kind: ChatFailureKind.unknown,
    operation: operation,
    userMessage: _defaultMessageFor(operation),
    retryable: true,
    cause: error,
    stackTrace: stackTrace,
  );
}

String _defaultMessageFor(ChatOperation operation) {
  switch (operation) {
    case ChatOperation.bind:
    case ChatOperation.watchChannel:
    case ChatOperation.watchMessages:
      return '채팅을 불러오지 못했습니다.';
    case ChatOperation.loadOlder:
      return '이전 메시지를 불러오지 못했습니다.';
    case ChatOperation.sendMessage:
      return '메시지를 보내지 못했습니다.';
    case ChatOperation.pinNotice:
      return '공지를 고정하지 못했습니다.';
    case ChatOperation.clearPinnedNotice:
      return '공지 고정을 해제하지 못했습니다.';
    case ChatOperation.searchMessages:
      return '전체 이력 검색을 완료하지 못했습니다.';
    case ChatOperation.indexSearchHistory:
      return '기존 메시지 검색 색인을 생성하지 못했습니다.';
    case ChatOperation.watchInbox:
      return '채팅 알림 상태를 불러오지 못했습니다.';
  }
}
