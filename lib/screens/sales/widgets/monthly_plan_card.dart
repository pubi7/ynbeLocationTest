import 'package:flutter/material.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';

import '../../../providers/sales_provider.dart';

class MonthlyPlanCard extends StatelessWidget {
  const MonthlyPlanCard({
    super.key,
    required this.monthlyTarget,
    required this.isLoadingMonthlyTarget,
  });

  final double monthlyTarget;
  final bool isLoadingMonthlyTarget;

  @override
  Widget build(BuildContext context) {
    return Consumer<SalesProvider>(
      builder: (context, salesProvider, _) {
        final now = DateTime.now();
        final monthStart = DateTime(now.year, now.month, 1);
        final monthEnd = DateTime(now.year, now.month + 1, 1);
        final monthlySales =
            salesProvider.getTotalSalesForRange(monthStart, monthEnd);
        final monthlyProgress =
            monthlyTarget <= 0 ? 0.0 : (monthlySales / monthlyTarget).clamp(0.0, 1.0);
        final monthlyProgressPercent = (monthlyProgress * 100).toStringAsFixed(1);

        return Container(
          margin: const EdgeInsets.only(bottom: 20),
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.calendar_month_rounded,
                      color: Color(0xFF6366F1), size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${intl.DateFormat('yyyy-MMMM', 'mn_MN').format(now)} сарын төлөвлөгөө',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isLoadingMonthlyTarget)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      '${monthlyTarget.toStringAsFixed(0)} ₮',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF6366F1),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Одоогийн борлуулалт',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${monthlySales.toStringAsFixed(0)} ₮',
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF10B981),
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text(
                        'Гүйцэтгэл',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$monthlyProgressPercent%',
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: monthlyProgress >= 1.0
                              ? const Color(0xFF10B981)
                              : monthlyProgress >= 0.7
                                  ? const Color(0xFFF59E0B)
                                  : const Color(0xFFEF4444),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: monthlyProgress,
                  minHeight: 12,
                  backgroundColor: Colors.grey.shade200,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    monthlyProgress >= 1.0
                        ? const Color(0xFF10B981)
                        : monthlyProgress >= 0.7
                            ? const Color(0xFFF59E0B)
                            : const Color(0xFFEF4444),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

