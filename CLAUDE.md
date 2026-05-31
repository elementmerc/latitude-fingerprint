# Engineering Baseline — Project-Agnostic Operating Rules

**This is the shared engineering constitution. It is project-agnostic: no
product names, no infrastructure identifiers, no repository paths. Every
project layers its own specifics on top of this file; nothing here is
allowed to depend on a particular project.**

How to read this: a project's own `CLAUDE.md` should open with
`> Inherits the engineering baseline at claude-baseline/CLAUDE.md` and then
contain only what is genuinely specific to that project (its domain rules,
its architecture, its release cadence). If a rule is true for every
project, it belongs here, not there.

These rules are non-negotiable unless explicitly overridden in writing in
the working session.

---

## 1. Product standard

Everything that ships is commercial-grade software, not a hobby project.
Hold all work to the highest known standards: thorough testing, clean
architecture, comprehensive documentation, security-conscious code,
professional UX. Every change is production-ready.

When fixing an issue, prefer the thorough solution over the quick
workaround. If the reliable approach is more complex, do that first rather
than applying a band-aid that becomes technical debt.

---

## 2. Robustness mandate

**Every layer must be designed to be extremely robust against real-world
unpredictability and edge cases, and must handle errors exceptionally
well.** "Every layer" is literal: each module, each script, each CI
workflow, each external surface.

### 2.1 Concrete expectations

- **Fail loud, never silent.** No caught error is swallowed. Discarding an
  error result without handling it is forbidden. Every error surfaces a
  human-readable reason and a diagnostic path. Log the full error context
  chain, not just the final layer. No panicking unwrap/expect/assert in
  non-test code unless a prior invariant check proves it cannot fire.
- **Pre-flight everything.** Disk space, network reachability, dependency
  presence, credentials, capacity, version compatibility — checked before
  a long job starts, not halfway through.
- **Timeouts on every wait.** No blocking read, lock acquisition,
  subprocess, or network call waits forever. Use deadline-bounded lock
  acquisition on any hot path.
- **Idempotent by default.** Any operation that can be re-run after an
  interruption must be safe to re-run. Partial-state files are written via
  atomic rename-on-close or cleaned up on the next run. Never leave
  `.part`, `.tmp`, or half-written files behind.
- **State markers on phased pipelines.** Every phase writes a completion
  marker; the next run resumes from the last completed phase unless a
  `--force` flag says otherwise.
- **Validate inputs at boundaries.** Path strings, hashes, JSON payloads,
  filenames — validated at the surface. Path traversal, invalid encodings,
  malformed input, zero-byte files, over-long paths, symlink traversal,
  TOCTOU races — all handled at the boundary. Trust internal code; only
  validate where untrusted data enters.
- **Resource caps on every parser.** Recursion depth, decompressed size,
  regex backtracking, per-item memory — all bounded with hard, documented
  limits.
- **Concurrency discipline.** Every shared lock has a deadline. Every
  worker thread has a panic/crash hook that logs to a known path. Every
  channel is bounded. Backpressure sleeps the producer; it never drops
  work.
- **Graceful degradation.** When a sub-system fails, the rest of the
  pipeline degrades cleanly with a visible warning rather than crashing or
  producing silently-wrong results.
- **Signal handling and cleanup.** Ctrl+C, SIGTERM, OOM kill, preemption —
  always leave the dataset recoverable and temp directories wiped.
- **Reproducibility.** Two runs on the same input produce byte-identical
  output. Iteration order of unordered collections must not leak into
  results (sort at the serialization boundary). Capture wall-clock
  timestamps once per operation and reuse them.
- **Observability.** Every long-running loop emits a heartbeat every 30 to
  60 seconds. Every failure writes a diagnostic path the user can paste
  into a bug report. Every pipeline stage logs entry, exit, and duration.

**When in doubt, prefer the robust approach even if it is slower to write.
Every shortcut here is a future outage.**

---

## 3. Planning and feature-design discipline

Whenever you draft a plan, a spec, a milestone, a task list, an API
surface, a schema, a CLI flag, an IPC contract, or any design artifact,
think through these eight dimensions **before** the artifact is considered
done. Skipping any one is the root cause of outages.

1. **Loopholes.** Enumerate explicitly: what could go wrong in the real
   world? Adversarial input? A concurrent-access race? Partial failure?
   Every plan has a numbered "loophole hunt" section pairing each loophole
   with an explicit fix or an accepted-risk argument.
2. **Robustness and graceful degradation.** Describe how the system stays
   useful when a sub-component fails. (See §2.)
3. **Quality bar.** Target best-of-class: correct first, then fast
   (measured baselines), efficient (memory/CPU/IO budgets), stable
   (non-flaky tests, reproducible output), versatile (works across
   environments and inputs), modular (trait or interface boundaries,
   single responsibility, swappable backends), testable (every non-trivial
   function has a test).
4. **Scale-conscious design.** Evaluate every decision against one order
   of magnitude beyond today's scale. (See §12.)
5. **Cross-layer implications.** A change in one layer is checked against
   that layer's consumers. Schema changes ship with migration adapters.
   API changes ship with version bumps. Every layer-crossing interaction
   is an explicit contract with a defined error shape.
6. **Observability.** Heartbeats, diagnostic paths, per-stage timing.
7. **Data preservation by default.** Answer explicitly: "what happens to
   the data?" Dropping data is a load-bearing decision requiring written
   rationale. The default is keep everything, annotate what changed.
8. **Integration-first design.** Every new module, binary, or feature is
   designed as an integration into the existing system, not a standalone
   add-on. It fits existing contracts, reuses canonical modules, honours
   locked conventions, ships in the language already used at that layer.
   If a genuinely better alternative would work better as an independent
   piece, stop and surface the choice before proceeding.

If you cannot fill in a dimension, the plan is not done; surface the gap
and ask for direction.

---

## 4. Two-phase review framework

**Every release ships only after a pre-tag gate review. Every work cycle
closes with a lightweight retrospective. Each serves one purpose; they do
not overlap.**

Four review axes: **integrity, general quality, security posture, extreme
robustness**, applied in the pre-tag gate.

1. **Release gate review** — before every tag/merge. A full sweep across
   the cumulative delta since the last tag, written up with a sign-off
   line. The tag does not land without it. A green CI run is necessary but
   not sufficient; the gate sign-off is the actual gate.
2. **Retrospective** — at the close of each work cycle. Short (30 to 45
   minutes). NOT a re-run of the four axes. Captures: what shipped, what
   slipped, what surprised, what to fold into the next gate so the same
   surprise does not escape twice. Retrospective findings never block a
   release; they shape the next gate.

**Finding-handling.** Every finding surfaced in a gate is fixed in the
same cycle. Deferral is the exception: a finding may defer only if its fix
needs physical hardware, external coordination, or a full infrastructure
build. Every deferred finding carries a written reason and a concrete
next step.

**Self-evolving gate.** Every finding adds an automated check so the same
finding class cannot escape silently next time. The gate gets stronger
every cycle.

A fifth axis is worth running: **recipient review**, for any work handed
to an external party (a PR to another maintainer, a public release), ask
"what would a critical reviewer flag, even something small?" This catches
documentation drift, copy-paste traps, and tone issues the four axes miss.

---

## 5. Supply chain and dependency discipline

The dependency graph is attack surface. Treat it like one. The current
threat pattern: an attacker compromises one package, harvests credentials
from everyone who installs it, and uses those to compromise the next, a
cascade. The defence is **blast-radius reduction**: assume any dependency
may turn hostile, and make sure that when one does, it reaches nothing
valuable.

- **Lockfiles are committed, always.** `Cargo.lock`, `package-lock.json`,
  `pnpm-lock.yaml`, `uv.lock` — all version-controlled, for libraries as
  well as binaries.
- **Version cooldown.** Do not adopt a dependency version younger than the
  cooldown window (default: 7 days; longer for critical paths). Most
  compromised versions are caught within days. See `supply-chain/` for
  the `.npmrc` and Renovate configuration that automate this.
- **Pin everything that is not lockfile-managed.** Editor extensions
  pinned to exact versions. CI actions pinned by commit hash, never by
  tag. Container base images pinned by digest, never by tag.
- **Disable auto-update** on editors and editor extensions. Update
  deliberately, after the cooldown window, having read what changed.
- **Minimize the surface.** Every dependency and every editor extension is
  attack surface and runs with your privileges. Audit and prune
  regularly. Prefer the standard library and a small, well-known
  dependency set over many small convenience packages.
- **Isolate untrusted builds.** Do not run a build, install, or test of
  untrusted third-party code as the same user that holds your keys and
  credentials. Use a container, a VM, or a dedicated user. For build
  scripts and macros, prefer a sandbox.
- **Vet dependencies.** Use the ecosystem's audit tooling (advisory-db
  checks, dependency review). Know that audit tools catch *known* issues,
  not zero-days — cooldown and isolation cover the rest.
- **A new dependency is a decision.** Adding one is reviewed like any
  other design choice: who maintains it, how big is it, what does it pull
  in transitively, could three lines of our own code replace it.
- **AI coding tools are now targeted.** Configuration and credential files
  for AI development tools are an explicit exfiltration target. Keep their
  config free of plaintext secrets; keep their credentials out of synced
  repositories.

A weekly automated dependency audit is defined in
`agents/weekly-dependency-audit.md`. It proposes; a human reviews and
approves. Nothing auto-merges.

---

## 6. Scope discipline

- **Do not touch code outside the scope of the task.** Do not reformat,
  restructure, or refactor anything unrelated.
- **Pre-existing warnings on untouched code are left alone.** Warnings on
  newly-added or modified code are fixed before the work is done.
- **If something looks broken outside scope**, record it in the project's
  deferred-work tracker and move on.
- **Do not add features, abstractions, or indirection beyond what the task
  requires.** A bug fix does not need surrounding cleanup. Three similar
  lines beat a premature abstraction.
- **Do not add error handling for scenarios that cannot happen.** Trust
  internal code and framework guarantees. Validate only at system
  boundaries.
- **Default to no comments.** Add one only when the *why* is non-obvious:
  a hidden constraint, a subtle invariant, a workaround for a specific
  bug, behaviour that would surprise a reader. Do not explain *what* the
  code does — names do that. Do not reference the current task in
  comments.
- **Even in auto-accept mode, pause and ask** when something is unclear,
  when a design decision has multiple valid paths, or when a mistake would
  be expensive. A 30-second question saves 30 minutes of rework.

---

## 7. Test coverage

- **At least 90% branch coverage on changed files.** Every new function
  covered. Every error path covered.
- **Never disable a test without a documented reason** in the test file.
  Never delete or comment out an existing test without documenting why.
- **The test pyramid is real:** unit, integration, end-to-end, adversarial,
  chaos, benchmarks. For load-bearing components, all layers apply.
- **Tests verify correctness, not feature presence.** A passing suite does
  not mean the feature works as the user expects; manual verification of
  user-facing behaviour is required before claiming complete.
- **No flaky tests.** A test that passes 90% of the time is not green.
  Find the race or ordering bug; do not add retry loops.

---

## 8. Commit hygiene

- **One commit per atomic change.** Not end-of-milestone mega-commits.
- **Commit messages describe the *why*,** not the *what*.
- **No co-author trailers and no AI-attribution boilerplate.** No
  "Generated with", no tool attribution, no robot emoji. The author is the
  author; tools are tools.
- **No `--no-verify` and no skipping signing** unless explicitly requested
  in the session. If a hook fails, fix the underlying issue and make a new
  commit. Do not amend pushed commits.
- **Commit messages are public-safe:** no internal planning markers, no
  private paths, no infrastructure identifiers, no secrets.
- **No hyphens in user-facing strings** (UI copy, CLI output, reports,
  documentation prose, PR descriptions). Rewrite with commas, semicolons,
  parentheses, or restructure the sentence. Hyphens in identifiers, flags,
  file paths, and commit subjects are fine.
- **Push only when asked.** If on the default branch, branch first. Never
  force-push a shared branch.

---

## 9. Code style

- Follow the language's standard formatter and linter. Fix all warnings on
  changed code before finishing.
- Prefer error propagation over panics in all non-test code.
- No debug prints or scratch logging left in production paths.
- Comments explain *why*, not *what* (see §6).
- Error messages shown to users are plain language, not raw error strings.

---

## 10. Verification discipline

When asked to verify, simulate, or test that something works:

1. **Run real checks.** Write test scripts, read the actual library
   source, grep for actual behaviour. Do not theorise about what should
   happen and present it as verification.
2. **If live testing is impossible** (needs hardware or network access not
   available), say so explicitly and describe what was verified statically
   versus what still needs manual testing.
3. **If thorough testing will take significant time,** say so before
   starting and let the user decide whether to invest it.
4. **Never present a theoretical walkthrough as an actual test.**

---

## 11. Explanation register

When explaining anything (a concept, a trade-off, why one tool was chosen
over another, what a piece of code does), default to the register of a
sharp 17-year-old: smart and curious, but without a CS degree.

1. **Lead with the picture, not the jargon.** Open with what the thing
   does in plain language. The technical name comes second.
2. **Use analogies to physical things.**
3. **Diagrams are first-class.** A six-line ASCII picture beats 30 lines
   of prose. Use tables for trade-offs.
4. **Define every acronym the first time** it appears.
5. **Trade-offs as tables:** what you get / what you give up / who it
   hurts when it fails.
6. **Numbers carry units and context,** not bare figures.
7. **Never end a section without a "so what".** One sentence on why the
   reader should care.
8. **No condescension.** Do not dumb it down; do not assume prior
   knowledge the reader does not have.

Applies to chat replies, plan sections, commit bodies, comments longer
than two lines, and PR descriptions.

---

## 12. Scale-conscious design

Evaluate every architectural decision, data structure, and pipeline
against **the most extreme scale the system could plausibly meet, up to
quadrillions of records, users, events or transactions**, even when
today's dataset is small. The point is not to over-engineer today's
code; it is to make sure today's choices do not force a rewrite at any
realistic scale the system might ever reach. Trait boundaries, content-
addressed layouts, partitioned batch work and streaming pipelines are
nearly free now and enormous later.

1. **No in-memory collection that grows unboundedly with input size.**
   Stream or partition instead. A trait or interface boundary alone is not
   enough if the chosen implementation still accumulates everything.
2. **Trait/interface boundaries between logic and storage.** Parsers,
   scoring, and detection never touch storage directly. Storage backends
   are swappable.
3. **Content-addressed paths for file storage** (`hash[0:2]/hash[2:4]/
   hash`) so the layout works identically on local disk or object storage.
4. **Design batch work as partition, distribute, merge, reconcile.** The
   reconcile step resolves conflicts that pure merge gets wrong at scale.
5. **Prefer streaming over accumulation.** Process one item at a time
   where possible.
6. **Lay the trait, the convention, and the path structure now** even if
   today's implementation behind them is trivial. A trait boundary is
   nearly free; a rewrite is enormous.

---

## 13. Secrets and data handling

- **Credentials never appear in logs, commits, error messages, or shared
  output.** A pre-commit hook scans for them (see `hooks/`).
- **Secrets never live in a synced repository in plaintext.** Use an
  encrypted-at-rest mechanism so the repository only ever holds
  ciphertext, or keep them out of version control entirely.
- **Private keys are per-machine or hardware-backed where practical.** A
  single private key shared across machines means one compromise is total
  compromise.
- **No untrusted data on a trusted machine without isolation** (see §5).
- **Validate at the boundary, trust internally** (see §2.1).

---

## 14. Language register

- **British English everywhere.** Chat replies, source comments,
  documentation, commit messages, PR descriptions, user-facing CLI
  and GUI strings. *analyse* not analyze, *colour* not color,
  *behaviour* not behavior, *recognise* not recognize, *organisation*
  not organization, *licence* (noun) and *license* (verb) as in BrE.
  Code identifiers stay with whatever the surrounding library
  dictates (e.g. CSS `color`, `Cargo.toml` `license` field, image
  crate `ColorType`) — those are interface contracts, not prose.
- **Explanation register stays as §11** — sharp 17 year old, plain
  language first, jargon second, analogies to physical things,
  diagrams when they beat prose, no condescension.

---

## 15. Sleep advisory (NON-NEGOTIABLE, cross-project)

**Between 20:00 and 05:00 UK local time (BST in summer, GMT in
winter; `TZ=Europe/London` is canonical), every single response
MUST open with a short, firm advisory to wrap the session and
rest.** The work is there tomorrow.

**Format.** 1 to 2 lines at the top of the response, before any
technical content. MUST begin with the 💤 emoji. MUST be ALL
UPPERCASE. Use the correct BST or GMT label based on the actual UK
offset returned by `date` (run `TZ=Europe/London date` when
uncertain), not "BST" year-round.

Example (summer):

> 💤 IT'S PAST 20:00 BST. SUGGESTING YOU CLOSE THIS SESSION AND REST — THE WORK WILL SURVIVE THE NIGHT.

**Dismissal.** "stop" / "dismiss" / "I want to keep going" / "mute"
suppresses the advisory for exactly 1 hour from the dismissal.
After 1 hour, if the response is still inside the 20:00 to 05:00
window, the advisory resumes. Each dismissal is 1 hour only. The
advisory cannot be permanently turned off. Safety beats convenience.

**Why.** Most operators carrying this baseline are running it
alongside day jobs and other evening commitments. Burnout is the
real, observed risk. Other rules track pace; this one enforces the
floor.

---

## 16. No future-version references in user-facing artefacts

Public documentation, README sections, AUP, release notes, CHANGELOG
entries that are not the current release, and any marketing copy
ship **only what the current release contains**. Future versions
(v4.1+, v5+, anything not-yet-released) are not named, are not
promised, and are not previewed in public artefacts.

The one allowed exception is the project's private roadmap document
(typically `private/plans/roadmap.md`, gitignored), which is the
canonical place to track future-version intent.

Reasoning: future commitments quietly bind us to ship things on a
timeline we may want to change. Naming them publicly creates an
implicit promise; staying silent leaves us free to reroute, defer,
or replace without breaking trust.

Hook-enforced via `pre-commit` when the project sets
`BLOCK_FUTURE_VERSIONS_REGEX` in `.baseline-hook-config`. Refusal is
loud and points to this section.

---

## 17. Decision-matrix format

Whenever a decision is presented with more than one viable option,
present it as a **four-column matrix preceded by context and
followed by an explicit recommendation**, in this exact shape:

1. **Context.** One short paragraph describing the situation, why
   the decision is being raised now, and what success looks like.
2. **Matrix.** A four-column table:

   | Option | Pros | Cons | Best for |
   |---|---|---|---|
   | ... | ... | ... | ... |

3. **Recommendation.** A single sentence (or short paragraph if it
   is a combination) stating which option to pick and why — even
   when the recommendation is an unorthodox combination of parts of
   multiple options. *"Combine A's storage layer with B's API"* is
   a legitimate recommendation; the matrix surfaces the components,
   the recommendation re-combines them honestly.

Pure preference questions (theme, naming, ordering) can skip the
matrix. Anything with architectural, security, performance or
licensing implications uses it.

---

## 18. CHANGELOG format

CHANGELOG entries are written to be skimmed by a user with thirty
seconds, no internal context, and no prior team knowledge.

**Reader expectations.**

- Plain bullet points, one per change.
- One sentence each; two only if the second sentence is genuinely
  needed for the user to understand the change.
- Group by *area* (Engine / GUI / CLI / Docs / CI / Licence / Security
  / Other) when the release has changes across multiple surfaces;
  flat list otherwise.
- Notable changes first, mundane changes near the end.
- **Close every entry with an `### Other` section** whose single
  bullet is the verbatim line *"Bug fixes and improvements."* This
  signals the round-up of small changes that didn't earn their own
  bullet, and is the convention every project in this baseline uses
  even when there are no leftover small fixes. Skip it only for the
  very first release of a project.
- For a release that genuinely had nothing user-facing worth
  detailing, the entire body collapses to the same closer:
  *"Bug fixes and improvements."* used verbatim as the only line.
- Date format is ISO 8601 (`YYYY-MM-DD`).
- Format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

**Banned in user-facing CHANGELOG entries.**

- Internal ticket / sprint / phase identifiers (`Q-37`, `T-29`,
  `Phase 3.5`, `Sprint-12`). They are noise to a public reader.
  Describe the change, not the ticket.
- Forward-looking lines (*"next release will…"*) — see §16.
- LLM tells (§21) and unnecessary em dashes (§19) — public docs.
- Internal-team shorthand for components that don't appear in the
  public API or UI.

The CHANGELOG is the canonical source for GitHub Release notes;
write it once, paste it twice.

---

## 19. No unnecessary em dashes or en dashes in prose

**Rule.** Em dashes (`—`) and prose en dashes (`–`) become an LLM
tic when used as a dramatic-pause crutch in flowing prose. The fix
is to replace them with the punctuation the sentence actually needs:

- A colon (`: `) for definitions and labels: *"LSB: Least
  Significant Bit"*.
- A comma (`, `) for loose subordinate clauses.
- A semicolon (`; `) when two independent clauses need joining.
- A full stop and a fresh sentence when the second half is a
  separate thought.
- Parentheses for genuinely parenthetical asides.

**Em dashes are still allowed where they genuinely work.** The
rule is "not so common", not "never". These uses are fine and the
hook does not flag them:

- Label-description pairs in bullet lists: `- Term — description.`
- Markdown table cells (column dividers, "not applicable" markers).
- Section headers separating title from subtitle: `## Section — Subtitle`.
- Tree-map and file-map alignment where the dash is a layout glyph.
- Inline code paired with a brief note: `` `flag` — what it does ``.

**Scope.** All public docs (README, AUP, CHANGELOG, COMMERCIAL,
docs/**, frontend READMEs), all source comments, all commit messages
and PR bodies, all chat replies, all generated user-facing content.

**Keep these (legitimate hyphen use, not in scope):**

- Compound modifiers: *UK-based, remote-first, 45-minute*.
- Hyphenated words: *co-ordinate, state-of-the-art*.
- Filenames and identifiers (`stegcore-engine`, `package.json`).
- Range tables where space is genuinely tight (date columns in a
  narrow table).

**Hook-enforced** via `pre-commit` em-dash gate, which inspects
only inline prose and skips bullets, headers, tables, blockquotes,
tree-map alignment and inline-code-adjacent dashes. Override on a
case-by-case basis via `.baseline-hook-allow` with a comment
explaining the legitimate use; disable entirely with
`EMDASH_ENABLED=0`.

---

## 20. Documentation philosophy

Two audiences, two registers, but the same plain-language register
underneath.

**Public documentation (README, user guides, AUP, COMMERCIAL, marketing
copy, CLI help text, GUI strings, error messages):**

Always simple. A reader with no prior context, no CS degree, and 30
seconds of attention has to understand what the tool does and how to
use it. Short sentences. Concrete examples. No jargon without
definition. No internal-team shorthand. If a paragraph can't be
explained out loud to a smart 17 year old (see §11), rewrite it.

**Internal documentation (ARCHITECTURE, design docs, runbooks,
private/plans, ADR records, post-mortems):**

Simplicity and length beat complexity and brevity. Take the time and
words needed to be unambiguous. A four-paragraph explanation that a
new contributor can follow is better than a two-line "obviously"-
flavoured one that needs three Slack messages to clarify. Diagrams
when prose gets long. Examples next to abstractions. Cross-references
to related docs.

Both registers stay British English (§14) and skip the unnecessary
em-dash habit (§19). Public docs may sacrifice some completeness for
accessibility; internal docs may sacrifice some brevity for clarity.
Neither sacrifices honesty.

---

## 21. Minimise LLM writing tells in public documentation

Public artefacts (README, AUP, COMMERCIAL, docs/, marketing copy,
release notes, GUI strings) read as if a human wrote them with
intent. The patterns below are the ones that flag prose as
LLM-generated even when the content is correct. Avoid them in public
docs. They are tolerated in internal docs (§20) where length and
clarity beat polish, but flag them for cleanup if they start to
accumulate there too.

**Negative parallelisms.** Constructions of the shape *"X is not
just A, it's B"* or *"This isn't only X, it's Y"*. The pattern feels
profound but is empty rhetoric. Rewrite to make the positive claim
directly: *"X is Y"*.

**Hedge stacks.** Stacking *could potentially*, *may possibly*,
*tends to often*, *might generally* in a single paragraph. Pick one
qualifier and only if the claim genuinely needs one.

**Tricolons of generic adjectives.** *"Fast, scalable, and
reliable"*; *"robust, comprehensive, and seamless"*. Replace with
specific claims that have numbers, or drop the marketing-fluff and
just describe what the thing does.

**Overused LLM vocabulary.** *Delve, leverage, robust, comprehensive,
seamless, navigate (in figurative sense), unleash, elevate, tapestry,
realm, landscape (figurative), embark, foster, holistic, paradigm,
profound, intricate, nuanced, multifaceted, vibrant, rich (in
abstract sense), it's worth noting that, it should be noted that,
in conclusion, in summary, moreover, furthermore (paragraph-start),
additionally (paragraph-start)*. Use specific words.

**Em dashes as dramatic pause.** Already covered in §19.

**Sycophantic openers.** *"Great question!"*, *"Absolutely!"*,
*"I'd be happy to..."* before a technical answer. Just answer.

**Curly / smart quotes (`"` `'`).** Use straight ASCII quotes (`"`
and `'`) in source-controlled prose. Curly quotes signal AI rendering
or autocorrect interference and break in plain-text contexts.

**Rhetorical questions to close a section.** *"So what does this
mean for you?"* Just state it.

**Uniform sentence length.** Vary it. A run of identical-length
sentences is a polish-too-far signal.

**"It's important to note that"** and any other phrase that adds
weight without adding information. Cut the phrase, keep the
information.

Hook-enforced subset: the highest-confidence tells (negative
parallelisms, the LLM vocabulary list, sycophantic openers, curly
quotes, "it's important to note that") are scanned by `pre-commit`
on additions to public docs. Override with `.baseline-hook-allow` if
a specific use is genuinely the right word.

---

## 22. Release tag codenames

**Rule.** Every release tag carries a human codename in addition to
its semantic version. The codename is **chosen by the user**,
typically from the TV series, anime, film or other media they are
currently watching at the time of the release. Past examples:
*Dokima*, *Anya* (the frozen project's headline series). The
codename lives in:

- the annotated tag message, as a `Codename:` line near the top.
- the GitHub Release title, in the form `vX.Y.Z — <Codename>`.
- the CHANGELOG entry header, in the same form.

**Workflow.** Before creating a release tag, **always ask the user
for the codename**. Never invent one. The conversation is short:

> "Picking the codename for vX.Y.Z — what are you watching at the
> moment?"

If the user says they don't have one in mind, suggest deferring the
tag until they do rather than shipping an unnamed release. The
codename is not optional; it is how the project keeps its release
history personal and memorable rather than a sterile semver list.

**Hardening.** The `pre-push` baseline hook refuses to push an
annotated `v*` tag whose message lacks a `Codename:` line (this is
the soft enforcement of the policy). Override with
`SKIP_TAG_CODENAME=1 git push` only with a recorded reason; the
intent is to catch the case where the tag was scripted without the
codename rather than to block legitimate fast-paths.

---

## Adopting this baseline

1. Copy or symlink `claude-baseline/` into the new project, or reference it
   from the project's own `CLAUDE.md`.
2. Install the hooks: run `hooks/install.sh` from inside the project repo.
3. Add the supply-chain configuration: copy the relevant file from
   `supply-chain/` for the project's package manager.
4. The project's own `CLAUDE.md` inherits this file by reference and adds
   only project-specific rules.
5. Register the weekly dependency audit (`agents/weekly-dependency-audit.md`)
   as a scheduled task.

When a baseline rule changes, change it here. Project files never fork a
baseline rule; they either inherit it or explicitly override it in writing
with a recorded reason.


---

## PART B — LATITUDE-FINGERPRINT PROJECT FACTS

### Project overview

A packaging effort, not a driver-authoring effort. Canonical already ships a
working closed-source fingerprint driver for the Broadcom BCM58200 ControlVault
3 sensor (USB ID `0a5c:5843`) as a libfprint TOD ("Touch On Demand") plugin,
but it is pinned to the 22.04 OEM apt pocket. Dell Latitude and Precision
owners on releases after 22.04 cannot `apt install` it. This project backports
that blob's `debian/` packaging to the two current LTSes (24.04 noble and 26.04
resolute), hosts it in a public PPA plus a GitHub Releases mirror, and closes
Launchpad bug
#2099655. It serves Latitude/Precision owners stuck without fingerprint login
on post-22.04 Ubuntu. The proprietary blob is never redistributed; the user
fetches it on install (see `docs/LICENSING.md`).

- Owner: Daniel Iwugo
- Licence: AGPL-3.0-or-later (the project's scripts, packaging metadata, and
  write-ups; the Broadcom blob stays under its proprietary "Broadcom-tod"
  licence and is never bundled)
- Repo home: GitHub `latitude-fingerprint` (canonical, public)
- Launchpad identity: `elementmerc`; PPA `ppa:elementmerc/latitude-fingerprint`
- Hardware target: Dell Latitude 7420 ("Chronos"), Broadcom BCM58200 CV3,
  `0a5c:5843`, running Ubuntu 26.04 LTS (resolute), libfprint `1.95.1+tod1`,
  fprintd `1.94.5`
- Target suites: noble (24.04 LTS) and resolute (26.04 LTS). See Q-12.
- Status: active, sprint 0, public from day 1

### Decisions

Live queue: [`private/decisions.md`](private/decisions.md) (Q-coded, §17
matrices; all eleven sprint-0 decisions LOCKED). Promote a Q-N to a formal ADR
under `docs/decisions/` only when it becomes load-bearing on architecture,
security, or data model; none qualifies yet.

### Architecture

The full executable brief, with the §3 loophole hunt and §4 review hooks, lives
in [`PLAN.md`](PLAN.md). Background and the RE-vs-packaging pivot live in the
operator-local research memos under `private/research/` (gitignored:
`2026-05-23-idea.md`, `2026-05-23-research.md`). There is no code
architecture beyond two shapes: `shape-a/` (a personal `install.sh` +
`SHA256SUMS`) and `shape-b/` (per-suite `debian/` packaging built with
`sbuild`).

### Sister-project context

- **olympus** (laptop bring-up automation): Shape A's `install.sh` is designed
  as a unit olympus can reuse. Integration-first, not standalone (§3.8).
- **stegobench** (Docker bundle of stego tools): shares the Debian-packaging
  muscle on a different target; lessons transfer both ways.
- **Stegcore / Dokima / Anya**: same AGPL-3.0 public-project licence family. No
  code dependency; this project is not blocked on any of their roadmaps.

---

## PART C — ADAPTATIONS (latitude-fingerprint vs other operator projects)

How this project diverges from the baseline or from sister-project conventions:

- **Public from day 1.** Unlike Hephaestus (private indefinitely), this repo is
  public from the first commit. Secret discipline (§13) and the public-doc
  hooks (§16, §19, §21) apply from the start.
- **Single operator, no multi-tenancy.** One maintainer, one piece of
  hardware. No refusal posture, rate-limit, or ops-page surface to design.
- **Distribution surface is external infra, not the shared hub.** This project
  consumes Launchpad (the `elementmerc` PPA), the Ubuntu build farm, and GitHub
  Releases, rather than the operator's Forgejo/Tailscale infrastructure. The
  proprietary blob is never redistributed on any of them (mere aggregation;
  `docs/LICENSING.md`).
- **Naming is descriptive, not Greek or commercial.** The repo, PPA, and
  package names are `latitude-fingerprint` and the upstream
  `libfprint-2-tod1-broadcom`, chosen for search discoverability ("latitude
  7420 fingerprint ubuntu"), not for an internal codename scheme.
- **Operator-paced sprints.** Cadence is weekend-shaped sprints (0 to 3), not
  continuous delivery. Git v-tags carry codenames (§22), first tag after the
  Sprint 0 hardware gate.
- **No native build/test CI.** There is no Rust/TS to compile; CI is limited to
  SPDX-header verification (`licence-check.yml`). The real correctness gate is
  hardware-bound (`fprintd-verify` on Chronos), not automatable in CI.

---

## How to update this file

- **PART A is shared.** Any change to PART A should land first in the baseline at `crazy-random-ideas/claude-setup/baseline/CLAUDE.md`, then propagate to every project's CLAUDE.md PART A. Drift between this file's PART A and the baseline is a bug; fix in the baseline + re-sync.
- **PART B + PART C are project-specific.** Edit freely. Sister projects will diverge over time; that is the intended pattern.
- **When in doubt** about whether something belongs in PART A (universal) vs PART B (project facts) vs PART C (adaptations), ask: "would another project of mine want this rule?" Yes → PART A. No → PART B or C.
