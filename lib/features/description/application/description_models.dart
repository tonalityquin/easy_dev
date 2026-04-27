import 'package:flutter/material.dart';

enum DescriptionSectionLayout {
  portrait,
  landscape,
  textOnly,
}

@immutable
class DescriptionBook {
  const DescriptionBook({
    required this.title,
    required this.subtitle,
    required this.chapters,
  });

  final String title;
  final String subtitle;
  final List<DescriptionChapter> chapters;

  List<DescriptionSection> get sections => [
        for (final chapter in chapters) ...chapter.sections,
      ];

  int get totalSections => sections.length;

  int get landscapeSectionCount => sections
      .where((section) => section.layout == DescriptionSectionLayout.landscape)
      .length;

  int get textOnlySectionCount => sections
      .where((section) => section.layout == DescriptionSectionLayout.textOnly)
      .length;

  int get imageSectionCount => sections
      .where((section) => section.layout != DescriptionSectionLayout.textOnly)
      .length;

  DescriptionChapter? chapterForSection(String sectionId) {
    for (final chapter in chapters) {
      for (final section in chapter.sections) {
        if (section.id == sectionId) {
          return chapter;
        }
      }
    }
    return null;
  }

  DescriptionSection? sectionById(String sectionId) {
    for (final section in sections) {
      if (section.id == sectionId) {
        return section;
      }
    }
    return null;
  }

  int indexOfSection(String sectionId) {
    final resolved = sections.indexWhere((section) => section.id == sectionId);
    return resolved;
  }
}

@immutable
class DescriptionChapter {
  const DescriptionChapter({
    required this.id,
    required this.title,
    required this.summary,
    required this.sections,
  });

  final String id;
  final String title;
  final String summary;
  final List<DescriptionSection> sections;

  bool get hasChildren {
    if (sections.length > 1) {
      return true;
    }
    if (sections.isEmpty) {
      return false;
    }
    return (sections.first.tocTitle ?? '').trim().isNotEmpty;
  }

  String get primarySectionId {
    if (sections.isEmpty) {
      return id;
    }
    return sections.first.id;
  }
}

@immutable
class DescriptionSection {
  const DescriptionSection({
    required this.id,
    required this.title,
    required this.eyebrow,
    required this.summary,
    required this.paragraphs,
    required this.bullets,
    required this.layout,
    required this.media,
    this.tocTitle,
  });

  final String id;
  final String title;
  final String? tocTitle;
  final String eyebrow;
  final String summary;
  final List<String> paragraphs;
  final List<String> bullets;
  final DescriptionSectionLayout layout;
  final DescriptionMediaSpec media;

  bool get hasImage => layout != DescriptionSectionLayout.textOnly;

  String get chipLabel {
    final resolved = eyebrow.trim();
    if (resolved.isNotEmpty) {
      return resolved;
    }
    return title;
  }
}

@immutable
class DescriptionMediaSpec {
  const DescriptionMediaSpec({
    required this.title,
    required this.caption,
    required this.icon,
    this.assetPath,
    this.slotName,
  });

  final String title;
  final String caption;
  final IconData icon;
  final String? assetPath;
  final String? slotName;
}
