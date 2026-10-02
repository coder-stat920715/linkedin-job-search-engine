# Testing Guide: Job Search & Candidate Matching Engine

Files: `job-search-engine.postman_collection.json` (44 requests with automated assertions), `job-search-local.postman_environment.json`.

> The expected values below are derived from the seed data and scoring formulas in the code. Run the unit tests (Step 2) first, and tell me about any mismatch.

## 1. Prerequisites
| Tool | Version | Check |
|---|---|---|
| JDK | 21 | `java -version` |
| Maven | 3.9+ | `mvn -v` |
| Postman (or Newman) | any recent | optional: `npm i -g newman` |
| Docker | optional, only for Redis/Kafka | `docker -v` |

## 2. Run the unit tests
```bash
unzip linkedin-job-search-engine.zip && cd linkedin-job-search-engine
mvn clean test
```
Expected: `BUILD SUCCESS`, 5 test classes (parser, L1 retrieval, scorers, L2 engine, pipeline, InMail observer) with 0 failures. Fix any compile error before continuing.

## 3. Start the application (pick one mode)

**Mode A: no infrastructure (easiest; recommended for first run)**
```bash
mvn spring-boot:run -Dspring-boot.run.arguments="--app.kafka.listener-enabled=false --app.kafka.publish-enabled=false"
```
Uses in-memory H2 and dispatches engagement events in-process. Redis is not needed: the first Redis failure logs a warning and the app falls back to SQL for 30 s at a time.

**Mode B: full stack (Redis + Kafka)**
```bash
docker run -d --name redis -p 6379:6379 redis:7
docker run -d --name kafka -p 9092:9092 apache/kafka:3.8.0
mvn spring-boot:run
```
Engagement events now flow through Kafka asynchronously, so wait 2-3 seconds between a POST event and the next GET.

Startup is OK when you see: `L1 index rebuilt with 0 candidates` followed by `Seeded 8 demo candidates`.

Useful URLs: Swagger UI `http://localhost:8080/swagger-ui.html`, OpenAPI `http://localhost:8080/v3/api-docs`, H2 console `http://localhost:8080/h2-console` (JDBC URL `jdbc:h2:mem:jobsearch`, user `sa`, empty password).

## 4. Seed data (ids are assigned in this order on a fresh start)
| Id | Name | Company | Title | City | Open | Immediate | Skills |
|---|---|---|---|---|---|---|---|
| 1 | Priya Nair | JPMorgan | Talent Acquisition Specialist | Mumbai | yes | yes | Java, Recruiting, Sourcing |
| 2 | Rahul Mehta | JPMorgan | Recruiter | Mumbai | yes | no (30d) | Java, Spring Boot, Recruiting |
| 3 | Ananya Rao | JPMorgan | Recruiter | Bengaluru | no | no (60d) | Java, Talent Acquisition |
| 4 | Karan Shah | Google | Software Engineer | Bengaluru | yes | yes | Java, Spring Boot, Microservices, Kafka |
| 5 | Sneha Iyer | Infosys | Senior Developer | Pune | yes | no (45d) | Java, Hibernate, SQL |
| 6 | Vikram Singh | Amazon | SDE II | Hyderabad | no | no (90d) | Spring Boot, Rate Limiting, Redis, Docker |
| 7 | Meera Joshi | Flipkart | Data Scientist | Bengaluru | yes | yes | Python, Pandas, SQL |
| 8 | Arjun Das | TCS | Developer | Mumbai | yes | yes | JavaScript, React, TypeScript, Java |

**Restart the app before re-running the collection if you want the exact seed ids** (data is in-memory).

## 5. Test with Postman
1. Postman -> **Import** -> select both JSON files.
2. Top-right environment dropdown -> choose **Job Search - Local**.
3. Click the collection -> **Run** -> keep the folder order -> **Run**. All folders are order-dependent (folder 3 creates a candidate, folder 4 uses candidate 1, folder 5 creates a job).
4. Every request has a **Test Results** tab. All should be green. Command line alternative:
```bash
newman run job-search-engine.postman_collection.json -e job-search-local.postman_environment.json
```

## 6. Manual step-by-step (what each folder proves)

### Step 1. Smoke
`GET /v3/api-docs` -> 200 and the response has header `X-Trace-Id`. `GET /api/v1/candidates/1` -> `Priya Nair`.

### Step 2. L1 Boolean retrieval
`POST /api/v1/search/candidates`
```json
{ "query": "\"JPMorgan\" AND (\"Talent Acquisition\" OR \"Recruiter\") AND \"Java\" AND \"Immediate Joiner\"", "requiredSkills": ["Java"] }
```
Expected: `l1Matches: 1`, a single result `Priya Nair`, and `scoreBreakdown` with `skillMatch`, `inMailResponse`, `openToWork`, `freshness`.

| Query | Expected names |
|---|---|
| same without `AND "Immediate Joiner"` | Priya, Rahul, Ananya in that order |
| `"JPMorgan" AND NOT "Immediate Joiner"` | Rahul, Ananya |
| `java recruiter` (implicit AND) | Rahul, Ananya |
| `"Google" OR "Amazon" AND "Docker"` (AND before OR) | Karan, Vikram |
| `java` with `pageSize: 2` | `l1Matches: 6`, 2 results |
| `java` + `location: "Mumbai"` + `openToWorkOnly: true` | Priya, Rahul, Arjun (`afterFilters: 3`) |
| add `maxNoticePeriodDays: 10` | Priya, Arjun |
| `"COBOL"` | 200 with empty results |

Error cases: `"JPMorgan" AND (` -> **400** "Invalid Boolean query"; `"Java AND Spring` -> 400 "Unterminated"; `""` -> 400 "Validation failed"; `pageSize: 500` -> 400.

### Step 3. L2 reranking
Query `"Spring Boot"` with `requiredSkills: ["Java"]`: Karan and Rahul get `skillMatch = 1.0`, Vikram (no Java, has Spring Boot) gets `(0.9 x 0.8 + 1.0) / 2 = 0.86`. This proves the companion matrix. Ananya (not open to work) always shows `openToWork = 0.1`.

### Step 4. Ingestion and index freshness
1. `POST /api/v1/candidates` with company `AcmeX` and skills Rust/Kafka -> 201.
2. Search `"acmex" AND rust` -> 1 hit (indexed immediately after commit).
3. `PUT /api/v1/candidates/{id}` changing company to `GlobexX` -> search `"acmex"` -> 0 hits, `"globexx"` -> 1 hit.

### Step 5. Feedback loop (the key L2 behaviour)
1. `GET /api/v1/candidates/1/features` -> note counters (fresh start: all 0).
2. Search `"JPMorgan" AND "Talent Acquisition"` and note Priya's `inMailResponse` (about 0.34 on a fresh start).
3. `POST /api/v1/engagement/events` with `INMAIL_SENT`, `candidateId 1`, a unique `messageId`, `occurredAt` 3 hours ago -> **202**.
4. Same call with `INMAIL_RESPONDED`, same `messageId`, `occurredAt` 1 hour ago -> 202.
5. `GET .../features` -> `inMailsReceived: 1`, `inMailsResponded: 1`, `avgResponseHours: 2.0`.
6. Repeat step 4 -> counters do not change (idempotent).
7. Repeat the search -> Priya's `inMailResponse` rises to about 0.53.
8. `SESSION_ACTIVITY` then `PROFILE_VIEWED` events -> `sessionActivity` grows by 1.0 and 0.25.

### Step 6. Jobs
`POST /api/v1/jobs` (Java, Spring Boot, Microservices; Bengaluru) -> 201 with id. `GET /api/v1/jobs/{id}/matches?size=10` -> only Bengaluru candidates, Karan first, Ananya lower.

### Step 7. Admin
`POST /api/v1/admin/index/rebuild` -> `{"indexedCandidates": 8}` or more.

## 7. Verify through logs and the database
* Every log line carries the trace id: `INFO [pm-1760000000] ... Search <uuid> finished: l1=1, filtered=1, returned=1, tookMs=12`. Send your own `X-Trace-Id` header and find it in the logs and in error responses (`traceId`).
* H2 console queries:
```sql
SELECT * FROM candidate_feature_scores;
SELECT * FROM inmail_communications ORDER BY id DESC;
SELECT raw_query, result_count, took_ms FROM recruiter_searches ORDER BY id DESC;
```
* Redis (Mode B): `docker exec -it redis redis-cli GET cfs:1`.

## 8. Troubleshooting
| Symptom | Cause / fix |
|---|---|
| Seeded candidate test fails (`fullName` mismatch) | Data is not fresh; restart the app |
| Engagement GET shows no change (Mode B) | Kafka consumer not yet processed; wait 3 s and re-send the GET |
| `Connection refused` warnings for Kafka/Redis in logs | Expected in Mode A; use the two `--app.kafka...=false` flags |
| 500 on `/api/v1/engagement/events` with `INMAIL_*` and no `messageId` | `messageId` is required for InMail events |
| `UnsupportedClassVersionError` | JDK is older than 21 |
| Compile error | Please share the full Maven output so I can fix the code |
