[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

$script:DefaultRepositoryUrl = "https://github.com/mikannohako/JujutsuController.git"
$script:ConfigPath = Join-Path $PSScriptRoot "config.ini"
$script:SetupMarkerPath = Join-Path $PSScriptRoot ".setup-completed"
$script:JujutsuControllerVersion = "3.0.0"
$Host.UI.RawUI.WindowTitle = "JujutsuController"

function Get-ECLatestRelease {
    $release = Invoke-RestMethod `
        -Uri "https://api.github.com/repos/mikannohako/JujutsuController/releases/latest" `
        -Headers @{ "User-Agent" = "JujutsuController" }

    if ($null -eq $release) {
        throw "GitHub APIからリリース情報を取得できませんでした。"
    }

    if ([string]::IsNullOrWhiteSpace([string]$release.tag_name)) {
        throw "最新リリースのバージョン情報が取得できませんでした。"
    }

    return $release
}

function Test-ECUpdate {
    try {
        $release = Get-ECLatestRelease

        $latestVersion = ([string]$release.tag_name).TrimStart("v")
        $latestUrl = [string]$release.html_url

        if ([version]$latestVersion -gt [version]$script:JujutsuControllerVersion) {
            Write-Host ""
            Write-Host "新しいJujutsuControllerがあります。" -ForegroundColor Yellow
            Write-Host "  現在: $script:JujutsuControllerVersion" -ForegroundColor Gray
            Write-Host "  最新: $latestVersion" -ForegroundColor Green
            Write-Host ""

            $open = Read-Host "最新版のページを開きますか？ [Y/n]"

            if (
                [string]::IsNullOrWhiteSpace($open) -or
                $open -match '^(?i)y(es)?$'
            ) {
                Start-Process $latestUrl
            }
        }
    }
    catch {
        Write-Host "JujutsuControllerの更新確認中にエラーが発生しました: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

function Write-ECHeader {
    Clear-Host
    Write-Host ""
    Write-Host "  Easy Controller" -ForegroundColor Cyan
    Write-Host "  Git / Jujutsu project toolkit" -ForegroundColor DarkCyan
    Write-Host "  Version $script:JujutsuControllerVersion" -ForegroundColor DarkGray
    Write-Host "  Repository: $($script:DefaultRepositoryUrl)" -ForegroundColor DarkGray
    Write-Host "  $('-' * 42)" -ForegroundColor DarkGray
    Write-Host ""
}

function Write-StageProgress {
    param(
        [Parameter(Mandatory)] [int] $Current,
        [Parameter(Mandatory)] [int] $Total,
        [Parameter(Mandatory)] [string] $Activity,
        [Parameter(Mandatory)] [string] $Status
    )

    Write-Host "  $Activity - $Status" -ForegroundColor DarkCyan
}

function Clear-StageProgress {
}

function Invoke-RequiredCommand {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [Parameter(Mandatory)] [AllowEmptyString()] [string[]] $Arguments
    )

    & $Command @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "コマンドに失敗しました: $Command $($Arguments -join ' ')"
    }
}

function Test-CommandAvailable {
    param([Parameter(Mandatory)] [string] $Name)

    return $null -ne (Get-Command $Name -ErrorAction SilentlyContinue)
}

function Read-ECConfig {
    $config = @{}
    if (-not (Test-Path $script:ConfigPath)) {
        return $config
    }

    foreach ($line in [System.IO.File]::ReadAllLines($script:ConfigPath)) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith("#") -or $trimmedLine.StartsWith("[")) {
            continue
        }

        $separator = $trimmedLine.IndexOf('=')
        if ($separator -gt 0) {
            $key = $trimmedLine.Substring(0, $separator).Trim()
            $value = $trimmedLine.Substring($separator + 1).Trim()
            $config[$key] = $value
        }
    }

    return $config
}

function Save-ECConfig {
    param(
        [Parameter(Mandatory)] [string] $UserName,
        [Parameter(Mandatory)] [string] $UserEmail,
        [string] $RepositoryUrl = $script:DefaultRepositoryUrl
    )

    $existingConfig = Read-ECConfig
    $projectDirectory = [string] $existingConfig["project_directory"]
    $lines = @(
        "[user]",
        "name=$UserName",
        "email=$UserEmail",
        "repository_url=$RepositoryUrl",
        "project_directory=$projectDirectory",
        ""
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($script:ConfigPath, $lines, $utf8NoBom)
    Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
}

function Save-ECProjectDirectory {
    param([Parameter(Mandatory)] [string] $ProjectDirectory)

    $lines = @()
    if (Test-Path -LiteralPath $script:ConfigPath) {
        $lines = [System.IO.File]::ReadAllLines($script:ConfigPath)
    }

    $projectLineIndex = -1
    for ($index = 0; $index -lt $lines.Count; $index++) {
        if ($lines[$index] -match '^\s*project_directory\s*=') {
            $projectLineIndex = $index
            break
        }
    }

    $projectLine = "project_directory=$ProjectDirectory"
    if ($projectLineIndex -ge 0) {
        $lines[$projectLineIndex] = $projectLine
    }
    else {
        $lines += $projectLine
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($script:ConfigPath, $lines, $utf8NoBom)
}

function Get-ECProjectDirectory {
    $config = Read-ECConfig
    $projectDirectory = [string] $config["project_directory"]
    if ([string]::IsNullOrWhiteSpace($projectDirectory)) {
        throw "セットアップ先のプロジェクトフォルダが設定されていません。セットアップを再実行してください。"
    }
    if (-not (Test-Path -LiteralPath $projectDirectory -PathType Container)) {
        throw "保存済みのプロジェクトフォルダが見つかりません: $projectDirectory"
    }

    $resolvedProjectDirectory = (Resolve-Path -LiteralPath $projectDirectory).Path
    $hasJujutsuRepository = Test-Path -LiteralPath (Join-Path $resolvedProjectDirectory ".jj")
    $hasGitRepository = Test-Path -LiteralPath (Join-Path $resolvedProjectDirectory ".git")
    if (-not ($hasJujutsuRepository -or $hasGitRepository)) {
        throw "保存済みのフォルダは Git/Jujutsu リポジトリではありません: $resolvedProjectDirectory"
    }

    return $resolvedProjectDirectory
}

function Set-ECProjectLocation {
    $projectDirectory = Get-ECProjectDirectory
    Set-Location -LiteralPath $projectDirectory
}

function Get-ECRepositoryUrl {
    $config = Read-ECConfig
    $repositoryUrl = [string] $config["repository_url"]
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        return $script:DefaultRepositoryUrl
    }
    return $repositoryUrl
}

function Read-ECRepositorySettings {
    param([Parameter(Mandatory)] [hashtable] $UserSettings)

    $currentRepositoryUrl = Get-ECRepositoryUrl
    Write-Host ""
    Write-Host "cloneするリポジトリを選択してください。" -ForegroundColor Cyan
    $repositoryUrl = Read-Host "リポジトリURL [$currentRepositoryUrl]"
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        $repositoryUrl = $currentRepositoryUrl
    }
    Test-ECRepositoryUrl -RepositoryUrl $repositoryUrl

    $saveDecision = Read-Host "このリポジトリURLを設定に保存しますか？ [Y/n/C]"
    if ([string]::IsNullOrWhiteSpace($saveDecision) -or $saveDecision -match '^(?i)y(es)?$') {
        Save-ECConfig -UserName $UserSettings.Name -UserEmail $UserSettings.Email -RepositoryUrl $repositoryUrl
    }
    elseif ($saveDecision -match '^(?i)c(ancel)?$') {
        throw "リポジトリ選択をキャンセルしました。"
    }
    else {
        Write-Host "リポジトリURLは保存せず、今回のセットアップだけで利用します。" -ForegroundColor Yellow
    }

    return $repositoryUrl
}

function Test-ECRepositoryUrl {
    param([Parameter(Mandatory)] [string] $RepositoryUrl)

    if ($RepositoryUrl -match '^git@[^:]+:.+$') {
        return
    }

    $uri = $null
    if (-not [Uri]::TryCreate($RepositoryUrl, [UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -notin @("http", "https", "ssh", "git")) {
        throw "リポジトリURLが正しくありません。"
    }
}

function Read-ECSaveDecision {
    $decision = Read-Host "設定を保存しますか？ [Y/n/C]"
    if ([string]::IsNullOrWhiteSpace($decision) -or $decision -match '^(?i)y(es)?$') {
        return "save"
    }
    if ($decision -match '^(?i)c(ancel)?$') {
        return "cancel"
    }
    return "skip"
}

function Read-ECUserSettings {
    $config = Read-ECConfig
    $savedName = [string] $config["name"]
    $savedEmail = [string] $config["email"]
    $hasSavedSettings = -not [string]::IsNullOrWhiteSpace($savedName) -and -not [string]::IsNullOrWhiteSpace($savedEmail)

    if ($hasSavedSettings) {
        Write-Host "保存済みの設定が見つかりました。" -ForegroundColor Cyan
        Write-Host "  名前: $savedName" -ForegroundColor DarkGray
        Write-Host "  メール: $savedEmail" -ForegroundColor DarkGray
        $useSavedSettings = Read-Host "この設定を利用しますか？ [Y/n]"
        if ([string]::IsNullOrWhiteSpace($useSavedSettings) -or $useSavedSettings -match '^(?i)y(es)?$') {
            return @{ Name = $savedName; Email = $savedEmail }
        }
    }

    $userName = Read-Host "Git ユーザー名"
    $userEmail = Read-Host "Git メールアドレス"
    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userEmail)) {
        throw "名前とメールアドレスは必須です。"
    }

    $saveDecision = Read-ECSaveDecision
    if ($saveDecision -eq "cancel") {
        throw "設定の保存をキャンセルしました。"
    }
    if ($saveDecision -eq "save") {
        Save-ECConfig -UserName $userName -UserEmail $userEmail -RepositoryUrl (Get-ECRepositoryUrl)
    }
    else {
        Write-Host "設定は保存せず、この処理でのみ利用します。" -ForegroundColor Yellow
    }
    return @{ Name = $userName; Email = $userEmail }
}

function Invoke-ConfigChange {
    Write-ECHeader
    try {
        $config = Read-ECConfig
        $currentName = [string] $config["name"]
        $currentEmail = [string] $config["email"]
        $currentRepositoryUrl = Get-ECRepositoryUrl

        $settings = @(
            [PSCustomObject]@{ Label = "Git ユーザー名"; Key = "name"; Value = $currentName },
            [PSCustomObject]@{ Label = "Git メールアドレス"; Key = "email"; Value = $currentEmail },
            [PSCustomObject]@{ Label = "リポジトリURL"; Key = "repository_url"; Value = $currentRepositoryUrl }
        )
        $selected = 0
        while ($true) {
            Write-ECHeader
            Write-Host "  変更する設定を選択してください。" -ForegroundColor Cyan
            Write-Host "  上下:選択  Enter:決定  Esc:キャンセル" -ForegroundColor DarkCyan
            Write-Host ""
            for ($index = 0; $index -lt $settings.Count; $index++) {
                $line = "$($settings[$index].Label): $($settings[$index].Value)"
                if ($index -eq $selected) {
                    Write-Host "  > $line" -ForegroundColor White -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    $line" -ForegroundColor Gray
                }
            }

            if ($selected -eq $settings.Count) {
                Write-Host "  > キャンセル" -ForegroundColor Yellow -BackgroundColor DarkGray
            }
            else {
                Write-Host "    キャンセル" -ForegroundColor Yellow
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" { $selected = ($selected - 1 + $settings.Count + 1) % ($settings.Count + 1) }
                "DownArrow" { $selected = ($selected + 1) % ($settings.Count + 1) }
                "Escape" { return }
                "Enter" { break }
            }
            if ($key.Key -eq "Enter") {
                break
            }
        }

        if ($selected -eq $settings.Count) {
            Write-Host "設定変更をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        $setting = $settings[$selected]
        $newValue = Read-Host "$($setting.Label) [$($setting.Value)]"
        if ([string]::IsNullOrWhiteSpace($newValue)) {
            Write-Host "設定変更をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        $newName = $currentName
        $newEmail = $currentEmail
        $newRepositoryUrl = $currentRepositoryUrl
        switch ($setting.Key) {
            "name" { $newName = $newValue }
            "email" { $newEmail = $newValue }
            "repository_url" { $newRepositoryUrl = $newValue }
        }
        if ([string]::IsNullOrWhiteSpace($newName) -or [string]::IsNullOrWhiteSpace($newEmail)) {
            throw "名前とメールアドレスは必須です。"
        }
        Test-ECRepositoryUrl -RepositoryUrl $newRepositoryUrl
        Save-ECConfig -UserName $newName -UserEmail $newEmail -RepositoryUrl $newRepositoryUrl
    }
    catch {
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Update-ProcessPath {
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    $pathEntries = @($machinePath, $userPath) | Where-Object { $_ } | ForEach-Object {
        $_ -split ';' | Where-Object { $_ }
    }

    $env:Path = ($pathEntries | Select-Object -Unique) -join ';'
    Write-Host "PATH を再読み込みしました。" -ForegroundColor Green
}

function Install-RequiredTools {
    if (-not (Test-CommandAvailable "winget")) {
        throw "winget が見つかりません。Windows App Installer をインストールしてください。"
    }

    Write-Host "winget を確認しました。" -ForegroundColor Green

    if (-not (Test-CommandAvailable "git")) {
        Write-Host "Git をインストールしています..." -ForegroundColor Yellow
        Invoke-RequiredCommand "winget" @("install", "--id", "Git.Git", "--exact", "--source", "winget")
        Write-Host "Git のインストールが完了しました。" -ForegroundColor Green
    }
    else {
        Write-Host "Git はインストール済みです。" -ForegroundColor DarkGray
    }

    if (-not (Test-CommandAvailable "jj")) {
        Write-Host "Jujutsu (jj) をインストールしています..." -ForegroundColor Yellow
        Invoke-RequiredCommand "winget" @("install", "--id", "jj-vcs.jj", "--exact", "--source", "winget")
        Write-Host "jj のインストールが完了しました。" -ForegroundColor Green
    }
    else {
        Write-Host "jj はインストール済みです。" -ForegroundColor DarkGray
    }

    Update-ProcessPath
}

function Select-ECProjectDirectory {
    $projectName = Read-Host "プロジェクトフォルダ名"
    if ([string]::IsNullOrWhiteSpace($projectName)) {
        throw "プロジェクトフォルダ名が入力されていません。"
    }

    $invalidCharacters = [System.IO.Path]::GetInvalidFileNameChars()
    if ($projectName.IndexOfAny($invalidCharacters) -ge 0 -or $projectName -in @('.', '..')) {
        throw "プロジェクトフォルダ名に使用できない文字が含まれています。"
    }

    $defaultParentDirectory = [Environment]::GetFolderPath("Desktop")
    $parentDirectory = Read-Host "プロジェクトを置く親フォルダのパス [$defaultParentDirectory]"
    if ([string]::IsNullOrWhiteSpace($parentDirectory)) {
        $parentDirectory = $defaultParentDirectory
    }
    $parentDirectory = $parentDirectory.Trim().Trim('"')
    if (-not (Test-Path -LiteralPath $parentDirectory -PathType Container)) {
        throw "親フォルダが見つかりません: $parentDirectory"
    }

    $projectDirectory = Join-Path (Resolve-Path -LiteralPath $parentDirectory).Path $projectName
    if (Test-Path $projectDirectory) {
        if (-not (Test-Path $projectDirectory -PathType Container)) {
            throw "同名のファイルが既に存在します: $projectDirectory"
        }
        $hasJujutsuRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".jj")
        $hasGitRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".git")
        $hasExistingFiles = @(Get-ChildItem -LiteralPath $projectDirectory -Force).Count -gt 0
        if ($hasExistingFiles -and -not ($hasJujutsuRepository -or $hasGitRepository)) {
            throw "選択した場所に既存のファイルがあります: $projectDirectory"
        }
    }

    return $projectDirectory
}

function Initialize-ECRepository {
    $projectDirectory = Select-ECProjectDirectory

    New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
    Set-Location $projectDirectory

    $userSettings = Read-ECUserSettings
    $repositoryUrl = Read-ECRepositorySettings -UserSettings $userSettings

    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.name", $userSettings.Name)
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.email", $userSettings.Email)

    $hasJujutsuRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".jj")
    $hasGitRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".git")
    if ($hasJujutsuRepository -or $hasGitRepository) {
        Write-Host "既存のリポジトリを使用します..." -ForegroundColor Yellow
    }
    else {
        Write-Host "リポジトリを取得しています..." -ForegroundColor Yellow
        Invoke-RequiredCommand "jj" @("git", "clone", $repositoryUrl, ".")
    }
    Save-ECProjectDirectory -ProjectDirectory $projectDirectory
    explorer.exe $projectDirectory

    Write-Host "セットアップ先: $projectDirectory" -ForegroundColor Green
}

function Invoke-Setup {
    Write-ECHeader
    $total = 3
    try {
        Write-StageProgress 1 $total "EC セットアップ" "必要なツールを確認しています..."
        Install-RequiredTools

        Write-StageProgress 2 $total "EC セットアップ" "リポジトリ設定を準備しています..."
        if (-not (Test-CommandAvailable "jj")) {
            throw "PATH 再読み込み後も jj が見つかりません。新しい PowerShell で再実行してください。"
        }

        Write-StageProgress 3 $total "EC セットアップ" "ユーザー設定とリポジトリを準備しています..."
        Initialize-ECRepository
        Clear-StageProgress
        Set-Content -LiteralPath $script:SetupMarkerPath -Value "completed" -Encoding utf8
        Write-Host "`nセットアップが完了しました。" -ForegroundColor Green
        return $true
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-Update {
    Write-ECHeader
    try {
        Write-StageProgress 1 2 "EC 更新" "サーバーから最新情報を取得しています..."
        Invoke-RequiredCommand "jj" @("git", "fetch")

        Write-StageProgress 2 2 "EC 更新" "最新の main に合わせています..."
        Invoke-RequiredCommand "jj" @("rebase", "-d", "main@origin")
        Clear-StageProgress
        Write-Host "`n更新が完了しました。`n" -ForegroundColor Green
        Write-Host "現在の状態:" -ForegroundColor Cyan
        & jj status
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "コンフリクトなどが発生している可能性があります。コンフリクトを解決してください。" -ForegroundColor Yellow
    }
}

function Invoke-Publish {
    Write-ECHeader
    try {

        Invoke-Update

        Write-StageProgress 1 4 "EC 保存" "変更を確認しています..."
        Invoke-RequiredCommand "jj" @("status")
        
        Write-Host ""
        $existingComment = @(& jj log -r "@" --no-graph -T "description") -join [Environment]::NewLine
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj log -r @ --no-graph -T description"
        }
        $existingComment = $existingComment.Trim()

        if (-not [string]::IsNullOrWhiteSpace($existingComment)) {
            Write-Host "現在のコメント:" -ForegroundColor Cyan
            Write-Host $existingComment -ForegroundColor DarkGray
            $reuseComment = Read-Host "このコメントを利用しますか？ [Y/n]"
            if ([string]::IsNullOrWhiteSpace($reuseComment) -or $reuseComment -match '^(Y|y)$') {
                $comment = $existingComment
            }
            else {
                Write-Host "変更を保存するにはコメントが必要です。（空白でキャンセル）" -ForegroundColor Cyan
                $comment = Read-Host "変更コメント"
            }
        }
        else {
            Write-Host "変更を保存するにはコメントが必要です。（空白でキャンセル）" -ForegroundColor Cyan
            $comment = Read-Host "変更コメント"
        }

        if ([string]::IsNullOrWhiteSpace($comment)) {
            Clear-StageProgress
            Write-Host "`n保存をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 2 4 "EC 保存" "変更にコメントを設定しています..."
        Invoke-RequiredCommand "jj" @("desc", "-m", $comment)

        Write-StageProgress 3 4 "EC 保存" "main を更新しています..."
        Invoke-RequiredCommand "jj" @("bookmark", "set", "main", "-r", "@")

        Write-StageProgress 4 4 "EC 保存" "サーバーへアップロードしています..."
        Invoke-RequiredCommand "jj" @("git", "push")
        Clear-StageProgress
        Write-Host "`nアップロードが完了しました。" -ForegroundColor Green
        Write-Host "コメント: $comment" -ForegroundColor DarkGray
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-NewChange {
    Write-ECHeader
    try {
        Write-Host "新しい変更のコメントを入力してください。（空白でキャンセル）" -ForegroundColor Cyan
        $comment = Read-Host "変更コメント"
        if ([string]::IsNullOrWhiteSpace($comment)) {
            Clear-StageProgress
            Write-Host "`n変更をキャンセルしました。" -ForegroundColor Yellow
            return
        }
        Write-StageProgress 1 1 "EC 区切り" "新しい変更を作成しています..."
        Invoke-RequiredCommand "jj" @("new", "-m", $comment)
        Clear-StageProgress
        Write-Host "`n新しい変更を作成しました。" -ForegroundColor Green
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-AddDescription {
    Write-ECHeader
    try {
        while ($true) {
            $logLines = @(& jj log -r "mutable() ~ root()" --no-graph -T 'change_id ++ "\t" ++ committer.timestamp() ++ "\t" ++ description.first_line() ++ "\n"')
            if ($LASTEXITCODE -ne 0) {
                throw "コマンドに失敗しました: jj log -r mutable() ~ root()"
            }

            $candidates = @()
            foreach ($line in $logLines) {
                $parts = $line -split "`t", 3
                if ($parts.Count -eq 3) {
                    $description = $parts[2].Trim()
                    if ([string]::IsNullOrWhiteSpace($description)) {
                        $description = "(コメントなし)"
                    }
                    $candidates += [PSCustomObject]@{
                        ChangeId    = $parts[0].Trim()
                        Timestamp   = $parts[1].Trim()
                        Description = $description
                    }
                }
            }

            if ($candidates.Count -eq 0) {
                Write-Host "コメントを設定・変更できる未pushの変更はありません。" -ForegroundColor Green
                return
            }

            $selectedIndex = 0
            while ($true) {
                Write-ECHeader
                Write-Host "  コメントを設定・変更する変更を選択してください。" -ForegroundColor Cyan
                Write-Host "  上下:選択  Enter:決定  Esc:キャンセル" -ForegroundColor DarkCyan
                Write-Host ""
                for ($index = 0; $index -lt $candidates.Count; $index++) {
                    $line = "$($candidates[$index].ChangeId)  $($candidates[$index].Timestamp)  $($candidates[$index].Description)"

                    if ($index -eq $selectedIndex) {
                        Write-Host "  > $line" -ForegroundColor White -BackgroundColor DarkGray
                    }
                    else {
                        Write-Host "    $line" -ForegroundColor Gray
                    }
                }

                if ($selectedIndex -eq $candidates.Count) {
                    Write-Host "  > キャンセル" -ForegroundColor Yellow -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    キャンセル" -ForegroundColor Yellow
                }

                $key = [Console]::ReadKey($true)
                switch ($key.Key) {
                    "UpArrow" { $selectedIndex = ($selectedIndex - 1 + $candidates.Count + 1) % ($candidates.Count + 1) }
                    "DownArrow" { $selectedIndex = ($selectedIndex + 1) % ($candidates.Count + 1) }
                    "Escape" { return }
                    "Enter" { if ($selectedIndex -eq $candidates.Count) { return } break }
                }
                if ($key.Key -eq "Enter") {
                    break
                }
            }

            $comment = Read-Host "変更コメント（上書き可・空白でキャンセル）"
            if ([string]::IsNullOrWhiteSpace($comment)) {
                Write-Host "コメントが空のためキャンセルしました。" -ForegroundColor Yellow
                return
            }

            Write-StageProgress 1 1 "コメント設定" "変更コメントを設定しています..."
            Invoke-RequiredCommand "jj" @("desc", "-r", $candidates[$selectedIndex].ChangeId, "-m", $comment)
            Clear-StageProgress
            Write-Host "`nコメントを設定しました。" -ForegroundColor Green
            Write-Host "続けて別の変更にもコメントを設定できます。" -ForegroundColor DarkCyan
        }
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Undo {
    Write-ECHeader
    try {
        Write-Host "直前の操作を取り消します。" -ForegroundColor Yellow
        $decision = Read-Host "実行しますか？ [y/N]"
        if ($decision -notmatch '^(?i)y(es)?$') {
            Write-Host "取り消しをキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "EC Undo" "直前の操作を取り消しています..."
        Invoke-RequiredCommand "jj" @("undo")
        Clear-StageProgress
        Write-Host "`n直前の操作を取り消しました。" -ForegroundColor Green
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ECConflictFiles {
    $conflictLines = @(& jj resolve --list 2>&1)
    if ($LASTEXITCODE -ne 0) {
        $errorText = ($conflictLines | ForEach-Object { [string] $_ }) -join [Environment]::NewLine
        if ($errorText -match "(?i)No conflicts found at this revision") {
            return @()
        }
        throw "コマンドに失敗しました: jj resolve --list"
    }

    $conflictFiles = @()
    foreach ($line in $conflictLines) {
        $path = ([string] $line).Trim()
        if (-not [string]::IsNullOrWhiteSpace($path)) {
            $conflictFiles += [PSCustomObject]@{
                Status = "C"
                Path   = $path
            }
        }
    }
    return $conflictFiles
}

function Invoke-ResolveConflicts {
    try {
        $conflictFiles = @(Get-ECConflictFiles)
        if ($conflictFiles.Count -eq 0) {
            Write-ECHeader
            Write-Host "  コンフリクトがありません。" -ForegroundColor Green
            return
        }

        $selected = 0
        while ($true) {
            Write-ECHeader
            Write-Host "  解決するコンフリクトを選択してください。" -ForegroundColor Cyan
            Write-Host "  上下:選択  Enter:決定  Esc:キャンセル" -ForegroundColor DarkCyan
            Write-Host ""
            for ($index = 0; $index -lt $conflictFiles.Count; $index++) {
                $line = "[C] $($conflictFiles[$index].Path)"
                if ($index -eq $selected) {
                    Write-Host "  > $line" -ForegroundColor Red -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    $line" -ForegroundColor Red
                }
            }

            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" { $selected = ($selected - 1 + $conflictFiles.Count) % $conflictFiles.Count }
                "DownArrow" { $selected = ($selected + 1) % $conflictFiles.Count }
                "Escape" { return }
                "Enter" { break }
            }
            if ($key.Key -eq "Enter") {
                break
            }
        }

        $conflictPath = $conflictFiles[$selected].Path
        Write-Host ""
        Write-Host "対象: $conflictPath" -ForegroundColor Cyan
        Write-Host "  L: ローカルを優先"
        Write-Host "  R: リモートを優先"
        Write-Host "  C: キャンセル"
        $decision = Read-Host "解決方法"
        if ($decision -match '^(?i)l(ocal)?$') {
            $tool = ":ours"
            $side = "ローカル"
        }
        elseif ($decision -match '^(?i)r(emote)?$') {
            $tool = ":theirs"
            $side = "リモート"
        }
        else {
            Write-Host "コンフリクト解決をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "コンフリクト解決" "$side を優先しています..."
        Invoke-RequiredCommand "jj" @("resolve", "--tool", $tool, "--", $conflictPath)
        Clear-StageProgress
        Write-Host "`nコンフリクトを解決しました: $conflictPath" -ForegroundColor Green
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ReviewChanges {
    $changedFiles = @()
    try {
        Write-StageProgress 1 2 "変更を確認" "変更状態を確認しています..."
        $statusOutput = @(& jj status)
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj status"
        }

        foreach ($line in $statusOutput) {
            if ($line -match '^\s*([MADRC?])\s+(.+?)\s*$') {
                $changedFiles += [PSCustomObject]@{
                    Status = $Matches[1]
                    Path   = $Matches[2]
                }
            }
        }

        Clear-StageProgress
        if ($changedFiles.Count -eq 0) {
            Write-ECHeader
            Write-Host "  変更されたファイルはありません。" -ForegroundColor Green
            return
        }

        Read-ECChangedFileChoice -ChangedFiles $changedFiles
    }
    catch {
        Clear-StageProgress
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ViewHistory {
    Write-ECHeader
    try {
        Write-Host "  変更履歴（最近10件）" -ForegroundColor Cyan
        Write-Host ""
        & jj log -r "all()" -n 10 --no-pager
        if ($LASTEXITCODE -ne 0) {
            throw "コマンドに失敗しました: jj log -r all() --no-pager"
        }
    }
    catch {
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }

    Write-Host ""
}

function Get-ECStatusColor {
    param([Parameter(Mandatory)] [string] $Status)

    switch ($Status) {
        "M" { return "Yellow" }
        "A" { return "Green" }
        "D" { return "Red" }
        "R" { return "Cyan" }
        default { return "Gray" }
    }
}

function Read-ECChangedFileChoice {
    param([Parameter(Mandatory)] [array] $ChangedFiles)

    $selected = 0
    while ($true) {
        Write-ECHeader
        Write-Host "  変更されたファイル" -ForegroundColor White
        Write-Host "  M:変更  A:追加  D:削除  R:名前変更" -ForegroundColor DarkGray
        Write-Host ""

        for ($index = 0; $index -lt $ChangedFiles.Count; $index++) {
            $file = $ChangedFiles[$index]
            $color = Get-ECStatusColor -Status $file.Status
            $line = "[$($file.Status)] $($file.Path)"
            if ($index -eq $selected) {
                Write-Host "  > $line" -ForegroundColor $color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $line" -ForegroundColor $color
            }
        }

        Write-Host ""
        Write-Host "  Enter:差分を表示  Esc:戻る" -ForegroundColor DarkCyan
        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $ChangedFiles.Count) % $ChangedFiles.Count }
            "DownArrow" { $selected = ($selected + 1) % $ChangedFiles.Count }
            "Escape" { return }
            "Enter" {
                Show-ECFileDiff -Path $ChangedFiles[$selected].Path
            }
        }
    }
}

function Show-ECFileDiff {
    param([Parameter(Mandatory)] [string] $Path)

    Write-ECHeader
    Write-Host "  [$Path]" -ForegroundColor Cyan
    Write-Host ""
    & jj diff -- $Path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n差分の表示に失敗しました。" -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Enter でファイル一覧に戻ります"
}

function Read-ECMenuChoice {
    $items = @(
        @{ Label = "変更を確認（status / diff）"; Color = "Cyan"; Action = { Invoke-ReviewChanges } },
        @{ Label = "最新の情報を取得（fetch / rebase）"; Color = "Blue"; Action = { Invoke-Update } },
        @{ Label = "変更を保存（commit / push）"; Color = "Green"; Action = { Invoke-Publish } },
        @{ Label = "新しい変更で区切る（jj new）"; Color = "DarkCyan"; Action = { Invoke-NewChange } },
        @{ Label = "変更にコメントを付ける（desc）"; Color = "White"; Action = { Invoke-AddDescription } },
        @{ Label = "変更履歴を閲覧（log）"; Color = "DarkCyan"; Action = { Invoke-ViewHistory } },
        @{ Label = "直前の操作を取り消す（undo）"; Color = "Yellow"; Action = { Invoke-Undo } },
        @{ Label = "コンフリクトを解決（local / remote）"; Color = "Red"; Action = { Invoke-ResolveConflicts } },
        @{ Label = "保存済み設定を変更"; Color = "Yellow"; Action = { Invoke-ConfigChange } },
        @{ Label = "終了"; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-ECHeader
        Write-Host "  操作を選択してください" -ForegroundColor White
        Write-Host ""
        for ($index = 0; $index -lt $items.Count; $index++) {
            if ($index -eq $selected) {
                Write-Host "  > $($items[$index].Label)" -ForegroundColor $items[$index].Color -BackgroundColor DarkGray
            }
            else {
                Write-Host "    $($items[$index].Label)" -ForegroundColor $items[$index].Color
            }
        }

        $key = [Console]::ReadKey($true)
        switch ($key.Key) {
            "UpArrow" { $selected = ($selected - 1 + $items.Count) % $items.Count }
            "DownArrow" { $selected = ($selected + 1) % $items.Count }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でメニューに戻ります"
            }
        }
    }
}

try {
    if (-not (Test-Path -LiteralPath $script:SetupMarkerPath)) {
        if (-not (Invoke-Setup)) {
            exit 1
        }

        Write-Host ""
        Read-Host "Enter でメニューに進みます"
    }
    else {
        try {
            Set-ECProjectLocation
        }
        catch {
            Write-Host "`n保存済みプロジェクトを利用できません: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "セットアップ情報を削除して、セットアップをやり直します。" -ForegroundColor Yellow

            Remove-Item -LiteralPath $script:SetupMarkerPath -Force

            if (-not (Invoke-Setup)) {
                exit 1
            }

            Write-Host ""
            Read-Host "Enter でメニューに進みます"
        }
    }

    # JujutsuControllerの更新確認
    Test-ECUpdate

    Read-ECMenuChoice
}
catch {
    Write-Host "`n致命的なエラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}