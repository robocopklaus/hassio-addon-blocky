# What Blocky v0.34.0 exposes about upstream resolver health

Primary-source research into whether Blocky, at the version this add-on pins, publishes any signal
that reflects **whether upstream DNS resolution actually works** — and whether such a signal could be
consumed by the add-on manifest's `watchdog` field, which the Supervisor polls with a plain HTTP GET.

Written to settle [#313](https://github.com/robocopklaus/hassio-addon-blocky/issues/313), which asked
for independent verification of the four claims [PR #317](https://github.com/robocopklaus/hassio-addon-blocky/pull/317)
used to justify shipping an active polling probe instead of repointing the watchdog.

Everything below is read from the pinned release's source, not from documentation prose, except
where the upstream docs are cited directly.

## Sources and how to read the links

All Blocky links are permalinks to tag
[`v0.34.0`](https://github.com/0xERR0R/blocky/tree/91a8f4437e983c840874aec4aded47fd90bd6ddf)
(commit `91a8f44`, 2026-07-27) — the version pinned by `BLOCKY_VERSION` in `blocky/Dockerfile:14`.

Add-on links are to this repository at the time of writing.

---

## 0. The answer, in one paragraph

**The claims hold, with one correction to how they are worded.** Blocky v0.34.0 serves exactly seven
REST operations plus a DoH endpoint, a docs/asset set, a profiler, and an optional metrics endpoint.
Of everything reachable by GET, **nothing changes its HTTP status, or any field of its body, when
every upstream is dead**. The one HTTP surface that returns a non-2xx status on total upstream
failure is `POST /api/query`, and the Supervisor watchdog cannot issue a POST. The correction: #317
says `/api/query` is "the only endpoint that actually resolves" — that is not true. `GET /dns-query`
(DoH) also runs the full resolver chain, and it *is* a GET. But RFC 8484 requires a DoH server to
answer **HTTP 200** and carry the failure in the DNS RCODE inside the binary body, and Blocky
implements exactly that, so it is unreadable by a status-code watchdog. The *mechanism* conclusion in
#317 is therefore unaffected; only its reasoning needs this one endpoint added.

---

## 1. The complete HTTP surface at v0.34.0

Everything is mounted on one `chi` router, built by
[`createHTTPRouter`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L195-L215),
with the DoH routes added by the caller
([`server.go:196-197`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server.go#L196-L197)).
That single router is served on **every** configured HTTP and HTTPS port — there is no separate
"API port" versus "DNS port" split at the HTTP layer. The add-on renders `ports.http: [4000]`
(`blocky/rootfs/usr/share/tempio/blocky.gtpl:410-412`), so all of the following are reachable at
`http://127.0.0.1:4000`:

| Path | Method | Source | Moves when upstreams die? |
|---|---|---|---|
| `/api/blocking/status` | GET | [`api_server.gen.go:26-28`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_server.gen.go#L26-L28) | **No** |
| `/api/blocking/enable` | GET | same | No (and mutates state) |
| `/api/blocking/disable` | GET | same | No (and mutates state) |
| `/api/stats` | GET | same | Only if statistics enabled; see §3 |
| `/api/cache/flush` | POST | same | No |
| `/api/lists/refresh` | POST | same | No (list downloads, not resolution) |
| `/api/query` | **POST** | same | **Yes — 500.** See §4 |
| `/dns-query` (`dohPath`) | GET **and** POST | [`registerDoHEndpoints`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L67-L75) | Body only, never status. See §5 |
| `/metrics` | GET | [`metrics.Start`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/metrics/metrics.go#L21-L28) | Only if Prometheus enabled; see §6 |
| `/docs/openapi.yaml`, `/docs/config.schema.json` | GET | [`configureDocsHandler`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L215-L227) | No (static) |
| `/static/*`, `/robots.txt`, `/` | GET | [`server_endpoints.go:229-243`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L229-L243) | No (static) |
| `/debug/*` | GET | [`configureDebugHandler`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L303-L305) | No (Go pprof) |

The REST operations are the generated
[`ServerInterface`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_server.gen.go#L19-L41)
mounted under the `/api` base path
([`RegisterOpenAPIEndpoints`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_interface_impl.go#L65-L69)).
That list is exhaustive: it is code-generated from the OpenAPI spec, so no hand-written REST route
can exist outside it.

## 2. `/api/blocking/status` — confirmed, reports blocking only

[`BlockingStatus`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_interface_impl.go#L137-L154)
reads `i.control.BlockingStatus()` and returns `Enabled`, optionally `AutoEnableInSec` and
`DisabledGroups`. It has exactly one return path — `BlockingStatus200JSONResponse` — so it is
**structurally incapable of a non-2xx status**, and none of its three fields has any relationship to
upstream reachability. **Claim confirmed.**

This is the URL the add-on's manifest currently polls (`blocky/config.yaml:10`).

## 3. `/api/stats` — confirmed, and worse than "needs enabling"

[`GetStats`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_interface_impl.go#L205-L212)
returns `503 "statistics are disabled"` when the stats provider is absent or off. `statistics.enable`
defaults to `false`
([`config/statistics.go:6-9`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/config/statistics.go#L6-L9))
and the add-on's template never emits a `statistics:` block at all, so on this add-on the endpoint is
**permanently 503**. Pointing the watchdog at it would mark every install unhealthy forever.

Even with statistics enabled it would not work. The summary
([`toAPIStats`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_interface_impl.go#L214-L243))
carries an `Errors` count, aggregated by
[`curatedSummary`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/stats/collector.go#L438-L463)
from chain-level resolver failures. That is a **rolling counter, not a verdict**: reading it once
tells you nothing, since a consumer must diff two samples and pick a threshold. And it is
**traffic-derived** — if no client queries during the outage, `Errors` does not move at all. The
status code stays 200 throughout. **Claim confirmed, and strengthened.**

## 4. `POST /api/query` — confirmed as the only truthful REST signal, and confirmed POST-only

[`Query`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_interface_impl.go#L167-L195)
calls `i.querier.Query(...)`, which is
[`Server.Query`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L184-L192)
→ `Server.resolve`. On total upstream failure the resolver chain returns an error that is *not* an
`UpstreamServerError`, so `resolve` returns
[`query resolution failed: %w`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server.go#L843-L853)
rather than a response. The generated strict handler routes that to the default
`ResponseErrorHandlerFunc`, which is
[`http.StatusInternalServerError`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_server.gen.go#L568-L577).

So this endpoint genuinely does return **500 when upstream resolution is broken** — and it is
registered as POST only ([`api_server.gen.go:35-37`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/api/api_server.gen.go#L35-L37)),
with no GET variant anywhere in the generated router. **Claim confirmed.**

Worth noting for #317's classifier: the `UpstreamServerError` branch converts an upstream's *error
answer* into a normal `RESOLVED` response. That is correct — an upstream that answers SERVFAIL is
reachable, and reachability is what is being measured.

## 5. Correction: `GET /dns-query` also resolves — but its status is always 200

#317 states that `/api/query` "is the only endpoint that actually resolves". It is not.
[`registerDoHEndpoints`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L67-L75)
registers `GET` handlers for `dohPath` (default `/dns-query`,
[`config.go:352`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/config/config.go#L352)),
on the same router as the REST API — therefore on port 4000 in this add-on. A base64url-encoded DNS
message in the `dns` query parameter runs the complete resolver chain, upstreams included.

It is still unusable as a watchdog target, for a reason of protocol rather than availability. On a
resolution failure,
[`handleReq`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server.go#L797-L812)
builds a DNS message with RCODE `SERVFAIL` and hands it to
[`httpMsgWriter.WriteMsg`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server_endpoints.go#L146-L172),
which unconditionally writes `http.StatusOK` — with an explicit code comment citing
[RFC 8484 §4.2.1](https://www.rfc-editor.org/rfc/rfc8484#section-4.2.1), which requires it. The
verdict exists, but it is four bits inside a packed binary body. A Supervisor watchdog that inspects
only the HTTP status cannot read it, and neither can anything that does not parse wire-format DNS.

**Net effect on #317: none.** The claim that mattered — no GET returns non-2xx on upstream failure —
survives. But the supporting sentence is inaccurate as written and should say *"the only endpoint
whose HTTP status reflects resolution"* rather than *"the only endpoint that actually resolves"*.

## 6. Prometheus — no per-upstream dimension exists at all

`prometheus.enable` defaults to `false`
([`config/metrics.go:6-11`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/config/metrics.go#L6-L11)),
and when it is off the route is **not registered** — `/metrics` 404s rather than returning an empty
body. The add-on's own default is also `false` (`blocky/config.yaml:113-115`).

With it enabled, the full metric inventory is:

- `blocky_build_info`, `blocky_blocking_enabled`, `blocky_denylist_cache_entries`,
  `blocky_allowlist_cache_entries`, `blocky_last_list_group_refresh_timestamp_seconds`,
  `blocky_failed_downloads_total`, `blocky_prefetches_total`, `blocky_prefetch_hits_total`,
  `blocky_cache_entries`, `blocky_prefetch_domain_name_cache_entries`
  ([`metrics_event_publisher.go`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/metrics/metrics_event_publisher.go))
- `blocky_query_total{client,type}`, `blocky_error_total`,
  `blocky_request_duration_seconds{response_type}`,
  `blocky_response_total{reason,response_code,response_type}`
  ([`metrics_resolver.go:108-145`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/resolver/metrics_resolver.go#L108-L145))

Grepping `metrics/` for "upstream" returns **nothing**. There is no per-upstream counter, gauge, or
`up`-style boolean. `blocky_error_total` is a bare `prometheus.Counter` with **no labels at all**, so
it cannot even distinguish an upstream failure from any other chain error. Like `/api/stats`, every
one of these is a cumulative time series requiring two samples and a threshold, served with HTTP 200
regardless of value — the opposite of a boolean verdict. **Claim confirmed.**

## 7. `init_strategy`'s outcome is observable only as a log line

The add-on's `upstreams.init_strategy` renders to Blocky's `upstreams.init.strategy`
(`blocky.gtpl:30-36`), defaulting to `blocking`
([`config.go:522-525`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/config/config.go#L522-L525)).
[`InitStrategy.Do`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/config/config.go#L119-L144)
runs the init function and, unless the strategy is `failOnError`, **passes the error to a logger and
returns nil**. Both call sites for upstreams do exactly that and nothing else:

- [`NewUpstreamResolver`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/resolver/upstream_resolver.go#L478-L495):
  `logger.WithError(err).Warn("initial resolver test failed")`
- [`resolver.go:271-283`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/resolver/resolver.go#L271-L283):
  `logger.WithError(err).Error("upstream verification error, will continue to use bootstrap DNS")`

No flag is stored, no metric is incremented, no API field changes. The result of the startup test is
**write-only to the log**, exactly as [#310](https://github.com/robocopklaus/hassio-addon-blocky/issues/310)
suspected. It is also a one-shot: nothing re-runs it, so it says nothing about an upstream that dies
later.

There is per-upstream health state at runtime — `upstreamResolverStatus.lastErrorTime`
([`parallel_best_resolver.go:37-50`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/resolver/parallel_best_resolver.go#L37-L50)) —
but the type is unexported and the field is consumed only by weighted upstream selection. It reaches
no API, no metric, and no log. **The data Blocky needs to answer "are my upstreams alive" exists
inside the process and has no surface.**

## 8. The trap: `healthcheck.blocky` is liveness, not health

Blocky registers a dedicated DNS name that bypasses the resolver chain entirely:
[`OnHealthCheck`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server.go#L887-L895)
builds a reply, sets `RcodeSuccess`, and writes it. It never touches an upstream. It is wired to the
name `healthcheck.blocky`
([`registerDNSHandlers`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/server/server.go#L574-L585)),
which is what `blocky healthcheck`
([`cmd/healthcheck.go:38`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/cmd/healthcheck.go#L38))
queries and what Blocky's own container `HEALTHCHECK`
([`Dockerfile:82`](https://github.com/0xERR0R/blocky/blob/91a8f4437e983c840874aec4aded47fd90bd6ddf/Dockerfile#L82))
runs — and what [the upstream docs recommend](https://0xerr0r.github.io/blocky/latest/configuration/#healthcheck)
for Docker Compose.

**Blocky's own upstream health check reports healthy with every upstream dead.** Anything that reuses
it — including a naive DNS probe that picks the obvious name — inherits that blindness. This is the
independent justification for #317 using a *random* name under a nonexistent TLD: a fixed name can be
answered from cache, and this particular fixed name is answered by a handler that was built never to
resolve anything.

---

## What this means for the add-on

1. **All four of #317's load-bearing claims are confirmed.** No GET-able endpoint at v0.34.0 changes
   its HTTP status when upstream resolution breaks, so the `watchdog` field cannot be repointed at a
   truthful signal. The mechanism decision stands.
2. **One sentence in #317 is inaccurate and should be corrected on the record:** `GET /dns-query`
   also resolves. It is excluded by RFC 8484's unconditional HTTP 200, not by absence.
3. **Every passive signal is traffic-derived.** `/api/stats` `Errors` and every `blocky_*` counter
   move only when a client queries. A quiet household at 3 a.m. produces the same numbers as a
   healthy one. Only an **active probe** generates the traffic whose failure is the signal — which is
   what #317 ships.
4. **The information exists but has no exit.** `lastErrorTime` per upstream is tracked and used
   internally. An upstream feature request exposing it — as a labelled `blocky_upstream_up` gauge, or
   a field on `/api/blocking/status` — would make a truthful watchdog possible in a future version.
   That is a Blocky change, not an add-on change; worth revisiting at the next `BLOCKY_VERSION` bump
   (see `docs/agents/blocky-bump-review.md`).
5. **`healthcheck.blocky` must never be used as this add-on's probe name**, and the reason is
   non-obvious enough to be worth stating wherever the probe is documented.

## Open questions

- Whether the Supervisor watchdog checks only TCP reachability or also the HTTP status code — this
  determines whether even a *hypothetical* non-2xx endpoint would be read. Tracked separately as
  [#314](https://github.com/robocopklaus/hassio-addon-blocky/issues/314); not needed to settle #313,
  because no such endpoint exists either way.
- Whether Blocky's `bootstrapDns` masks upstream death for any code path other than list downloads.
  `resolver.go:274` logs "will continue to use bootstrap DNS" on verification failure, which suggests
  the bootstrap resolver stays in play; not traced to the point of knowing whether it can ever serve
  a client query.
