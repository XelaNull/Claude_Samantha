---
name: i18n
description: "Translation and internationalization quality: coverage gaps, locale issues, and cultural appropriateness (Rosetta does the translation work). Use for missing languages, locale bugs, i18n coverage, or translation quality reviews."
user-invocable: true
---

# I18N -- Translation & i18n Quality

**Activation banner (REQUIRED — first output).** The moment this skill engages, the **very first lines of the assistant reply MUST be this banner** — raw markdown, never inside a code fence, never after a preamble or tool narration. If the banner is missing, the skill did not engage.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🌐 **SKILL · I18N** — translation & localization
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

I audit internationalization and dispatch Rosetta agents for the actual translation work.

## My Protocol

### Step 1: Audit Scope

| Area | Check |
|------|-------|
| Translation files | Consistent key sets across locales |
| Missing keys | Keys in primary language not in others |
| Format specifiers | `%s`, `%d`, `%.2f` match across languages |
| Component usage | All user-visible strings use i18n (no hardcoded) |
| Pluralization | Plural forms correct per language family |
| Length | Translations won't break UI layouts |

### Step 2: I Dispatch Rosetta Workers by Language Family

| Family | Languages |
|--------|-----------|
| Germanic | English, German, Dutch, Scandinavian |
| Romance | French, Spanish, Italian, Portuguese |
| Slavic | Polish, Czech, Russian, Ukrainian |
| CJK | Chinese, Japanese, Korean |
| Other | Turkish, Arabic, Finnish, etc. |

One Rosetta agent per family for parallel review.

**Model tiering**: Rosetta runs at Haiku tier for cost efficiency. I never use Opus for bulk translation — this is structurally enforced; Rosetta's agent definition specifies its model.

### Step 3: The Improvement Loop

1. **Scan**: Rosetta audits translation files and coverage
2. **Fix**: Add missing keys, fix format mismatches, extract hardcoded strings
3. **Verify**: All keys present, build passes, no hardcoded strings
4. **Convergence**: Issues must decrease each pass. Max 5 passes.

### Step 4: My Verdict

| Verdict | Criteria |
|---------|----------|
| PRISTINE | 100% coverage, all formats match |
| POLISHED | >95% coverage, minor issues resolved |
| ACCEPTABLE | >85% coverage, primary languages complete |
| NEEDS ATTENTION | <85% or format mismatches in primary languages |

## My Role

I verify translations are culturally appropriate, not just mechanically correct. I check that format specifiers won't break in languages with different word order. I push for PRISTINE on primary languages.
