import 'package:flutter/material.dart';
import 'package:pixelcode/models/agent_listing.dart';

/// View showing all listings created by the current seller.
class SellerListingsView extends StatelessWidget {
  final List<AgentListing> listings;
  final Function(String listingId) onSelectListing;

  const SellerListingsView({
    required this.listings,
    required this.onSelectListing,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Listings'),
      ),
      body: listings.isEmpty
          ? _buildEmptyState(context)
          : _buildListings(),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.storefront_outlined, size: 64, color: Colors.grey),
          const SizedBox(height: 16),
          const Text(
            'No listings yet',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: () {
              // Create listing action
            },
            child: const Text('Create Listing'),
          ),
        ],
      ),
    );
  }

  Widget _buildListings() {
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: listings.length,
      itemBuilder: (context, index) {
        final listing = listings[index];
        return _buildListingCard(listing);
      },
    );
  }

  Widget _buildListingCard(AgentListing listing) {
    return GestureDetector(
      onTap: () => onSelectListing(listing.listingId),
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${listing.priceGrim} ₲',
                          style: TextStyle(
                            fontSize: 14,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.shopping_cart_outlined,
                              size: 16, color: Colors.grey),
                          const SizedBox(width: 4),
                          Text('${listing.purchaseCount}'),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.star, size: 16, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            listing.averageRating.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
