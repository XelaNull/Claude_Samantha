#!/usr/bin/env bash
# coord-address-filter.sh — PROJECT-scoped wake helpers for STAR monitors (PROTOCOL 1.3.0+)
#
# Shared by coord-monitor.sh and tests. Source this file; do not execute standalone.
#
# Intent (human, 2026-08-09): On a shared hub, Sectorwars implementers should see
# Sectorwars traffic (including sibling seats) but NOT aiclient traffic. Only the
# orchestrator is aware of every project.
#
# Rules:
#   - Derive project from --project, else roster `project:`, else identity
#     `impl-<project>` / `impl-<project>-<lane>` → first segment after impl-.
#   - Spoke hub-outbox filter: emit iff TO is ALL, this seat, or another identity
#     in the SAME project. Hub self-nudge (→ orchestrator) is silent for spokes.
#   - Spoke watch set (coord-monitor): orchestrator.md + same-project impl-*.md
#     (excluding self). Orchestrator watches everything (unchanged).

# UTF-8 mailbox delimiters (explicit octets).
_COORD_ARROW=$'\xe2\x86\x92'    # →
_COORD_EMDASH=$'\xe2\x80\x94'   # —

# protocol_project_of_identity <identity>
# Prints project key, or empty for orchestrator / pending-* / unknown.
protocol_project_of_identity() {
  local id="$1"
  case "$id" in
    ""|orchestrator|ALL) printf '' ; return 0 ;;
    pending-*) printf '' ; return 0 ;;
    impl-*)
      local rest="${id#impl-}"
      printf '%s' "${rest%%-*}"
      return 0
      ;;
    *)
      # Non-impl spoke names: whole identity is the project key unless overridden.
      printf '%s' "$id"
      return 0
      ;;
  esac
}

# protocol_read_project_field <presence-file>
# Prints value of `project:` from presence header if present.
protocol_read_project_field() {
  local f="$1"
  [ -f "$f" ] || return 0
  # Prefer a line that looks like roster field, not prose.
  awk '/^project:[[:space:]]*/ { sub(/^project:[[:space:]]*/, ""); gsub(/[[:space:]]+#.*$/, ""); gsub(/[[:space:]]+$/, ""); print; exit }' "$f" 2>/dev/null
}

# protocol_resolve_project <identity> <explicit-project> <presence-or-mailbox-file> [coord-dir]
protocol_resolve_project() {
  local id="$1" explicit="$2" presence="$3" coord="${4:-}" from_file derived from_side
  if [ -n "$explicit" ]; then
    printf '%s' "$explicit"
    return 0
  fi
  if [ -n "$coord" ] && [ -f "$coord/.presence/$id" ]; then
    from_side=$(awk -F= '$1 == "project" { print $2; exit }' "$coord/.presence/$id")
    if [ -n "$from_side" ]; then
      printf '%s' "$from_side"
      return 0
    fi
  fi
  from_file=$(protocol_read_project_field "$presence")
  if [ -n "$from_file" ]; then
    printf '%s' "$from_file"
    return 0
  fi
  derived=$(protocol_project_of_identity "$id")
  printf '%s' "$derived"
}

# protocol_same_project <project> <other-identity>
# Exit 0 if other-identity belongs to project (or other is ALL — caller handles ALL).
protocol_same_project() {
  local project="$1" other="$2" op
  [ -n "$project" ] || return 1
  [ -n "$other" ] || return 1
  [ "$other" = "ALL" ] && return 0
  [ "$other" = "orchestrator" ] && return 1
  op=$(protocol_project_of_identity "$other")
  [ -n "$op" ] && [ "$op" = "$project" ]
}

# Extract TO from a ### header line; prints TO or empty.
protocol_header_to() {
  local line="$1"
  local arrow="$_COORD_ARROW" em="$_COORD_EMDASH"
  printf '%s' "$line" | awk -v arrow="$arrow" -v em="$em" '
    BEGIN { asep = " " arrow " "; esep = " " em " " }
    {
      p = index($0, asep)
      if (p > 0) {
        rest = substr($0, p + length(asep))
        q = index(rest, esep)
        if (q > 0) print substr(rest, 1, q - 1)
      }
    }'
}

# spoke_filter_delta <ident> <project> <chunk>
# Emit messages on hub outbox relevant to this spoke's project.
# Exit 0 if any output, 1 if none.
spoke_filter_delta() {
  local ident="$1"
  local project="$2"
  local chunk="$3"
  local filtered
  [ -n "$ident" ] || return 1
  [ -n "$chunk" ] || return 1
  # No project resolved → fall back to strict self|ALL only (safe default).
  filtered=$(printf '%s' "$chunk" | awk -v ident="$ident" -v project="$project" \
    -v arrow="$_COORD_ARROW" -v em="$_COORD_EMDASH" '
    function project_of(id,   rest) {
      if (id == "" || id == "orchestrator" || id == "ALL") return ""
      if (index(id, "pending-") == 1) return ""
      if (index(id, "impl-") == 1) {
        rest = substr(id, 6)
        if (match(rest, /-/)) return substr(rest, 1, RSTART - 1)
        return rest
      }
      return id
    }
    function relevant(to,   op) {
      if (to == "ALL") return 1
      if (to == ident) return 1
      if (project == "") return 0
      if (to == "orchestrator") return 0
      op = project_of(to)
      return (op != "" && op == project) ? 1 : 0
    }
    BEGIN {
      asep = " " arrow " "
      esep = " " em " "
      keep = 0
      buf = ""
    }
    index($0, "### ") == 1 {
      if (keep) printf "%s", buf
      buf = $0 "\n"
      to = ""
      p = index($0, asep)
      if (p > 0) {
        rest = substr($0, p + length(asep))
        q = index(rest, esep)
        if (q > 0) to = substr(rest, 1, q - 1)
      }
      keep = relevant(to)
      if (!keep) buf = ""
      next
    }
    {
      if (keep) buf = buf $0 "\n"
    }
    END {
      if (keep) printf "%s", buf
    }
  ')
  [ -n "$filtered" ] || return 1
  printf '%s' "$filtered"
  return 0
}

# Backward-compat name used in early 1.2.1 tests — requires project as 2nd arg now.
# Prefer spoke_filter_delta.
