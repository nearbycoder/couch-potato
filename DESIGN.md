# Couch Potato — Design System

Couch Potato is a premium streaming companion. The look is **cinematic, confident and quiet**: artwork is the hero and the chrome recedes. Reference points: the Apple TV app, Letterboxd, Plex. No cartoon mascots in the UI, no emoji in labels, no tilted "sticker" cards, no hard offset shadows, no novelty fonts.

The same system is used by the Apple app (SwiftUI), the Android app (Jetpack Compose / Material 3) and the website.

## Color

Dark is the primary appearance; light is a first-class alternative. Both must look finished.

| Token | Dark | Light |
|---|---|---|
| `bg` | `#0C0C10` | `#F5F5F7` |
| `surface` | `#15151B` | `#FFFFFF` |
| `surfaceElevated` | `#1D1D25` | `#FFFFFF` + soft shadow |
| `hairline` | `rgba(255,255,255,0.08)` | `rgba(0,0,0,0.08)` |
| `textPrimary` | `#F5F5F7` | `#111114` |
| `textSecondary` | `rgba(245,245,247,0.62)` | `rgba(17,17,20,0.62)` |
| `textTertiary` | `rgba(245,245,247,0.40)` | `rgba(17,17,20,0.40)` |
| `accent` ("Ember") | `#F0A335` | `#D98A1C` |
| `onAccent` | `#1A1200` | `#1A1200` |
| `success` | `#3DD68C` | `#1E9E62` |
| `danger` | `#F2545B` | `#D63E45` |
| `info` | `#4C8DFF` | `#2F6FE0` |

Watchlist statuses: Want to Watch `info`, Watching `accent`, Watched `success`, Dropped `textTertiary`.

Streaming-service brand colors (Netflix `#E50914`, Hulu `#1CE783`, Disney+ `#113CCF`, HBO Max `#6A2FD8`, Apple TV `#A2AAAD`, Prime Video `#00A8E1`, Peacock `#F2A900`, Paramount+ `#0064FF`, Starz `#C9A227`, AMC+ `#C8102E`, Crunchyroll `#F47521`, Tubi `#7408FF`, YouTube `#FF0033`) are used only as a small tile, dot or monogram background — never as full-bleed chips. When a logo image is available (TMDB), show it in a 36 pt rounded-square tile with a hairline border.

Mood duotones (gradient top-left → bottom-right):

| Mood | From | To | Symbol |
|---|---|---|---|
| Cozy | `#D98E5A` | `#5A2E1A` | sofa / `weekend` |
| Laughs | `#F0C94A` | `#5C4300` | face.smiling / `sentiment_satisfied` |
| Thrills | `#E2473F` | `#3B0B0B` | bolt / `bolt` |
| Feels | `#5B7FE8` | `#121C4A` | heart / `favorite` |
| Spooky | `#8A5CF5` | `#22104D` | moon.stars / `dark_mode` |
| Brainy | `#3DBB9E` | `#0B3A33` | brain / `psychology` |

## Typography

System fonts only: SF Pro on Apple, the Material 3 default on Android, Inter on the web. Weights and sizes:

| Role | Size / weight |
|---|---|
| Large title | 34 / bold, tight tracking |
| Title 1 | 28 / bold |
| Title 2 | 22 / semibold |
| Section header | 20 / semibold, trailing "See All" 15 / medium in `accent` |
| Headline | 17 / semibold |
| Body | 17 / regular |
| Callout | 15 / regular |
| Footnote | 13 / regular, `textSecondary` |
| Caption | 12 / medium, `textSecondary` |

## Shape and depth

- Poster corner radius: 8 (thumb), 10 (row), 14 (featured). Cards 16. Sheets 24. Buttons: capsule.
- Every artwork gets a 1 px `hairline` border so dark posters don't bleed into the background.
- Shadows are soft and low: dark `0 8px 24px rgba(0,0,0,0.45)`, light `0 6px 20px rgba(0,0,0,0.10)`.
- No rotation, no tilt, no hard offset shadows.
- Backdrops fade into `bg` with a vertical gradient (clear → bg over the bottom 55 %).

## Components

- **Hero carousel**: edge-to-edge backdrop (16:9 on wide layouts, 4:5 on phones), gradient fade, bottom-aligned Title 1, metadata line `2024 · Drama · 1h 52m · ★ 7.8`, primary button (accent capsule, "Add to Watchlist" / "In Watchlist") and secondary button (translucent capsule, "Details"). Page indicator dots.
- **Poster row**: section header + horizontally scrolling posters. Poster width 120 (phone), 150 (tablet/desktop). Caption: title 15 semibold one line, subtitle 13 `textSecondary`.
- **Poster grid**: adaptive, 110–120 min width on phones, 150–170 on larger screens, 12–16 gutter.
- **Provider tile**: 36 pt rounded-square logo or 2-letter monogram on brand color; name beneath in Caption. Rows: "Stream", "Free", "Rent", "Buy" with price in Caption.
- **Status badge**: pill, Caption, colored dot + label.
- **Rating**: 5 stars in `accent` (`star.fill` / `star`), 24 pt interactive, 14 pt display. Community score shown as `★ 7.8`.
- **Buttons**: primary = accent fill, `onAccent` text; secondary = `white 12 %` (dark) / `black 6 %` (light) fill; tertiary = text in accent. Height 44 on touch, 32–36 on desktop. Use native Liquid Glass / Material tonal styles where the platform offers them.
- **Mood tiles**: 2 columns on phones, 3–4 on wide layouts, 16:10, duotone gradient, 24 pt outlined symbol top-left, title bottom-left in white Title 2.
- **Shuffle** (formerly "Roulette"): a stack of posters that cycles quickly and decelerates to a stop. The winner expands into a card with a blurred backdrop, title, metadata and actions: "Watch now", "Plan it", "Shuffle again". Filters: pool (Watchlist / Discover), mood, time available.
- **Planner**: week strip with 7 columns; the selected day is an accent circle; days with plans get a 4 pt dot. Agenda cards: poster thumb, title, time range, calendar/reminder indicators, done checkbox.
- **Empty states**: 40 pt symbol in `textTertiary`, Headline, Footnote, one primary button. Centered, max width 320.
- **Settings**: native grouped lists.

## Motion

200–350 ms ease-out for transitions; springs for interactive elements; hover scale 1.02 on desktop; respect reduce-motion everywhere.

## Voice

Concise and warm, no emoji. Feature names: **Tonight**, **Browse**, **Watchlist**, **Planner**, **Shuffle**, **Moods**, **Where to Watch**. "Spud" exists only as the app-icon mark and in the About screen.

## App icon

Deep charcoal gradient (`#1E1E27` → `#0C0C10`), a minimal gold (`#F0A335`) couch silhouette with a play triangle as the center cushion. Source: `design/AppIcon.svg`.
