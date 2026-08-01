# How Home Assistant persists and renders add-on options

Primary-source research into what the Supervisor and the frontend actually do with an add-on's
`options:` defaults, its `schema:`, and the operator's stored values. Everything below is read from
source, not documentation prose, except where the developer docs are cited directly.

## Sources and how to read the links

All Supervisor links are permalinks to commit
[`3dea234`](https://github.com/home-assistant/supervisor/tree/3dea234189bc9fc910729fa502be2e1024462103)
(`main`, 2026-07-31, between releases 2026.07.5 and 2026.08).
All frontend links are permalinks to commit
[`f71a938`](https://github.com/home-assistant/frontend/tree/f71a938d023065aa6f4b7254c703ef2cde5516f5).

**Naming note.** Upstream has renamed the Supervisor's add-on modules from `supervisor/addons/*` to
`supervisor/apps/*`, and the classes from `AddonOptions`/`Addon` to `AppOptions`/`App`. The rename is
present in every current release (verified: `supervisor/apps/options.py` exists at tags `2026.06.2`
and `2026.07.5`; `supervisor/addons/options.py` returns 404 at both). The REST surface is unchanged —
routes are still `/addons/{slug}/options`, `/addons/{slug}/options/validate`
([`api/__init__.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/api/__init__.py#L647-L658))
— and the on-disk contract (`/data/options.json`) is unchanged. This document uses HA's public
"add-on" vocabulary and links to the `apps/` paths.

---

## 0. The mechanism, in one paragraph

There are three distinct objects, and conflating them is the source of most confusion:

1. **Defaults** — the `options:` block of the add-on's `config.yaml`. Stored by the Supervisor as the
   add-on's *system* data.
2. **Persisted user values** — a separate *user* dict, per add-on, in the Supervisor's own store.
   Starts empty on install
   ([`AppsData.install`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/data.py#L40-L48)
   sets `{ATTR_OPTIONS: {}}`).
3. **Effective options** — `App.options`, computed on every read as a deep merge of (1) with (2)
   layered on top
   ([`App.options`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L442-L447)).
   The merger recurses into dicts and **overrides everything else, including lists**
   ([`_OPTIONS_MERGER`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L130-L134):
   `type_strategies=[(dict, ["merge"])]`, `fallback_strategies=["override"]`).

`/data/options.json` is (3), validated against the schema, rewritten on **every add-on start**
([`App.start`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L1305-L1307)
calls
[`write_options`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L866-L884)).
The UI shows (3) too — the info endpoint returns `app.options`
([`api/apps.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/api/apps.py#L254-L255)).
The add-on never sees (2) alone, and cannot write to any of them.

---

## 1. Are all schema defaults written to `/data/options.json`?

**Yes. `/data/options.json` contains every key that has a default in `config.yaml`'s `options:`
block, whether or not the operator ever touched it** — minus any key not present in `schema:`.

[`write_options`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L866-L884)
writes `self.schema.validate(self.options)`, i.e. the merged dict (defaults + user values) after
passing through validation — not the user's overrides. The developer docs state only that
"`/data/options.json` contains the user configuration"
([add-on configuration reference](https://developers.home-assistant.io/docs/add-ons/configuration/));
the code shows this to mean the *effective* configuration.

Validation is a filter, not just a check.
[`AppOptions.__call__`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L78-L103)
iterates the incoming dict and **drops any key not in `raw_schema`**, logging
`Option '<key>' does not exist in the schema for <name> (<slug>)`. The same drop happens one level
down in
[`_nested_validate_dict`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L247-L272)
(`Unknown option '<key>' for ...`). So a default declared in `options:` but absent from `schema:`
never reaches the add-on.

After filtering,
[`_check_missing_options`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L274-L291)
requires every schema key whose type string does not end in `?` to be present. For a list type
(`["str"]`) the *element* type decides: `["str?"]` makes the key itself optional. A missing required
key raises `vol.Invalid`, which `write_options` turns into `AppConfigurationInvalidError` — the
add-on does not start.

**What the operator sees on a fresh install.** The frontend seeds its editor from `addon.options`
([`updated()`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L385-L389):
`this._options = { ...this.addon.options }`), which on a fresh install is exactly the `options:`
block from `config.yaml`. In YAML mode the editor is populated with that whole dict. In UI mode the
form is filtered to entries that are either present in `options` or marked `required`
([`_filteredSchema`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L243-L247)) —
so a schema key with **no default and no `?`-less requirement** is hidden until the operator flips
the "Show unused optional configuration options" switch
([render](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L249-L256)).

Consequence for this add-on: every key in `blocky/config.yaml`'s `options:` block — all ~130 of
them, including `""`, `[]` and `0` placeholders — is visible in the operator's YAML editor and
present in `/data/options.json` from the first boot. There is no "unset" state for them.

**Confidence: high.** Direct reads of the write path and the form's data seeding.

---

## 2. How the form renders types

Rendering is two-stage. The Supervisor converts the raw schema into a UI descriptor
([`UiOptions`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L294-L442),
exposed as `schema` on the info endpoint), and the frontend converts that descriptor into selectors
([`_convertSchemaElementToSelector`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L173-L239)).

### `str` vs `str?`

The `?` suffix affects **exactly one field** of the UI descriptor.
[`_single_ui_option`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L358-L362):

```python
if value.endswith("?"):
    ui_node["optional"] = True
else:
    ui_node["required"] = True
```

The widget itself is identical — both become `{"type": "string"}` and then a `text` selector. The
difference shows up as (a) the required-marker and native `required` attribute on the input
([`ha-form-string`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/components/ha-form/ha-form-string.ts#L54-L61)),
and (b) whether the field survives `_filteredSchema` when it has no persisted value (§1).

Type → widget mapping, from
[`_single_ui_option`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L364-L403)
and the frontend converter: `str`/`match(...)` → text; `password` → text with `format: password`;
`email`/`url` → text with that format; `int`/`port` → number box; `float` → number box with
`step: any`; `bool` → toggle; `list(a|b|c)` → select with those options; `device` → select populated
from hardware.

Note two frontend-side surprises: a top-level option **named** `password`, `secret` or `token` is
masked regardless of its declared type
([`MASKED_FIELDS`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L56)),
and a list of scalars (`multiple: true` on a string type) renders not as a text area but as a
free-entry chip selector (`select` with `custom_value: true`,
[here](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L183-L195)).

### Nested objects

A dict in the schema becomes a `type: "schema"` node — and
[`_nested_ui_dict`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L422-L442)
**hardcodes `"optional": True`** on it. A nested group is therefore never itself required in the UI
descriptor, no matter what its children say. Requiredness of the children is carried on the child
nodes.

The frontend renders a non-`multiple` schema node as an **expandable form section**
([`_convertSchemaElement`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L143-L155)) —
this is what every top-level group in `blocky/config.yaml` (`upstreams`, `blocking`, `caching`, …)
becomes.

### Lists of objects

A list containing a dict produces the same `type: "schema"` node with `multiple: true`
([`_nested_ui_list`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L407-L420)).
The frontend does **not** expand these inline: it converts them to an `object` selector with
`multiple: true` and a `fields` map
([here](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L199-L227)),
which renders as a sortable list of rows plus an **Add** button; adding or editing a row opens a
modal form dialog
([`ha-selector-object`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/components/ha-selector/ha-selector-object.ts#L155-L176)
and
[`_addItem`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/components/ha-selector/ha-selector-object.ts#L237-L262)).
So `upstreams.groups` is a row list, and each row's `resolvers` is a chip field inside that dialog.

Depth is capped: `SCHEMA_ELEMENT` forbids a list directly inside a list
([`validate.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/validate.py#L144-L156),
comment: *"A list may not directly contain another list"*), matching the docs' "maximum depth of
two".

### Is a required field *inside a list entry* enforced?

**Yes, server-side, unconditionally.**
[`_nested_validate_dict`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L247-L272)
runs `_check_missing_options` on **every element** of the list, so a `groups` entry missing `name` or
`resolvers` raises `Missing option 'resolvers' in <key> in <name> (<slug>)`. This is enforced both on
save (`POST /addons/{slug}/options` validates via `app.schema(body)` before persisting,
[`api/apps.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/api/apps.py#L331-L339))
and again on start in `write_options`.

Client-side it depends on *how* the operator edits:

- **Via the row dialog** — blocked before it is ever sent. The dialog calls `reportValidity()` on its
  form and refuses to submit, showing a generic validation error
  ([`dialog-form.ts`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/dialogs/form/dialog-form.ts#L109-L115)).
- **Via the YAML editor, or by leaving a top-level field empty in the main form** — not blocked. The
  main config panel never calls `reportValidity`; in UI mode it sets `_valid = true` on every change
  ([`_configChanged`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L424-L435)).
  Save calls `POST /addons/{slug}/options/validate` first
  ([`_saveTapped`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L482-L515)),
  and on failure the operator sees a red alert reading **`Failed to save: <message>`**
  ([`en.json`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/translations/en.json#L2929)),
  where `<message>` is voluptuous' `humanize_error` output over the Supervisor's message string.

### The requiredness trap

"Required" means **the key is present and not `null`** — nothing more.
[`_single_validate`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L118-L124)
raises only `if value is None`. An empty string satisfies a required `str`; an empty list satisfies a
required `[str]` (`_nested_validate_list` iterates zero elements and returns `[]`). This is precisely
why this add-on needs runtime guards (ADR-0002) rather than trusting schema requiredness: HA will
happily hand the template `upstreams.groups: []`.

**Confidence: high** for the descriptor and selector mapping and for server-side enforcement (direct
code). **Medium** for the exact rendered appearance of a row list and the exact wording an operator
sees for a nested validation failure — the string is composed at runtime by `humanize_error`, and
this was not verified against a running instance.

---

## 3. What happens to persisted values when the schema changes?

**The ADR's claim is confirmed, with one refinement about *when* the drop becomes permanent.**

`CONTEXT.md` and
[ADR-0005](../adr/0005-passive-config-migration-via-schema-retention.md) state: *"on a schema change
it keeps persisted values for keys still in the schema and silently drops the rest"*, and *"the
add-on cannot safely rewrite `/data/options.json` because HA owns that file"*. Both hold.

- **Option removed from the schema.** The persisted user value is *not* deleted at update time —
  [`AppsData.update`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/data.py#L57-L61)
  replaces the system (config.yaml) data but only touches `version` and `image` in the user data. The
  value is dropped at *use* time: every `write_options` filters it out with a warning
  ([`__call__`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/options.py#L83-L92)),
  so the add-on never sees it again. The drop becomes **permanent** the next time the operator saves
  anything, because the API stores the *validated* body, not the raw one:
  `body[ATTR_OPTIONS] = app.schema(body[ATTR_OPTIONS])` and then `app.options = body[ATTR_OPTIONS]`
  ([`api/apps.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/api/apps.py#L331-L348),
  setter at
  [`app.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L449-L452)).
  Effect for the operator: identical to deletion. There is no migration hook anywhere in the update
  path.
- **Option renamed.** Old key persisted, new key not → the old value is dropped and the new key falls
  back to its `options:` default. HA does nothing to bridge them. This is exactly the gap ADR-0005's
  schema-retention pattern fills.
- **Option made optional (`str` → `str?`).** No effect on persisted values. `?` is read only by
  `_check_missing_options` (presence) and `_single_ui_option` (the `optional`/`required` flag). It
  never changes how an existing value is validated or stored.
- **Option made *required*, or its type narrowed, incompatibly.** `write_options` raises and the
  add-on refuses to start. For *auto*-updates only, there is a pre-flight:
  [`test_update_schema`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L1213-L1241)
  re-merges the current user values against the *new* schema and, on failure, logs `App <slug> will
  be ignored, schema tests failed`
  ([`misc/tasks.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/misc/tasks.py#L138-L140))
  and skips the update. A manual update is not gated by this.

The "HA owns the file" claim is also literally true: `write_options` overwrites `/data/options.json`
on every start, so anything the add-on writes there is lost at the next restart — not merely at the
next UI change.

One refinement worth recording: because the drop is a *read/write-time filter* rather than a
migration, a schema key that is removed and **later re-added** will resurrect the operator's original
value, provided they never pressed Save in between. That is a fragile property and should not be
relied on.

**Confidence: high.** Every step is a direct code read; no inference required.

---

## 4. Can an operator shrink their config by deleting keys?

**No, not for any key that has a default in `options:`. HA restores it on the next read — you do not
even have to save or restart to see it come back.**

`App.options` re-merges the `config.yaml` defaults underneath the persisted values on *every access*
([`app.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L442-L447)).
Deleting `blocking.block_ttl` in the YAML editor and saving removes it from the persisted user dict;
the very next `GET /addons/{slug}/info` recomputes the merge and hands the frontend `6h` again. The
same merge feeds `write_options`, so `/data/options.json` is never smaller than the defaults.

The exceptions, and only these:

- Keys that exist in `schema:` but **not** in `options:` (typically `?`-suffixed). These are genuinely
  absent until set, and can be removed again.
- Keys the operator adds that are not in the schema at all — dropped on save.
- A key whose default is a **list**: deleting individual *elements* works, because the merger
  overrides lists wholesale rather than element-merging them. `resolvers: []` is a real, persistable
  state; `resolvers` *absent* is not.

To shrink back to defaults wholesale there is one supported move: the config panel's **Reset to
defaults** menu item, which sends `options: null`
([`_resetTapped`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L437-L479)),
and the setter turns that into `persist[ATTR_OPTIONS] = {}`
([`app.py`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/app.py#L449-L452)).
That clears overrides; it does not shrink what the operator sees, since the defaults reappear.

A second-order effect worth knowing: the UI submits *the entire options object it is displaying*, not
a diff
([`_saveTapped`](https://github.com/home-assistant/frontend/blob/f71a938d023065aa6f4b7254c703ef2cde5516f5/src/panels/config/apps/app-view/config/supervisor-app-config.ts#L482-L515)).
So the first time an operator saves anything, every value they can see — including untouched defaults
— is copied into their persisted dict and pinned there. From that point on, changing a default in a
new add-on release has **no effect** on that operator; the pinned copy wins the merge. Only a key
they never had (added to `options:` after their last save) picks up the new default.

**Confidence: high** for the merge and reset behaviour (direct code). **Medium** for the "first save
pins every default" consequence — it follows necessarily from the code paths above, but was not
observed on a live instance.

---

## Implications for this add-on

1. **The pinning effect (§4) is the sharpest practical finding.** Changing a value in `blocky/config.yaml`'s
   `options:` block only reaches operators who have never pressed Save. For anyone else it is a no-op.
   Behaviour changes that must reach existing users belong in the template, not in a changed default.
2. **ADR-0005 stands as written.** Retaining a deprecated key in `schema:` is the correct and only
   lever. Removing it deletes the operator's value the next time they touch the config page — silently,
   with only a Supervisor log line.
3. **ADR-0005 also requires the key to stay in `options:`, and that is load-bearing for a second
   reason** the ADR does not spell out: a key present in `schema:` but absent from `options:` is
   hidden from the default form view (§1), so a deprecated key kept only in `schema:` would be
   invisible to operators who need to migrate off it.
4. **Schema requiredness is not a validation strategy.** Required means non-null, not non-empty (§2).
   The guards in ADR-0002 are not belt-and-braces; they are the only check that `upstreams.groups` is
   non-empty.
5. **The render harness's fixture merge matches HA's semantics** — dicts recurse, lists replace
   (`scripts/render-test/run.mjs`, `deepMerge`) — which is the same rule as `_OPTIONS_MERGER`. It does
   *not* replicate HA's schema filtering, which ADR-0005 records as a deliberate rejection.
6. **Nothing contradicts `CONTEXT.md`.** The one refinement is timing: the "silent drop" is a filter
   applied at read/write, not a destructive migration at update — the persisted value lingers in the
   Supervisor's store until the operator's next save.

## Open questions

- Whether `humanize_error` renders a nested list-element failure with a usable path (e.g. pointing at
  `upstreams.groups[1]`) or only the Supervisor's own message string. Settling this needs a live
  instance with a deliberately broken group entry; the code shows only that the message is passed
  through `humanize_error(self.options, ex)`.
- Whether backup restore takes a different path for user options.
  [`AppsData.restore`](https://github.com/home-assistant/supervisor/blob/3dea234189bc9fc910729fa502be2e1024462103/supervisor/apps/data.py#L62-L70)
  replaces the user dict wholesale from the backup without schema filtering, which suggests a restore
  can reintroduce keys the current schema no longer has — they would then be filtered at the next
  `write_options`. Not traced end to end.
