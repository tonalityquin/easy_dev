import 'package:flutter/material.dart';

class PlateSearchResults extends StatelessWidget {
  final List<String> results;
  final void Function(String) onSelect;

  const PlateSearchResults({
    super.key,
    required this.results,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '검색 결과',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: results.length,
          separatorBuilder: (_, __) => const Divider(),
          itemBuilder: (context, index) {
            return ListTile(
              leading: const Icon(Icons.directions_car),
              title: Text(results[index]),
              onTap: () => onSelect(results[index]),
            );
          },
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}
