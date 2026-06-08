param(
    [string[]]$Account,
    [string]$OutputDir = (Join-Path (Get-Location) 'tiktok-audit-output'),
    [switch]$JsonOnly
)

$ErrorActionPreference = 'Stop'

$knownAccounts = @(
    @{
        AccountName = 'Vita Shine official'
        Handle = '@vitashine0002'
        Url = 'https://www.tiktok.com/@vitashine0002'
        Aliases = @('vita shine official', 'official', 'vitashine0002', '@vitashine0002')
    },
    @{
        AccountName = 'Vita Shine Diamonds'
        Handle = '@nvnaow45'
        Url = 'https://www.tiktok.com/@nvnaow45'
        Aliases = @('vita shine diamonds', 'diamonds', 'nvnaow45', '@nvnaow45')
    },
    @{
        AccountName = 'VitaShine Bridal'
        Handle = '@vitashine.bridal'
        Url = 'https://www.tiktok.com/@vitashine.bridal'
        Aliases = @('vitashine bridal', 'vita shine bridal', 'bridal', 'vitashine.bridal', '@vitashine.bridal')
    }
)

function Get-NormalizedText {
    param([string]$Value)
    return ($Value ?? '').Trim().ToLowerInvariant()
}

function Resolve-TikTokAccount {
    param([string]$InputValue)

    $value = ($InputValue ?? '').Trim()
    $normalized = Get-NormalizedText $value

    if ([string]::IsNullOrWhiteSpace($value)) {
        return $null
    }

    foreach ($known in $knownAccounts) {
        if ((Get-NormalizedText $known.AccountName) -eq $normalized -or
            (Get-NormalizedText $known.Handle) -eq $normalized -or
            (Get-NormalizedText $known.Url) -eq $normalized -or
            (($known.Aliases | ForEach-Object { Get-NormalizedText $_ }) -contains $normalized)) {
            return [PSCustomObject]$known
        }
    }

    if ($value -match '^https?://') {
        $handle = if ($value -match 'tiktok\.com/@([^/?]+)') { '@' + $Matches[1] } else { '未取得' }
        return [PSCustomObject]@{
            AccountName = $handle
            Handle = $handle
            Url = $value
            Aliases = @()
        }
    }

    if ($value.StartsWith('@')) {
        return [PSCustomObject]@{
            AccountName = $value
            Handle = $value
            Url = "https://www.tiktok.com/$value"
            Aliases = @()
        }
    }

    throw "无法识别账号：$InputValue。请提供已知账号名、@handle 或 TikTok URL。"
}

function Get-Rate {
    param([double]$Numerator, [double]$Denominator)
    if ($Denominator -le 0) { return '无法计算' }
    return ('{0:N2}%' -f (($Numerator / $Denominator) * 100))
}

function Get-BeijingTime {
    param([long]$UnixSeconds)
    if (-not $UnixSeconds) { return '未取得' }
    $utc = [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds)
    $tz = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
    return [TimeZoneInfo]::ConvertTime($utc, $tz).ToString('yyyy-MM-dd HH:mm:ss')
}

function Get-HoursSincePublished {
    param([long]$UnixSeconds)
    if (-not $UnixSeconds) { return $null }
    $published = [DateTimeOffset]::FromUnixTimeSeconds($UnixSeconds)
    $delta = $script:NowChina - [TimeZoneInfo]::ConvertTime($published, $script:ChinaTimeZone)
    return [Math]::Round($delta.TotalHours, 1)
}

function Get-Observation {
    param($Row)

    if ($null -eq $Row.HoursSincePublished) {
        return '发布时间缺失，无法判断传播阶段。'
    }

    if ($Row.HoursSincePublished -lt 6 -and $Row.ViewCount -lt 200 -and $Row.LikeCount -eq 0 -and $Row.CommentCount -eq 0 -and $Row.SaveCount -eq 0 -and $Row.ShareCount -eq 0) {
        return "发布仅 $($Row.HoursSincePublished) 小时，仍属冷启动样本；当前只能确认初始曝光，不能据此判断内容质量。"
    }

    if ($Row.LikeCount -gt 0 -and $Row.CommentCount -eq 0 -and $Row.SaveCount -eq 0) {
        return '已有轻度点赞反馈，但尚未形成评论或收藏，说明被看到强于被讨论/被保存。'
    }

    if ($Row.ViewCount -lt 50) {
        return '当前播放偏低，优先检查首屏钩子和主题进入速度。'
    }

    return '当前样本仍需结合后续复抓确认。'
}

function Get-Advice {
    param($Row)

    if ($Row.ViewCount -lt 50) {
        return '下一条优先压缩前 2 秒信息密度，直接展示最强产品特征。'
    }

    if ($Row.LikeCount -gt 0 -and $Row.CommentCount -eq 0 -and $Row.SaveCount -eq 0) {
        return '保留当前题材，但文案末尾补问题句或使用场景句，拉评论与收藏。'
    }

    if ($Row.EngagementRate -eq '0.00%') {
        return '先不急着改方向，建议强化首屏对比、稀缺感或佩戴场景，再观察点赞是否回补。'
    }

    return '建议在 3-6 小时后复抓一次，再决定是否调整题材。'
}

function Get-VideoMetrics {
    param($ResolvedAccount)

    $isVideoUrl = $ResolvedAccount.Url -match '/video/'
    $args = if ($isVideoUrl) {
        @('--dump-single-json', '--no-warnings', $ResolvedAccount.Url)
    }
    else {
        @('--dump-single-json', '--playlist-end', '1', '--no-warnings', $ResolvedAccount.Url)
    }

    $raw = & yt-dlp @args
    $json = $raw | ConvertFrom-Json -Depth 100
    $entry = if ($json.entries -and $json.entries.Count -gt 0) { $json.entries[0] } else { $json }

    if (-not $entry) {
        throw "yt-dlp 没有返回视频条目：$($ResolvedAccount.Url)"
    }

    $views = [double]($entry.view_count ?? 0)
    $likes = [double]($entry.like_count ?? 0)
    $comments = [double]($entry.comment_count ?? 0)
    $saves = [double]($entry.save_count ?? 0)
    $shares = [double]($entry.repost_count ?? 0)

    [PSCustomObject]@{
        AccountName = $ResolvedAccount.AccountName
        Handle = $ResolvedAccount.Handle
        VideoUrl = $entry.webpage_url
        VideoId = $entry.id
        PublishedTimestamp = [int64]($entry.timestamp ?? 0)
        PublishedAt = Get-BeijingTime -UnixSeconds $entry.timestamp
        Caption = ($entry.description ?? $entry.title)
        DurationSeconds = ($entry.duration ?? '未取得')
        ViewCount = [int64]$views
        LikeCount = [int64]$likes
        CommentCount = [int64]$comments
        SaveCount = [int64]$saves
        ShareCount = [int64]$shares
        LikeRate = Get-Rate -Numerator $likes -Denominator $views
        CommentRate = Get-Rate -Numerator $comments -Denominator $views
        SaveRate = Get-Rate -Numerator $saves -Denominator $views
        EngagementRate = Get-Rate -Numerator ($likes + $comments + $saves + $shares) -Denominator $views
        HoursSincePublished = Get-HoursSincePublished -UnixSeconds $entry.timestamp
        ViewFollowerRatio = '缺少粉丝数'
        Source = 'yt-dlp'
        Note = '数据源：yt-dlp'
    }
}

function Format-MarkdownCell {
    param($Value)
    if ($null -eq $Value) { return '' }
    return ([string]$Value).Replace('|', '/').Replace("`r", ' ').Replace("`n", ' ')
}

$script:ChinaTimeZone = [TimeZoneInfo]::FindSystemTimeZoneById('China Standard Time')
$script:NowChina = [TimeZoneInfo]::ConvertTime([DateTimeOffset]::UtcNow, $script:ChinaTimeZone)
$dateStamp = $script:NowChina.ToString('yyyy-MM-dd')

if (-not $Account -or $Account.Count -eq 0) {
    $Account = $knownAccounts.AccountName
}

New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$rows = foreach ($item in $Account) {
    $resolved = Resolve-TikTokAccount -InputValue $item
    Get-VideoMetrics -ResolvedAccount $resolved
}

$jsonPath = Join-Path $OutputDir "tiktok-latest-video-audit-$dateStamp.json"
$mdPath = Join-Path $OutputDir "tiktok-latest-video-audit-$dateStamp.md"
$rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = @()
$lines += "# TikTok 最新视频审计 - $dateStamp"
$lines += ''
$lines += '| 账号 | handle | 视频链接 | 发布时间 | 时长 | 播放 | 点赞 | 评论 | 收藏 | 分享 | 综合互动率 | 数据源 |'
$lines += '|---|---|---|---|---:|---:|---:|---:|---:|---:|---:|---|'
foreach ($row in $rows) {
    $lines += "| $(Format-MarkdownCell $row.AccountName) | ``$(Format-MarkdownCell $row.Handle)`` | [链接]($($row.VideoUrl)) | $(Format-MarkdownCell $row.PublishedAt) | $(Format-MarkdownCell $row.DurationSeconds) | $(Format-MarkdownCell $row.ViewCount) | $(Format-MarkdownCell $row.LikeCount) | $(Format-MarkdownCell $row.CommentCount) | $(Format-MarkdownCell $row.SaveCount) | $(Format-MarkdownCell $row.ShareCount) | $(Format-MarkdownCell $row.EngagementRate) | $(Format-MarkdownCell $row.Source) |"
}
$lines += ''
$lines += '## 内容表现与建议'
$lines += ''
$lines += '| 账号 | 内容表现 | 优化建议 |'
$lines += '|---|---|---|'
foreach ($row in $rows) {
    $lines += "| $(Format-MarkdownCell $row.AccountName) | $(Format-MarkdownCell (Get-Observation -Row $row)) | $(Format-MarkdownCell (Get-Advice -Row $row)) |"
}
$lines += ''
$lines += '备注：粉丝数、完播率、平均观看时长无法从公开视频元数据稳定取得；播放/粉丝比标记为“缺少粉丝数”。'

$markdown = $lines -join [Environment]::NewLine
$markdown | Set-Content -LiteralPath $mdPath -Encoding UTF8

if ($JsonOnly) {
    $rows | ConvertTo-Json -Depth 6
}
else {
    $markdown
    ''
    "JSON: $jsonPath"
    "Markdown: $mdPath"
}
