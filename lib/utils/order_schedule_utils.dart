import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../utils/role_utils.dart';

/// Utilities for order scheduling / calendar-day display rules.
///
/// Goal: keep "which day should this order appear on" logic in one place.
class OrderScheduleUtils {
  /// Base calendar day (midnight) helper.
  ///
  /// Use local day by default (matches business day). If you need UTC-based day,
  /// set [useUtcDayBase] to true.
  static DateTime _baseDay({DateTime? now, required bool useUtcDayBase}) {
    final d = now ?? DateTime.now();
    // Normalize: if caller gives UTC DateTime, convert to local when needed (and vice versa).
    final v = useUtcDayBase ? d.toUtc() : d.toLocal();
    return DateTime(v.year, v.month, v.day);
  }

  /// Apply the single role-based scheduling rule to a **date-only** day.
  ///
  /// This is the one public rule that all screens should use.
  static DateTime applyRoleRule(DateTime baseDay, String role) {
    if (isManagerRole(role)) return baseDay;
    if (isAgentRole(role) || isOrderOnlyRole(role)) {
      final addDays = baseDay.weekday == DateTime.saturday ? 2 : 1;
      return baseDay.add(Duration(days: addDays));
    }
    return baseDay;
  }

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

  /// Локал хуанлийн өдөр (борлуулалт/захиалгын «хийсэн өдөр» — UI-д нэг замаар).
  static DateTime localCalendarDay([DateTime? now]) =>
      dateOnly(now ?? DateTime.now(), useUtc: false);

  static String localCalendarDayYyyyMmDd([DateTime? now]) =>
      yyyyMmDd(localCalendarDay(now));

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
  /// - agent / `order` role: +1 day, but if base day is Saturday -> +2 days
  static DateTime scheduledDeliveryDayForRole(
    String role, {
    DateTime? now,
    bool useUtcDayBase = false,
    bool applyRoleOffset = true,
  }) {
    final base = _baseDay(now: now, useUtcDayBase: useUtcDayBase);
    return applyRoleOffset ? applyRoleRule(base, role) : base;
  }

  /// The calendar day an order should be shown on the mobile UI.
  ///
  /// Rules:
  /// - If fulfilled (ebarimtRegistered or delivered): show on its orderDate day.
  /// - If backend provides [Order.deliveryDate] (YYYY-MM-DD): use that day.
  /// - Otherwise: show on [Order.orderDate] day (no extra +1/+2 here).
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

    // No backend deliveryDate: use the order's calendar day (same as Orders
    // screen: deliveryDate ?? orderDate). Mobile createOrder omits deliveryDate;
    // [scheduledDeliveryDayForRole] remains for other UI if needed.
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
    bool applyRoleOffset = true,
  }) {
    final day = scheduledDeliveryDayForRole(
      role,
      now: now,
      useUtcDayBase: useUtcDayBase,
      // Keep deliveryDate consistent across Mobile/Web by using the same role rules.
      // If backend should NOT store the role-based offset, pass applyRoleOffset: false.
      applyRoleOffset: applyRoleOffset,
    );

    return switch (format) {
      DeliveryDateFormat.yyyyMmDd => yyyyMmDd(day),
      DeliveryDateFormat.isoUtc => day.toUtc().toIso8601String(),
    };
  }

  /// Role-based delivery day string (e.g. web or flows that must send a day).
  ///
  /// Mobile sales entry does **not** send `deliveryDate` on create (null); the
  /// backend order day is the actual order timestamp. Use this only where a
  /// stored delivery calendar day is still required.
  static String deliveryDateForBackend({
    required String role,
    DateTime? now,
  }) {
    return computeDeliveryDateForWeb(
          role,
          now: now,
          format: DeliveryDateFormat.yyyyMmDd,
          useUtcDayBase: false,
          applyRoleOffset: true,
        ) ??
        yyyyMmDd(_baseDay(now: now, useUtcDayBase: false));
  }
}

enum DeliveryDateFormat {
  /// `YYYY-MM-DD` (recommended when backend stores date-only)
  yyyyMmDd,

  /// `YYYY-MM-DDTHH:mm:ss.sssZ` (UTC timestamp)
  isoUtc,
}

