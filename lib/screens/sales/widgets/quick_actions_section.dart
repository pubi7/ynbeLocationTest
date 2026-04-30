import 'package:flutter/material.dart';

import 'circular_action_button.dart';

class QuickActionsSection extends StatelessWidget {
  const QuickActionsSection({
    super.key,
    required this.onTakeOrder,
  });

  final VoidCallback onTakeOrder;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Quick Actions',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1E293B),
              ),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            CircularActionButton(
              title: 'Take Order',
              icon: Icons.shopping_cart_rounded,
              color: const Color(0xFF3B82F6),
              onTap: onTakeOrder,
            ),
          ],
        ),
      ],
    );
  }
}

