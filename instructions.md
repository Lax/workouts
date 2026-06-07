# Workouts CLI — Dev Workflow

KISS — Simple > clever. No early abstraction.
DRY — Extract repeated patterns.
TDD — Test with code. `bundle exec rspec` green = done signal.
MVC — Fix only what intended. Don't inline tangental fixes.
RUM — Read file fully before editing. Understand imports/style/patterns.
EPF — Error cases before happy path. File missing? Auth fails? Net down?

Verify callers before changing method behavior/return type/exception.
One concern per commit. Body explains WHY, not WHAT.
Propose verify method. Uncertain → offer options.
push → verify → fix → repeat until all pass.

No unsolicited files or actions.
No assumptions — confirm when uncertain.
