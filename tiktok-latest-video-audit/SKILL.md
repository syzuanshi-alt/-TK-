---
name: tiktok-latest-video-audit
description: Fetch and analyze the latest public TikTok video metrics for one or more accounts. Use when the user asks to audit TikTok accounts, query a latest TikTok video by account name/handle/URL, compare accounts, compute engagement rates, or produce Chinese TikTok performance recommendations. Prefer yt-dlp metadata over TikTok web HTML/API scraping.
---

# TikTok Latest Video Audit

## Workflow

Use the bundled script first:

```powershell
pwsh -File scripts/tiktok_latest_video_audit.ps1 -Account "Vita Shine official"
pwsh -File scripts/tiktok_latest_video_audit.ps1 -Account "@vitashine0002","@nvnaow45"
pwsh -File scripts/tiktok_latest_video_audit.ps1 -Account "https://www.tiktok.com/@vitashine.bridal"
```

If the user gives no accounts, run the default three-account audit:

```powershell
pwsh -File scripts/tiktok_latest_video_audit.ps1
```

Always report in Chinese unless the user asks otherwise. Lead with the result table, then concise analysis.

## Account Inputs

Accept any of these in conversation:

- Known account name, for example `Vita Shine official`
- TikTok handle, for example `@vitashine0002`
- TikTok profile URL, for example `https://www.tiktok.com/@vitashine0002`
- TikTok video URL, for example `https://www.tiktok.com/@user/video/123`

Known aliases are documented in `references/accounts.md`. If a name is not known, treat it as a TikTok handle when it starts with `@`; otherwise ask for a handle or URL.

## Data Source Rules

Prefer local `yt-dlp` metadata extraction:

```powershell
yt-dlp --dump-single-json --playlist-end 1 --no-warnings "<profile-url>"
```

For video URLs, use:

```powershell
yt-dlp --dump-single-json --no-warnings "<video-url>"
```

Use `entries[0]` for profile results. Do not prioritize TikTok webpage HTML or `/api/post/item_list`; those often return empty or risk-controlled content.

## Output Requirements

Include these fields when available:

- Account name and handle
- Video URL and video ID
- Published time in Asia/Shanghai
- Caption/title and duration
- Views, likes, comments, saves, shares/reposts
- Like rate, comment rate, save rate, total engagement rate
- View/follower ratio, marked as `缺少粉丝数` when follower count is unavailable
- Data source note, usually `yt-dlp`

Recommendations must be evidence-based. If the video is under 6 hours old, state that it is an early sample and avoid strong quality conclusions.

## Optional Delivery

This skill is designed for in-chat querying. If the user also asks for Feishu delivery or Base sync, use the local project automation only when the required Feishu config already exists in the environment. Do not invent chat IDs, base tokens, or table schemas.
