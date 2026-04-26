import 'package:flutter/material.dart';

/// Filter controls for marketplace listings (search, role dropdown, rating slider).
class ListingFilterBar extends StatefulWidget {
  final Function(String) onRoleFilterChanged;
  final Function(double) onMinRatingChanged;
  final Function(String) onSearchChanged;
  final String? selectedRole;
  final double minRating;
  final String searchQuery;

  const ListingFilterBar({
    required this.onRoleFilterChanged,
    required this.onMinRatingChanged,
    required this.onSearchChanged,
    this.selectedRole,
    required this.minRating,
    required this.searchQuery,
    super.key,
  });

  @override
  State<ListingFilterBar> createState() => _ListingFilterBarState();
}

class _ListingFilterBarState extends State<ListingFilterBar> {
  late TextEditingController _searchController;
  bool _showFilterPanel = false;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController(text: widget.searchQuery);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  final List<String> _roles = ['coder', 'tester', 'devops', 'architect'];

  void _toggleFilterPanel() {
    setState(() {
      _showFilterPanel = !_showFilterPanel;
    });
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: widget.onSearchChanged,
                    decoration: InputDecoration(
                      hintText: 'Search agents...',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Filter button
                IconButton(
                  icon: const Icon(Icons.tune),
                  onPressed: _toggleFilterPanel,
                ),
              ],
            ),
          ),
          // Filter panel
          if (_showFilterPanel)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Role filter
                  const Text('Role', style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: _roles
                        .map((role) => FilterChip(
                              key: ValueKey('role-$role'),
                              label: Text(role),
                              selected: widget.selectedRole == role,
                              onSelected: (selected) {
                                if (selected) {
                                  widget.onRoleFilterChanged(role);
                                  setState(() {});
                                }
                              },
                            ))
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  // Rating filter
                  const Text('Minimum Rating',
                      style: TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Slider(
                          value: widget.minRating,
                          min: 1.0,
                          max: 5.0,
                          divisions: 4,
                          label: '${widget.minRating.toStringAsFixed(1)} ★',
                          onChanged: widget.onMinRatingChanged,
                        ),
                      ),
                      Text('${widget.minRating.toStringAsFixed(1)} ★'),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
