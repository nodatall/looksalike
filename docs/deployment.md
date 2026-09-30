# Deployment verification

The [Railway app](https://web-production-1e238.up.railway.app/) uses one Rails/Puma process and a volume at `/app/storage`. The public [source branch](https://github.com/nodatall/looksalike/tree/deliver/looksalike-demo) passed [GitHub checks](https://github.com/nodatall/looksalike/actions/runs/36792146985).

## Hosted checks on September 30, 2026

With live search disabled, the public page and `/up` returned successfully. Rails verified a real writable volume and the configured SQLite database. The unauthenticated search returned the unavailable-search message with zero provider attempts.

A temporary authenticated probe replaced provider transport with recorded responses and blocked all outbound HTTP. It used the real upload validator, NDJSON controller, lease, reservations, filtering and deadline. It used a separate cache fingerprint namespace so its simulated results cannot be used by the normal app. No paid provider calls ran.

| Check | Observed result |
| --- | --- |
| Search longer than 30 seconds | Success in 34.45 seconds |
| First streamed stage | 0.56 seconds |
| Health check during search | 0.13 seconds |
| Second search while busy | Busy response in 0.55 seconds; zero attempts |
| Cached repeat | 0.25 seconds; zero new calls; original retrieval date |
| Server deadline | Clear timeout in 55.31 seconds |
| Health check during timeout test | 0.13 seconds |

The probe retained its four simulated SerpApi allowance units. It did not refund or reset usage. Persistence, probe removal and the final real-photo check are still pending. Hosted timings include network overhead and are separate from local or paid-search quality evidence.
