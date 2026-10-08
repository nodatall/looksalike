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

The probe retained its four simulated SerpApi allowance units. It did not refund or reset usage. The cache entry, four usage units and released lease survived a process restart and a new deployment. Before live enable, Rails verified both provider keys, the removed hook/token, and the normal search/cache methods. The probe files never entered the source repository or Docker image. Its isolated cache entry cannot match a normal photo fingerprint. Live search was then enabled on the normal app. A previously unseen black molded-seat chair photo by [Eugene Chystiakov](https://unsplash.com/photos/3neSwyntbQ8), discovered through the regular free [wooden-chair entries](https://unsplash.com/s/photos/wooden-chair) and used under the [Unsplash License](https://unsplash.com/license), returned six current cards. The individual photo page was inaccessible to the research tool; the search entry identified the creator and exact download. Its source SHA-256 was frozen before dispatch. The original photo is not bundled into this repository.

The real search used one upload, two SerpApi searches and one Venice call with `qwen3-vl-235b-a22b`. Server stages took 0.24 seconds for upload, 2.56 for Lens, 4.02 for Venice, 3.25 for eBay and 0.03 for local checks. Browser results appeared in 10.68 seconds. Lens lacked a usable phrase; Venice supplied `black molded seat wooden legs chair`. All six cards had explicit US location and valid eBay item links. Only two closely matched the molded-seat design; the other cards shared broader category, material or color traits. This is a working-route smoke check, not a new quality pass. The frozen four-of-five comparison remains unchanged.

Reload preserved the reference and open explanation with zero new calls. The 390-pixel mobile result view had no horizontal overflow. The production database retained six SerpApi units (four simulated, two real), one Venice reservation and both cache entries across the subsequent restart. The live lease was released; the temporary transport call count stayed at six. The real attempt conservatively reserved $0.03 for Venice; this is not a verified bill. Hosted timings include network overhead and are separate from local or paid-search quality evidence.

After the live service restart, the public page still restored completed results with no requests. Search again cleared that view, and choosing the bundled example again prepared its preview and enabled Find similar items. No extra paid submission was needed for that repeat check. The account check after the public smoke reported 193 SerpApi searches remaining.
