# Clip Learner — iOS

A native SwiftUI app for learning English from YouTube clips. It's a **thin client**
for the existing [`clip-learner`](https://github.com/aaaa-zhen/clip-learner) SvelteKit
backend — all heavy work (yt-dlp download, Whisper transcription, LLM analysis) runs
on the server. The app authenticates with the same accounts and shows the episodes /
notebook you generate on the web.

## Run

```bash
cd cliplearn
open cliplearn.xcodeproj   # build & run (⌘R). Requires Xcode 26+, iOS 26 SDK.
```

`YouTubePlayerKit` is vendored as a **local Swift package** (`../YouTubePlayerKit-main`,
committed in this repo), so it builds straight after clone — no package fetch needed.

## Backend connection

The app talks to the backend over JSON. The base URL lives in
`cliplearn/cliplearn/APIClient.swift`:

```swift
enum APIConfig {
    static let localDev    = URL(string: "http://localhost:5174")!   // npm run dev
    static let production  = URL(string: "http://43.134.87.27")!     // the VPS
    static let baseURL = production   // ← flip to .localDev for local backend work
}
```

- Session uses the backend's `clip_session` cookie via `URLSession`'s shared cookie
  storage (auto-persisted). Login is **on-demand** (a sheet), not a launch wall.
- The VPS is currently plain **HTTP**, so the cookie is `secure:false` server-side and
  `Info.plist` has ATS exceptions for `localhost` + `43.134.87.27`. Once the VPS is on
  HTTPS, revert those and drop the exceptions.

## Structure (`cliplearn/cliplearn/`)

| File | Role |
|---|---|
| `APIClient.swift` | Typed wrapper over `URLSession`; episodes, detail, explain, notebook, auth, add/delete. |
| `AuthStore.swift` / `AuthView.swift` | Login state + on-demand login sheet. |
| `Episode.swift` / `Models.swift` | Codable models mirroring the backend. |
| `RootView.swift` | iOS 26 Liquid-Glass `TabView`: Home / Notebook / Profile. |
| `HomeView.swift` | Episode feed: list, swipe-delete, long-press category, filter chips, **+ add clip** with status polling. |
| `StudyLoaderView.swift` / `StudyView.swift` | Loads transcript, then the core study screen: YouTube player + immersive scrollable caption (active-word highlight), tap-word lookup popover, custom transport bar, save-line. |
| `WordLookupSheet.swift` | Word/phrase explanation popover (`/api/explain`, LLM). |
| `NotebookView.swift` | Synced vocabulary with search + category filter. |

## Backend endpoints used

`GET /api/episodes`, `GET|PATCH /api/episodes/[id]`, `POST /api/auth`,
`POST /api/explain`, `GET|POST|DELETE /api/notebook`, `POST|DELETE /api/process`,
`GET /api/episode/[id]/status`.

## Notes / TODO

- **HTTPS on the VPS** (domain + Let's Encrypt) → removes the cleartext-cookie risk.
- Background audio mode (would need the backend to retain audio + AVPlayer).
- Word-level highlight is approximate (per-line timestamps only); precise sync needs
  Whisper word timestamps stored server-side.
- `yt-dlp` on the VPS uses a synced `cookies.txt` to dodge YouTube's bot check.
