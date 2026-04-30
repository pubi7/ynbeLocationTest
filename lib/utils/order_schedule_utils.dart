import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../utils/role_utils.dart';

/// Utilities for order scheduling / calendar-day display rules.
///
/// Goal: keep "which day should this order appear on" logic in one place.
class OrderScheduleUtils {
  /// Date-only (midnight) helper.
  ///
  /// If [useUtc] is true, the returned day is based on UTC calendar day.
  /// This avoids off-by-one issues when backend/worker runs in UTC.
  static DateTime dateOnly(DateTime d, {required bool useUtc}) {
    final v = useUtc ? d.toUtc() : d;
    return DateTime(v.year, v.month, v.day);
  }

  static String yyyyMmDd(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static bool isSameLocalCalendarDay(DateTime a, DateTime selectedDay) {
    return a.year == selectedDay.year &&
        a.month == selectedDay.month &&
        a.day == selectedDay.day;
  }

  /// Role-based scheduling day as an object.
  ///
  /// This is the **single source of truth** for "scheduled delivery day".
  /// UI can format/show it, backend can serialize it.
  ///
  /// Defaults:
  /// - base is computed using **local day** (matches Mongolia/Ulaanbaatar business day)
  /// - agent rule: +1 day, but if base day is Saturday -> +2 days
  static DateTime scheduledDeliveryDayForRole(
    String role, {
    DateTime? now,
    bool useUtcDayBase = false,
  }) {
    final base = dateOnly(now ?? DateTime.now(), useUtc: useUtcDayBase);

    if (isManagerRole(role)) return base;
    if (isAgentRole(role)) {
      final addDays = base.weekday == DateTime.saturday ? 2 : 1;
      return base.add(Duration(days: addDays));
    }
    return base;
  }

  /// The calendar day an order should be shown on the mobile UI.
  ///
  /// Rules:
  /// - If fulfilled (ebarimtRegistered or delivered): show on its orderDate day.
  /// - If backend provides [Order.deliveryDate] (YYYY-MM-DD): prefer it for scheduling.
  /// - If manager: pending orders show on orderDate day.
  /// - If agent/salesagent: pending orders show +1 day (if Saturday then +2 -> Monday).
  static DateTime effectiveOrderCalendarDay(
    Order o, {
    required String role,
  }) {
    final localOrderDay = DateUtils.dateOnly(o.orderDate);

    final isFulfilled =
        o.ebarimtRegistered == true || o.status.toLowerCase() == 'delivered';
    if (isFulfilled) return localOrderDay;

    final dd = o.deliveryDate;
    if (dd != null) return DateUtils.dateOnly(dd);

    if (isManagerRole(role)) return localOrderDay;
    if (isAgentRole(role)) {
      if (localOrderDay.weekday == DateTime.saturday) {
        return localOrderDay.add(const Duration(days: 2));
      }
      return localOrderDay.add(const Duration(days: 1));
    }

    return localOrderDay;
  }

  static List<Order> ordersForCalendarDay(
    List<Order> all,
    DateTime selectedDay,
    String role,
  ) {
    return all
        .where((o) => isSameLocalCalendarDay(
              effectiveOrderCalendarDay(o, role: role),
              selectedDay,
            ))
        .toList();
  }

  /// Compute deliveryDate to send to backend, based on role.
  ///
  /// Default output is `YYYY-MM-DD` (day-only), based on **UTC day base**.
  /// If you want ISO8601 UTC (timestamp), set [format] to [DeliveryDateFormat.isoUtc].
  static String? computeDeliveryDateForWeb(
    String role, {
    DateTime? now,
    DeliveryDateFormat format = DeliveryDateFormat.yyyyMmDd,
    bool useUtcDayBase = false,
  }) {
    final day = scheduledDeliveryDayForRole(
      role,
      now: now,
      useUtcDayBase: useUtcDayBase,
    );

    return switch (format) {
      DeliveryDateFormat.yyyyMmDd => yyyyMmDd(day),
      DeliveryDateFormat.isoUtc => day.toUtc().toIso8601String(),
    };
  }
}

enum DeliveryDateFormat {
  /// `YYYY-MM-DD` (recommended when backend stores date-only)
  yyyyMmDd,

  /// `YYYY-MM-DDTHH:mm:ss.sssZ` (UTC timestamp)
  isoUtc,
}

