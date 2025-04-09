import 'package:flutter/material.dart';

class PlateSearchDialog extends StatefulWidget {
  final void Function(String) onSearch;

  const PlateSearchDialog({
    super.key,
    required this.onSearch,
  });

  @override
  State<PlateSearchDialog> createState() => _PlateSearchDialogState();
}

class _PlateSearchDialogState extends State<PlateSearchDialog> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  bool isValidPlate(String value) {
    return RegExp(r'^\d{4}$').hasMatch(value);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ScaleTransitionDialog(
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: const [
              Icon(Icons.search, color: Colors.blueAccent),
              SizedBox(width: 8),
              Text('번호판 검색', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _searchController,
                builder: (context, value, child) {
                  return Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      value.text,
                      style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    ),
                  );
                },
              ),
              TextField(
                controller: _searchController,
                maxLength: 4,
                focusNode: _focusNode,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '번호판 뒷 4자리 입력',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, child) {
                final isValid = isValidPlate(value.text);
                return FilledButton(
                  onPressed: isValid
                      ? () {
                          widget.onSearch(value.text);
                          Navigator.pop(context);
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    backgroundColor: isValid ? Colors.blueAccent : Colors.grey,
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                    textStyle: const TextStyle(fontSize: 16),
                  ),
                  child: const Text('검색'),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class ScaleTransitionDialog extends StatefulWidget {
  final Widget child;

  const ScaleTransitionDialog({super.key, required this.child});

  @override
  State<ScaleTransitionDialog> createState() => _ScaleTransitionDialogState();
}

class _ScaleTransitionDialogState extends State<ScaleTransitionDialog> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _scaleAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutBack,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: widget.child,
    );
  }
}
