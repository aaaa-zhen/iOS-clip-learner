# Clip Learner iOS — v1 Design

**Date:** 2026-05-29
**Status:** Approved (pending written-spec review)

## Overview

A native iOS app (SwiftUI) that lets users learn English from YouTube clips by
**consuming content already produced by the existing Clip Learner web backend**.
The app is a thin client: all heavy work (yt-dlp download, Whisper transcription,
LLM humor/slang analysis) stays on the existing hosted SvelteKit server. The iOS
app authenticates with the same accounts, browses episodes the user already
generated on the web, plays the YouTube clip in sync with the transcript, looks
up words, and saves them to the shared notebook.

The web app is at `../clip-learner` (sibling project). The iOS Xcode project is
already scaffolded at `iOScliplearner/cliplearn/` (default SwiftUI template:
`cliplearnApp.swift`, `ContentView.swift`, test targets).

## Goals (v1)

1. **Log in** with an existing Clip Learner account (shared data with the web app).
2. **Browse** episodes the user already generated (no creation on mobile in v1).
3. **Study view (core):** play the YouTube clip with the transcript synced —
   current line auto-highlights and auto-scrolls; tapping a line seeks the video.
4. **Word lookup:** tap/select a word → get definition → save to notebook.
5. **Notebook:** view and manage saved vocabulary.

## Non-Goals (explicitly out of scope for v1)

- Creating episodes on mobile (pasting a URL → server processing).
- Offline downloaded video (mp4 from `/media`). v1 is **YouTube online playback only**.
- Quiz generation, Article Reader, settings page, guest mode.
- Android, iPad-optimized layout, App Store submission (TestFlight first).

## Architecture

```
┌─────────────────┐      JSON over HTTPS              ┌──────────────────────┐
│  iOS App         │  ──────────────────────────────▶ │  SvelteKit backend     │
│  (SwiftUI)       │   clip_session cookie (auto)      │  (existing hosted srv) │
│                  │  ◀────────────────────────────── │  yt-dlp/Whisper/LLM    │
└─────────────────┘                                   └──────────────────────┘
```

- iOS is a **pure client**. No on-device transcription or analysis.
- Network base URL is configurable (build setting / constant) so we can point at
  the hosted server or a local dev server.

### Authentication: cookie reuse (no backend auth changes)

The backend uses a `clip_session` **httpOnly** cookie (`sameSite: lax`,
`secure` in production), created by `POST /api/auth`. The iOS app relies on
`URLSession`'s shared `HTTPCookieStorage`, which automatically stores the
`Set-Cookie` from the login response and re-sends it on subsequent requests.
**No change to the backend's auth logic is required.**

Implications and requirements:
- The hosted server **must be HTTPS** (the cookie is `secure` in production, so it
  will not be stored/sent over plain HTTP). This is also required for App Transport
  Security.
- The app must **log in before** calling protected endpoints. The web app
  auto-creates guest users for *browser page* requests via `hooks.server.ts`, but
  the JSON API routes assume an authenticated user (e.g. `/api/explain` uses
  `locals.user!.id`). v1 does not use guest mode.
- Session lasts 30 days. On a `401`, the app routes back to the login screen.

## Backend changes (committed to the `clip-learner` repo)

The web delivers episode data through SvelteKit `+page.server.ts` load functions,
not JSON endpoints. Two small JSON endpoints are needed. Both reuse existing SQL
and must scope by `locals.user.id`, returning `401` when there is no user.

### 1. `GET /api/episodes` — episode list

Mirrors `src/routes/+page.server.ts`. Returns the user's episodes:

```jsonc
// 200
[
  {
    "id": "string",
    "video_id": "string|null",
    "title": "string",
    "url": "string",
    "thumbnail": "string|null",
    "duration": 123,            // seconds, or null
    "status": "ready|pending|fetching_audio|transcribing|analyzing|error|...",
    "created_at": "ISO-ish string",
    "studied_at": "string|null",
    "pinned_at": "string|null"
  }
]
```

Ordering matches the web: pinned first, then newest first. v1 client primarily
shows `status == "ready"` episodes but receives all.

### 2. `GET /api/episodes/[id]` — episode detail

Mirrors `src/routes/episode/[id]/+page.server.ts`. Returns everything the study
view needs, scoped to the owner (404 if not found for this user). Also updates
`studied_at` (same side effect as the web load):

```jsonc
// 200
{
  "episode":     { /* Episode, as above */ },
  "segments":    [ { "id": 1, "episode_id": "…", "index_num": 0,
                     "start_time": 0.0, "end_time": 4.2, "text": "…" } ],
  "annotations": [ { "id": 1, "episode_id": "…", "segment_id": 1,
                     "category": "wordplay", "explanation": "…",
                     "excerpt": "…", "start_pos": 0, "end_pos": 5 } ],
  "scenes":      [ { "id": 1, "episode_id": "…", "start_seg": 0, "end_seg": 8,
                     "title": "…", "explanation": "…",
                     "humor_types": ["slang","idiom"] } ],
  "vocabulary":  [ /* VocabEntry for this episode */ ]
}
```

### Existing endpoints reused as-is (no change)

| Endpoint | Method | Request → Response |
|---|---|---|
| `/api/auth` | POST | `{action:"login"\|"signup", username, password}` → `{ok:true}` + sets `clip_session`; errors `{error}` with 400/429 |
| `/api/explain` | POST | word lookup `{word, context}` → `{definition}`; **or** line help `{segmentId}` → `{explanation}`. Rate-limited 30/min/user |
| `/api/notebook` | GET | → `[VocabEntry + episode_title + episode_url]` |
| `/api/notebook` | POST | `{word, definition, example, phonetic, source_text, episode_id, source_time, category}` → `{id}`; duplicate → `409 {id, duplicate:true}` |
| `/api/notebook` | PATCH | `{id, confidence:0..5}` → `{success, confidence}` |
| `/api/notebook` | DELETE | `{id}` → `{success}` |

## iOS app structure (SwiftUI)

| Unit | Responsibility | Depends on |
|---|---|---|
| `APIClient` | One typed wrapper over `URLSession`: base URL, JSON encode/decode, cookie reuse, maps non-2xx → typed errors (incl. `401 → unauthenticated`). | Foundation |
| `Models` | `Codable` structs mirroring the backend: `Episode`, `Segment`, `HumorAnnotation`, `SceneBreakdown`, `VocabEntry`. | — |
| `AuthStore` | Observable login state; calls `/api/auth`; drives root navigation (logged-in vs login screen). | APIClient |
| `AuthView` | Login / sign-up form. | AuthStore |
| `EpisodeListView` | Lists `ready` episodes via `GET /api/episodes`; pull-to-refresh; tap → StudyView. | APIClient, Models |
| `StudyView` | **Core.** YouTubePlayerKit player + transcript list; observes playback time → highlight + auto-scroll; tap line → seek; tap word → WordLookup. | YouTubePlayerKit, APIClient |
| `WordLookupSheet` | Given a word + surrounding context, calls `/api/explain`, shows definition, "Save to notebook" → `POST /api/notebook`. | APIClient |
| `NotebookView` | Lists `GET /api/notebook`; delete / mark confidence. | APIClient |

Each unit has one job and a clear interface; views depend on `APIClient`/stores,
not on each other's internals.

### Third-party dependency

- **YouTubePlayerKit** (SwiftUI, ToS-compliant via official YouTube iFrame API),
  added via Swift Package Manager. Provides `YouTubePlayerView`, seeking, and a
  playback-time publisher used to drive transcript highlighting. Actively
  maintained (v2.0.5, Nov 2025).

## Core interaction: StudyView ("get the video right")

1. Build a `YouTubePlayer` from the episode's `video_id` (or parse from `url`).
2. Subscribe to the player's current-time updates.
3. Map current time → the `Segment` whose `[start_time, end_time)` contains it;
   highlight that line and auto-scroll it into view (only when the user isn't
   manually scrolling).
4. Tapping a transcript line calls `player.seek(to: segment.start_time)`.
5. Tapping/long-pressing a word opens `WordLookupSheet`; on save, the word is
   posted to the notebook with `episode_id` and `source_time` = current segment
   start. Duplicates (`409`) surface a friendly "already saved" message.
6. Segments that have humor annotations show a small badge; tapping reveals the
   stored explanation (no LLM call — already analyzed server-side).

## Data flow

```
Launch → AuthStore checks session (a cheap GET; 401 → AuthView)
  → EpisodeListView: GET /api/episodes
    → tap → StudyView: GET /api/episodes/{id}
        → YouTube player + transcript sync
        → tap word → POST /api/explain → (optional) POST /api/notebook
  → NotebookView: GET /api/notebook (+ PATCH/DELETE)
```

## Error handling

- **Network / non-2xx:** `APIClient` throws a typed `APIError`; views show an
  inline retry state. No silent failures.
- **401 Unauthorized:** clear session state → route to `AuthView`.
- **429 (rate limit on explain/auth):** show "slow down" message, allow retry.
- **Empty states:** no episodes / empty notebook get explicit empty-state UI.
- **Video unavailable:** if the YouTube clip can't load (region/removed), show a
  message in place of the player but keep the transcript usable.

## Testing

No heavy test harness in v1 (matches the web project's pragmatic stance), but:
- Unit tests for `Models` decoding against captured JSON samples from each
  endpoint (guards the iOS/backend contract).
- Unit test for the time → segment mapping logic (pure function, no UI).
- Manual TestFlight pass for the end-to-end study flow.

## Distribution

- **TestFlight first** for friends (no App Store review wait).
- App Store submission considered later once stable. Using YouTubePlayerKit's
  ToS-compliant iFrame approach keeps that path open.

## Build order (high level — detailed plan to follow)

1. Backend: add `GET /api/episodes` and `GET /api/episodes/[id]`; verify with curl.
2. iOS: `APIClient` + `Models` + decoding tests against captured JSON.
3. iOS: `AuthStore` + `AuthView`; confirm cookie persists across requests.
4. iOS: `EpisodeListView`.
5. iOS: `StudyView` — YouTubePlayerKit integration + transcript sync + seek.
6. iOS: `WordLookupSheet` + notebook save.
7. iOS: `NotebookView`.
8. TestFlight build.

## Open questions / risks

- **HTTPS required** for the `secure` session cookie and ATS — confirm the hosted
  server serves HTTPS with a valid cert.
- **Cookie domain/redirects:** if the server redirects (e.g. apex ↔ www), the
  cookie domain must match what `URLSession` sends; pin the base URL to the exact
  host that sets the cookie.
- **`video_id` source:** prefer the stored `video_id`; fall back to parsing the
  YouTube `url` if older rows lack it.
- **Sign-up guest migration:** the web `/api/auth` signup path has guest-upgrade
  logic; from iOS (no guest) it takes the plain create-account branch — fine, but
  worth a quick verification.
```
