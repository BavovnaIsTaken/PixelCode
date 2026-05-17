import 'package:flutter/material.dart';
import 'package:pixelcode/models/agent_listing.dart';
import 'package:pixelcode/services/marketplace_service.dart';

/// Dialog for confirming and completing agent purchases.
class PurchaseDialog extends StatefulWidget {
  final AgentListing listing;
  final int userBalance; // in Grim
  final Function(PurchaseResult) onPurchaseResult;

  const PurchaseDialog({
    required this.listing,
    required this.userBalance,
    required this.onPurchaseResult,
    super.key,
  });

  @override
  State<PurchaseDialog> createState() => _PurchaseDialogState();
}

class _PurchaseDialogState extends State<PurchaseDialog> {
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    final price = widget.listing.priceGrim;
    final platformCommission = (price * 0.20).floor();
    final sellerPayout = price - platformCommission;
    final hasEnoughFunds = widget.userBalance >= price;

    return AlertDialog(
      title: Text('Purchase ${widget.listing.name}?'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Agent: ${widget.listing.name}',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            const Text(
              'Price Breakdown:',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            _buildBreakdownRow('Agent Price', '$price ₲'),
            _buildBreakdownRow(
              'Platform Commission (20%)',
              '$platformCommission ₲',
              isSecondary: true,
            ),
            _buildBreakdownRow(
              'Seller Receives',
              '$sellerPayout ₲',
              isSecondary: true,
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Your Balance:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                Text(
                  '${widget.userBalance} ₲',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: hasEnoughFunds ? Colors.green : Colors.red,
                  ),
                ),
              ],
            ),
            if (!hasEnoughFunds)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    'Insufficient funds (need $price ₲, have ${widget.userBalance} ₲)',
                    style: TextStyle(color: Colors.red.shade900),
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isProcessing ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: hasEnoughFunds && !_isProcessing
              ? () async {
                  setState(() => _isProcessing = true);
                  final nav = Navigator.of(context);
                  // Simulate purchase (would call service in real app)
                  await Future.delayed(const Duration(milliseconds: 500));

                  final result = PurchaseResult(
                    status: PurchaseStatus.success,
                    transactionId: 'tx-${DateTime.now().millisecondsSinceEpoch}',
                  );

                  if (mounted) {
                    widget.onPurchaseResult(result);
                    nav.pop();
                  }
                }
              : null,
          child: _isProcessing
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Confirm Purchase'),
        ),
      ],
    );
  }

  Widget _buildBreakdownRow(String label, String amount,
      {bool isSecondary = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isSecondary ? 13 : 14,
              color: isSecondary ? Colors.grey.shade600 : null,
            ),
          ),
          Text(
            amount,
            style: TextStyle(
              fontWeight: isSecondary ? FontWeight.normal : FontWeight.w600,
              color: isSecondary ? Colors.grey.shade600 : null,
            ),
          ),
        ],
      ),
    );
  }
}
