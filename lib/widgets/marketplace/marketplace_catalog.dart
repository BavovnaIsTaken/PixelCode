import 'package:flutter/material.dart';
import 'package:pixelcode/models/agent_listing.dart';
import 'listing_tile.dart';
import 'listing_filter_bar.dart';

/// Main marketplace catalog view showing a grid of agent listings.
class MarketplaceCatalog extends StatefulWidget {
  final List<AgentListing> listings;
  final Function(String listingId) onSelectListing;

  const MarketplaceCatalog({
    required this.listings,
    required this.onSelectListing,
    super.key,
  });

  @override
  State<MarketplaceCatalog> createState() => _MarketplaceCatalogState();
}

class _MarketplaceCatalogState extends State<MarketplaceCatalog> {
  String? _roleFilter;
  double _minRating = 1.0;
  String _searchQuery = '';

  List<AgentListing> get _filteredListings {
    var result = widget.listings;

    if (_roleFilter != null) {
      result = result.where((l) => l.role == _roleFilter).toList();
    }

    if (_minRating > 1.0) {
      result = result.where((l) => l.averageRating >= _minRating).toList();
    }

    if (_searchQuery.isNotEmpty) {
      final query = _searchQuery.toLowerCase();
      result = result
          .where((l) =>
              l.name.toLowerCase().contains(query) ||
              l.description.toLowerCase().contains(query))
          .toList();
    }

    return result;
  }

  void _clearFilters() {
    setState(() {
      _roleFilter = null;
      _minRating = 1.0;
      _searchQuery = '';
    });
  }

  void _clearRoleFilter() {
    setState(() {
      _roleFilter = null;
    });
  }

  void _setRoleFilter(String role) {
    setState(() {
      _roleFilter = role;
    });
  }

  void _setMinRating(double rating) {
    setState(() {
      _minRating = rating;
    });
  }

  void _setSearchQuery(String query) {
    setState(() {
      _searchQuery = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    final filteredListings = _filteredListings;
    final isEmpty = filteredListings.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Marketplace'),
        elevation: 0,
      ),
      body: Column(
        children: [
          // Filter bar
          ListingFilterBar(
            onRoleFilterChanged: _setRoleFilter,
            onMinRatingChanged: _setMinRating,
            onSearchChanged: _setSearchQuery,
            selectedRole: _roleFilter,
            minRating: _minRating,
            searchQuery: _searchQuery,
          ),
          // Role filter chip
          if (_roleFilter != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Chip(
                label: Text(_roleFilter!),
                onDeleted: _clearRoleFilter,
                deleteIcon: const Icon(Icons.close),
              ),
            ),
          // Grid or empty state
          Expanded(
            child: isEmpty
                ? _buildEmptyState()
                : _buildGrid(filteredListings),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.shopping_cart_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No custom agents available yet',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              // Refresh action
              setState(() {});
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Refresh'),
          ),
        ],
      ),
    );
  }

  Widget _buildGrid(List<AgentListing> listings) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 16,
        crossAxisSpacing: 16,
        childAspectRatio: 0.75,
      ),
      itemCount: listings.length,
      itemBuilder: (context, index) {
        final listing = listings[index];
        return ListingTile(
          listing: listing,
          onTap: () => widget.onSelectListing(listing.listingId),
        );
      },
    );
  }
}
