/// Server/API product "active/inactive" parsing helpers.
///
/// Keep all API-field-name variations and edge-cases in this single file.

bool _hasValue(dynamic v) {
  if (v == null) return false;

  // Many APIs send deletedAt/archivedAt as bool/num.
  if (v is bool) return v;
  if (v is num) return v != 0;

  final s = v.toString().trim().toLowerCase();
  return s.isNotEmpty &&
      s != 'null' &&
      s != '0' &&
      s != 'false' &&
      s != 'undefined';
}

const Set<String> _inactiveStatuses = {
  'inactive',
  'disabled',
  'archived',
  'deleted',
  // Mongolian UI/backends sometimes return localized statuses
  'идэвхгүй',
};

const Set<String> _activeStatuses = {
  'active',
  'enabled',
  'идэвхтэй',
};

/// Resolve whether a product should be considered active based on raw API map.
///
/// Priority (production-safe):
/// 1) deleted/archived flags
/// 2) explicit isActive/active flag
/// 3) status/state strings
/// 4) default true
bool isProductActiveFromApiMap(Map<String, dynamic> p) {
  // 1) Deleted / archived (highest priority)
  final deletedAt = p['deletedAt'] ?? p['deleted_at'];
  if (_hasValue(deletedAt)) return false;

  final archivedAt = p['archivedAt'] ?? p['archived_at'];
  if (_hasValue(archivedAt)) return false;

  final isDeleted = p['isDeleted'] ?? p['deleted'];
  final deletedBool = _boolishToBoolOrNull(isDeleted);
  if (deletedBool == true) return false;

  // 2) Explicit active flag
  final directRaw = p['isActive'] ?? p['active'] ?? p['is_active'];
  final direct = (directRaw is Map) ? directRaw['value'] : directRaw;
  final v = _boolishToBoolOrNull(direct);
  if (v != null) return v;

  // 3) Status/state strings
  final status = (p['status'] ?? p['state'])?.toString().trim().toLowerCase();
  if (status != null && status.isNotEmpty) {
    final normalized = status.replaceAll('_', '').replaceAll(' ', '');

    // IMPORTANT: check inactive first because "inactive" contains "active".
    if (_inactiveStatuses.any((e) => normalized.contains(e))) return false;
    if (_activeStatuses.any((e) => normalized.contains(e))) return true;
  }

  // 4) Default: active
  return true;
}

bool? _boolishToBoolOrNull(dynamic v) {
  if (v == null) return null;
  if (v is bool) return v;
  if (v is num) {
    if (v == 0) return false;
    if (v == 1) return true;
    return null;
  }
  final s = v.toString().trim().toLowerCase();
  if (s.isEmpty) return null;
  if (s == 'false' ||
      s == '0' ||
      s == 'inactive' ||
      s == 'disabled' ||
      s == 'идэвхгүй' ||
      s == 'no' ||
      s == 'off') {
    return false;
  }
  if (s == 'true' ||
      s == '1' ||
      s == 'active' ||
      s == 'enabled' ||
      s == 'идэвхтэй' ||
      s == 'yes' ||
      s == 'on') {
    return true;
  }
  return null;
}

