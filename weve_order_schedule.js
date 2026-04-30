/**
 * Weve order scheduling helper (single-file source of truth).
 *
 * Purpose:
 * - Decide which "delivery day" (scheduled day) an order should be sent with.
 * - Keep the logic consistent across mobile/backend.
 *
 * Business rules (current):
 * - Manager/Admin: today
 * - SalesAgent/Agent: +1 day, but if today is Saturday -> +2 days (Monday)
 *
 * Notes:
 * - We compute using LOCAL day base (Ulaanbaatar business day) because mobile users
 *   operate in Mongolia timezone and "today" should match what they see.
 * - Output defaults to YYYY-MM-DD (ISO date only). This passes `isISO8601()` on backend.
 */

function _safeLower(s) {
  return String(s || "").trim().toLowerCase();
}

function isAgentRole(role) {
  const r = _safeLower(role);
  return (
    r === "agent" ||
    r === "sales" ||
    r === "salesagent" ||
    r === "sales_agent" ||
    r === "borluulagch" ||
    r === "seller" ||
    r.includes("agent") ||
    r.includes("sales") ||
    r.includes("seller") ||
    r.includes("борлуул") ||
    r.includes("агент")
  );
}

function isManagerRole(role) {
  const r = _safeLower(role);
  return (
    r === "manager" ||
    r === "admin" ||
    r === "boss" ||
    r.includes("manager") ||
    r.includes("admin") ||
    r.includes("boss") ||
    r.includes("менежер")
  );
}

function dateOnlyLocal(d) {
  const v = d instanceof Date ? d : new Date(d);
  return new Date(v.getFullYear(), v.getMonth(), v.getDate());
}

function yyyyMmDd(d) {
  const v = d instanceof Date ? d : new Date(d);
  const y = String(v.getFullYear()).padStart(4, "0");
  const m = String(v.getMonth() + 1).padStart(2, "0");
  const day = String(v.getDate()).padStart(2, "0");
  return `${y}-${m}-${day}`;
}

function computeDeliveryDateForWeb(role, now = new Date()) {
  const base = dateOnlyLocal(now);
  if (isManagerRole(role)) return yyyyMmDd(base);
  if (isAgentRole(role)) {
    // JS Date: Sunday=0, Saturday=6
    const isSaturday = base.getDay() === 6;
    const addDays = isSaturday ? 2 : 1;
    const scheduled = new Date(base);
    scheduled.setDate(scheduled.getDate() + addDays);
    return yyyyMmDd(scheduled);
  }
  return null;
}

function decodeJwtPayload(authHeader) {
  // Accept: "Bearer <token>"
  if (!authHeader || typeof authHeader !== "string") return null;
  const parts = authHeader.split(" ");
  const token = parts.length === 2 ? parts[1] : parts[0];
  const seg = token.split(".");
  if (seg.length < 2) return null;
  try {
    const payloadJson = Buffer.from(seg[1], "base64").toString("utf8");
    return JSON.parse(payloadJson);
  } catch (_) {
    return null;
  }
}

function getRoleFromRequest(req) {
  const authHeader = req?.headers?.authorization;
  const payload = decodeJwtPayload(authHeader);
  const role =
    payload?.role ||
    payload?.roleName ||
    payload?.userRole ||
    payload?.user_role ||
    "";
  return String(role || "");
}

module.exports = {
  computeDeliveryDateForWeb,
  getRoleFromRequest,
  isAgentRole,
  isManagerRole,
  yyyyMmDd,
};

