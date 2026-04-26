import 'package:flutter/material.dart';
import 'package:pixelcode/services/marketplace_service.dart';

/// Analytics dashboard for sellers showing stats about their marketplace activity.
class SellerAnalyticsView extends StatelessWidget {
  final SellerStats stats;

  const SellerAnalyticsView({required this.stats, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Analytics'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Marketplace Summary',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 24),
            // Stats grid
            GridView.count(
              crossAxisCount: 3,
              mainAxisSpacing: 16,
              crossAxisSpacing: 16,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStatCard('Total Sales', '${stats.totalSales}', Icons.shopping_cart),
                _buildStatCard('Revenue', '${stats.totalRevenue} ₲', Icons.account_balance_wallet),
                _buildStatCard('Avg Rating', stats.averageRating.toStringAsFixed(1), Icons.star),
              ],
            ),
            const SizedBox(height: 32),
            const Text(
              'Your Performance',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            _buildDetailedStats(),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 32, color: Colors.blue),
            const SizedBox(height: 12),
            Text(
              value,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade600,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailedStats() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            _buildDetailRow('Total Revenue', '${stats.totalRevenue} ₲'),
            const Divider(),
            _buildDetailRow(
              'Average per Agent',
              stats.totalSales > 0
                  ? '${(stats.totalRevenue / stats.totalSales).toStringAsFixed(0)} ₲'
                  : 'N/A',
            ),
            const Divider(),
            _buildDetailRow(
              'Customer Rating',
              stats.averageRating.toStringAsFixed(1),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
