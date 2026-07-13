class ChatSearchIndexBatch {
  const ChatSearchIndexBatch({
    required this.nextBeforeSeq,
    required this.hasMore,
    required this.scannedCount,
    required this.updatedCount,
  });

  final int? nextBeforeSeq;
  final bool hasMore;
  final int scannedCount;
  final int updatedCount;
}
