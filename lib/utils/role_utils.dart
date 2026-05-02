/// Role helpers shared across screens.
///
/// NOTE: Backend role string could be inconsistent (e.g. "agent" vs a typo "egant").
library role_utils;

bool isAgentRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  // Common variants from backend / display strings
  return r == 'agent' ||
      r == 'egant' ||
      r == 'sales' ||
      r == 'salesagent' ||
      r == 'sales_agent' ||
      r == 'borluulagch' ||
      r == 'borluulagch_role' ||
      r == 'seller' ||
      r.contains('agent') ||
      r.contains('sales') ||
      r.contains('seller') ||
      r.contains('борлуул') ||
      r.contains('агент');
}

bool isManagerRole(String? role) {
  final r = (role ?? '').trim().toLowerCase();
  return r == 'manager' ||
      r == 'meneger' ||
      r == 'boss' ||
      r == 'admin' ||
      r.contains('manager') ||
      r.contains('boss') ||
      r.contains('admin') ||
      r.contains('менежер');
}

/// Зөвхөн захиалга (`order`) — ачааны өдрийн тооцоонд агенттой ижил (+1 өдөр).
bool isOrderOnlyRole(String? role) {
  return (role ?? '').trim().toLowerCase() == 'order';
}

