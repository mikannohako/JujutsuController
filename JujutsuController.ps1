[Console]::InputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$ErrorActionPreference = "Stop"

$script:DefaultRepositoryUrl = "https://github.com/mikannohako/JujutsuController.git"
$script:ConfigPath = Join-Path $PSScriptRoot "config.ini"
$script:SetupMarkerPath = Join-Path $PSScriptRoot ".setup-completed"
$script:ControllerVersion = "4.0.0"
$Host.UI.RawUI.WindowTitle = "JujutsuController"

function Get-LatestRelease {
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

function Test-Update {
    try {
        $release = Get-LatestRelease

        $latestVersion = ([string]$release.tag_name).TrimStart("v")
        $latestUrl = [string]$release.html_url

        if ([version]$latestVersion -gt [version]$script:ControllerVersion) {
            Write-Host ""
            Write-Host "新しいJujutsuControllerがあります。" -ForegroundColor Yellow
            Write-Host "  現在: $script:ControllerVersion" -ForegroundColor Gray
            Write-Host "  最新: $latestVersion" -ForegroundColor Green
            Write-Host ""

            if (
                Read-YesNo -Prompt "最新版のページを開きますか？" -DefaultYes $true
            ) {
                Start-Process $latestUrl
            }
        }
    }
    catch {
        Write-Host "JujutsuControllerの更新確認中にエラーが発生しました: $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

function Write-Header {
    Clear-Host
    Write-Host ""
    Write-Host "  Jujutsu Controller" -ForegroundColor Cyan
    Write-Host "  Git / Jujutsu project toolkit" -ForegroundColor DarkCyan
    Write-Host "  Version $script:ControllerVersion" -ForegroundColor DarkGray
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

function Read-Config {
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

function Save-Config {
    param(
        [Parameter(Mandatory)] [string] $UserName,
        [Parameter(Mandatory)] [string] $UserEmail,
        [string] $RepositoryUrl = $script:DefaultRepositoryUrl,
        [AllowEmptyString()] [string] $SshSigningKey = $null
    )

    $existingConfig = Read-Config
    $projectDirectory = [string] $existingConfig["project_directory"]
    if ($null -eq $SshSigningKey) {
        $SshSigningKey = [string] $existingConfig["ssh_signing_key"]
    }
    $lines = @(
        "[user]",
        "name=$UserName",
        "email=$UserEmail",
        "repository_url=$RepositoryUrl",
        "project_directory=$projectDirectory",
        "ssh_signing_key=$SshSigningKey",
        ""
    )
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllLines($script:ConfigPath, $lines, $utf8NoBom)
}

function Save-ProjectDirectory {
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

function Get-ProjectDirectory {
    $config = Read-Config
    $projectDirectory = [string] $config["project_directory"]
    if ([string]::IsNullOrWhiteSpace($projectDirectory)) {
        throw "セットアップ先のプロジェクトフォルダが設定されていません。セットアップを再実行してください。"
    }
    if (-not (Test-Path -LiteralPath $projectDirectory -PathType Container)) {
        throw "保存済みのプロジェクトフォルダが見つかりません: $projectDirectory"
    }

    $resolvedProjectDirectory = (Resolve-Path -LiteralPath $projectDirectory).Path
    $hasRepository = Test-Path -LiteralPath (Join-Path $resolvedProjectDirectory ".jj")
    $hasGitRepository = Test-Path -LiteralPath (Join-Path $resolvedProjectDirectory ".git")
    if (-not ($hasRepository -or $hasGitRepository)) {
        throw "保存済みのフォルダは Git/Jujutsu リポジトリではありません: $resolvedProjectDirectory"
    }

    return $resolvedProjectDirectory
}

function Set-ProjectLocation {
    $projectDirectory = Get-ProjectDirectory
    Set-Location -LiteralPath $projectDirectory
}

function Get-RepositoryUrl {
    $config = Read-Config
    $repositoryUrl = [string] $config["repository_url"]
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        return $script:DefaultRepositoryUrl
    }
    return $repositoryUrl
}

function Get-SshSigningKey {
    $config = Read-Config
    return [string] $config["ssh_signing_key"]
}

function Test-SshSigningKey {
    param([Parameter(Mandatory)] [string] $PublicKey)

    $normalizedKey = ($PublicKey -replace "`r`n", "`n").Trim()
    $keyLines = @($normalizedKey -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if ($keyLines.Count -ne 1) {
        throw "SSH公開鍵は1行で入力してください。秘密鍵の内容は指定しないでください。"
    }
    if ($keyLines[0] -notmatch '^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521))\s+\S+(?:\s+.*)?$') {
        throw "SSH公開鍵の形式を確認できません。ssh-ed25519、ssh-rsa、またはECDSA公開鍵を指定してください。"
    }
    return $keyLines[0].Trim()
}

function Remove-OptionalConfigValue {
    param(
        [Parameter(Mandatory)] [string] $Command,
        [Parameter(Mandatory)] [string[]] $Arguments,
        [Parameter(Mandatory)] [int[]] $AllowedExitCodes
    )

    & $Command @Arguments
    if ($LASTEXITCODE -notin $AllowedExitCodes) {
        throw "コマンドに失敗しました: $Command $($Arguments -join ' ')"
    }
}

function Set-SshSigningConfiguration {
    param(
        [Parameter(Mandatory)] [AllowEmptyString()] [string] $PublicKey
    )

    if ([string]::IsNullOrWhiteSpace($PublicKey)) {
        Remove-OptionalConfigValue "git" @("config", "--global", "--unset", "gpg.format") @(0, 5)
        Remove-OptionalConfigValue "git" @("config", "--global", "--unset", "user.signingkey") @(0, 5)
        Remove-OptionalConfigValue "git" @("config", "--global", "--unset", "commit.gpgsign") @(0, 5)
        Remove-OptionalConfigValue "jj" @("config", "unset", "--user", "signing.backend") @(0, 1)
        Remove-OptionalConfigValue "jj" @("config", "unset", "--user", "signing.key") @(0, 1)
        return
    }

    $normalizedKey = Test-SshSigningKey -PublicKey $PublicKey
    Invoke-RequiredCommand "git" @("config", "--global", "gpg.format", "ssh")
    Invoke-RequiredCommand "git" @("config", "--global", "user.signingkey", $normalizedKey)
    Invoke-RequiredCommand "git" @("config", "--global", "commit.gpgsign", "true")
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "signing.backend", "ssh")
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "signing.key", $normalizedKey)

    try {
        Set-Clipboard -Value $normalizedKey
        Write-Host "公開鍵をクリップボードへコピーしました。" -ForegroundColor Green
    }
    catch {
        Write-Host "公開鍵のクリップボードへのコピーに失敗しました: $($_.Exception.Message)" -ForegroundColor Yellow
    }
    Write-Host "GitHubの SSH signing key 登録画面で公開鍵を登録してください。" -ForegroundColor Yellow
    if (Read-YesNo -Prompt "GitHubの登録画面を開きますか？" -DefaultYes $true) {
        Start-Process "https://github.com/settings/keys"
    }
}

function Read-SshSigningSettings {
    param([Parameter(Mandatory)] [string] $UserEmail)

    $currentKey = Get-SshSigningKey
    if (-not [string]::IsNullOrWhiteSpace($currentKey) -and
        (Test-Path -LiteralPath $currentKey -PathType Leaf)) {
        $currentKey = [System.IO.File]::ReadAllText($currentKey).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($currentKey)) {
        Write-Host ""
        Write-Host "保存済みのSSH署名鍵: $currentKey" -ForegroundColor Cyan
        $decision = Read-Host "このSSH署名鍵を利用しますか？ [Y/n/D(解除)]"
        if ([string]::IsNullOrWhiteSpace($decision) -or $decision -match '^(?i)y(es)?$') {
            $normalizedKey = Test-SshSigningKey -PublicKey $currentKey
            Set-SshSigningConfiguration -PublicKey $normalizedKey
            return $normalizedKey
        }
        if ($decision -match '^(?i)d(elete)?$') {
            Set-SshSigningConfiguration -PublicKey ""
            return ""
        }
    }

    if (Read-YesNo -Prompt "SSH署名鍵を設定・変更しますか？" -DefaultYes $False) {
        return $currentKey
    } else {
        return ""
        Write-Host "設定は行いませんでした。" -ForegroundColor Green
    }

    Write-Host "公開鍵の指定方法を選択してください。" -ForegroundColor Cyan
    Write-Host "  F: 公開鍵ファイルを読み込む"
    Write-Host "  T: 公開鍵を文章で入力する"
    $inputMethod = Read-Host "指定方法 [F/T]"
    if ($inputMethod -match '^(?i)f(ile)?$') {
        $keyPath = Read-Host "SSH公開鍵ファイルのパス"
        if ([string]::IsNullOrWhiteSpace($keyPath)) {
            throw "SSH公開鍵ファイルのパスが入力されていません。"
        }
        $resolvedPath = [System.IO.Path]::GetFullPath($keyPath.Trim().Trim('"'))
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "SSH公開鍵ファイルが見つかりません: $resolvedPath"
        }
        $inputKey = [System.IO.File]::ReadAllText($resolvedPath)
    }
    elseif ($inputMethod -match '^(?i)t(ext)?$') {
        $inputKey = Read-Host "SSH公開鍵を1行で入力してください"
    }
    else {
        throw "公開鍵の指定方法は F または T です。"
    }

    $normalizedKey = Test-SshSigningKey -PublicKey $inputKey
    Set-SshSigningConfiguration -PublicKey $normalizedKey
    return $normalizedKey
}

function Read-RepositorySettings {
    param([Parameter(Mandatory)] [hashtable] $UserSettings)

    $currentRepositoryUrl = Get-RepositoryUrl
    Write-Host ""
    Write-Host "cloneするリポジトリを選択してください。" -ForegroundColor Cyan
    $repositoryUrl = Read-Host "リポジトリURL [$currentRepositoryUrl]"
    if ([string]::IsNullOrWhiteSpace($repositoryUrl)) {
        $repositoryUrl = $currentRepositoryUrl
    }
    Test-RepositoryUrl -RepositoryUrl $repositoryUrl

    if (Read-YesNo -Prompt "このリポジトリURLを設定に保存しますか？" -DefaultYes $true) {
        Save-Config -UserName $UserSettings.Name -UserEmail $UserSettings.Email -RepositoryUrl $repositoryUrl
        Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
    }
    else {
        Write-Host "リポジトリURLは保存せず、今回のセットアップだけで利用します。" -ForegroundColor Yellow
    }

    return $repositoryUrl
}

function Test-RepositoryUrl {
    param([Parameter(Mandatory)] [string] $RepositoryUrl)

    if ($RepositoryUrl -match '^git@[^:]+:.+$') {
        return
    }

    $uri = $null
    if (-not [Uri]::TryCreate($RepositoryUrl, [UriKind]::Absolute, [ref] $uri) -or $uri.Scheme -notin @("http", "https", "ssh", "git")) {
        throw "リポジトリURLが正しくありません。"
    }
}

function Read-YesNo {
    param(
        [Parameter(Mandatory)] [string] $Prompt,
        [Parameter()] [bool] $DefaultYes = $true
    )

    $defaultOption = if ($DefaultYes) { "Y/n" } else { "y/N" }
    while ($true) {
        $response = Read-Host "$Prompt [$defaultOption]"
        if ([string]::IsNullOrWhiteSpace($response)) {
            return $DefaultYes
        }
        if ($response -match '^(?i)y(es)?$') {
            return $true
        }
        if ($response -match '^(?i)n(o)?$') {
            return $false
        }
        Write-Host "有効な入力ではありません。Y または N を入力してください。" -ForegroundColor Yellow
    }
}

function Read-UserSettings {
    $config = Read-Config
    $savedName = [string] $config["name"]
    $savedEmail = [string] $config["email"]
    $hasSavedSettings = -not [string]::IsNullOrWhiteSpace($savedName) -and -not [string]::IsNullOrWhiteSpace($savedEmail)

    if ($hasSavedSettings) {
        Write-Host "保存済みの設定が見つかりました。" -ForegroundColor Cyan
        Write-Host "  名前: $savedName" -ForegroundColor DarkGray
        Write-Host "  メール: $savedEmail" -ForegroundColor DarkGray
        if (Read-YesNo "この設定を利用しますか？" $true) {
            return @{ Name = $savedName; Email = $savedEmail }
        }
    }
    
    $userName = Read-Host "Git ユーザー名"
    $userEmail = Read-Host "Git メールアドレス"
    if ([string]::IsNullOrWhiteSpace($userName) -or [string]::IsNullOrWhiteSpace($userEmail)) {
        throw "名前とメールアドレスは必須です。"
    }

    if (Read-YesNo "設定を保存しますか？" $true) {
        Save-Config -UserName $userName -UserEmail $userEmail -RepositoryUrl (Get-RepositoryUrl)
        Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
    }
    else {
        Write-Host "設定は保存せず、この処理でのみ利用します。" -ForegroundColor Yellow
    }
    return @{ Name = $userName; Email = $userEmail }
}

function Invoke-ConfigChange {
    Write-Header
    try {
        $config = Read-Config
        $currentName = [string] $config["name"]
        $currentEmail = [string] $config["email"]
        $currentRepositoryUrl = Get-RepositoryUrl
        $currentSshSigningKey = [string] $config["ssh_signing_key"]
        $sshSigningLabel = if ([string]::IsNullOrWhiteSpace($currentSshSigningKey)) { "未設定" } else { $currentSshSigningKey }

        $settings = @(
            [PSCustomObject]@{ Label = "Git ユーザー名"; Key = "name"; Value = $currentName },
            [PSCustomObject]@{ Label = "Git メールアドレス"; Key = "email"; Value = $currentEmail },
            [PSCustomObject]@{ Label = "リポジトリURL"; Key = "repository_url"; Value = $currentRepositoryUrl },
            [PSCustomObject]@{ Label = "SSH署名鍵"; Key = "ssh_signing_key"; Value = $sshSigningLabel }
        )
        $selected = 0
        $itemCount = $settings.Count + 1
        while ($true) {
            Write-Header
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
        if ($setting.Key -eq "ssh_signing_key") {
            $newSshSigningKey = Read-SshSigningSettings -UserEmail $currentEmail
            Save-Config `
                -UserName $currentName `
                -UserEmail $currentEmail `
                -RepositoryUrl $currentRepositoryUrl `
                -SshSigningKey $newSshSigningKey
            Write-Host "SSH署名鍵の設定を更新しました。" -ForegroundColor Green
            return
        }

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
        Test-RepositoryUrl -RepositoryUrl $newRepositoryUrl
        Save-Config -UserName $newName -UserEmail $newEmail -RepositoryUrl $newRepositoryUrl
        Write-Host "設定を保存しました: $script:ConfigPath" -ForegroundColor Green
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

function Select-ProjectDirectory {
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
        $hasRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".jj")
        $hasGitRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".git")
        $hasExistingFiles = @(Get-ChildItem -LiteralPath $projectDirectory -Force).Count -gt 0
        if ($hasExistingFiles -and -not ($hasRepository -or $hasGitRepository)) {
            throw "選択した場所に既存のファイルがあります: $projectDirectory"
        }
    }

    return $projectDirectory
}

function Initialize-Repository {
    $projectDirectory = Select-ProjectDirectory

    New-Item -ItemType Directory -Path $projectDirectory -Force | Out-Null
    Set-Location $projectDirectory

    $userSettings = Read-UserSettings
    $repositoryUrl = Read-RepositorySettings -UserSettings $userSettings
    $sshSigningKey = Read-SshSigningSettings -UserEmail $userSettings.Email
    Save-Config `
        -UserName $userSettings.Name `
        -UserEmail $userSettings.Email `
        -RepositoryUrl $repositoryUrl `
        -SshSigningKey $sshSigningKey

    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.name", $userSettings.Name)
    Invoke-RequiredCommand "jj" @("config", "set", "--user", "user.email", $userSettings.Email)

    $hasRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".jj")
    $hasGitRepository = Test-Path -LiteralPath (Join-Path $projectDirectory ".git")
    if ($hasRepository -or $hasGitRepository) {
        Write-Host "既存のリポジトリを使用します..." -ForegroundColor Yellow
    }
    else {
        Write-Host "リポジトリを取得しています..." -ForegroundColor Yellow
        Invoke-RequiredCommand "jj" @("git", "clone", $repositoryUrl, ".")
    }
    Save-ProjectDirectory -ProjectDirectory $projectDirectory
    explorer.exe $projectDirectory

    Write-Host "セットアップ先: $projectDirectory" -ForegroundColor Green
}

function Invoke-Setup {
    Write-Header
    $total = 3
    try {
        Write-StageProgress 1 $total "JC セットアップ" "必要なツールを確認しています..."
        Install-RequiredTools

        Write-StageProgress 2 $total "JC セットアップ" "リポジトリ設定を準備しています..."
        if (-not (Test-CommandAvailable "jj")) {
            throw "PATH 再読み込み後も jj が見つかりません。新しい PowerShell で再実行してください。"
        }

        Write-StageProgress 3 $total "JC セットアップ" "ユーザー設定とリポジトリを準備しています..."
        Initialize-Repository
        
        Set-Content -LiteralPath $script:SetupMarkerPath -Value "completed" -Encoding utf8
        Write-Host "`nセットアップが完了しました。" -ForegroundColor Green
        Write-Host ""
        Read-Host "Enter キーを押して続行してください..."
        return $true
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

function Invoke-Update {
    Write-Header
    try {
        Write-StageProgress 1 2 "JC 更新" "サーバーから最新情報を取得しています..."
        Invoke-RequiredCommand "jj" @("git", "fetch")

        Write-StageProgress 2 2 "JC 更新" "最新の main に合わせています..."
        Invoke-RequiredCommand "jj" @("rebase", "-d", "main@origin")
        
        Write-Host "`n更新が完了しました。`n" -ForegroundColor Green
        Write-Host "現在の状態:" -ForegroundColor Cyan
        & jj status
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "コンフリクトなどが発生している可能性があります。コンフリクトを解決してください。" -ForegroundColor Yellow
    }
}

function Get-Branches {
    $branchLines = @(& jj bookmark list)
    if ($LASTEXITCODE -ne 0) {
        throw "コマンドに失敗しました: jj bookmark list"
    }

    $branches = @()
    foreach ($line in $branchLines) {
        if ([string]$line -match '^\s*([^:\s]+)\s*:') {
            $branches += $Matches[1]
        }
    }

    return @($branches | Select-Object -Unique)
}

function Invoke-BranchSwitch {
    Write-Header
    try {
        $branches = @(Get-Branches)
        if ($branches.Count -eq 0) {
            Write-Host "切り替え可能なブランチがありません。" -ForegroundColor Yellow
            return
        }

        $itemCount = $branches.Count + 1
        $selected = 0
        while ($true) {
            Write-Header
            Write-Host "  切り替えるブランチを選択してください。" -ForegroundColor Cyan
            Write-Host "  上下:選択  Enter:決定  Esc:キャンセル" -ForegroundColor DarkCyan
            Write-Host ""
            for ($index = 0; $index -lt $branches.Count; $index++) {
                if ($index -eq $selected) {
                    Write-Host "  > $($branches[$index])" -ForegroundColor White -BackgroundColor DarkGray
                }
                else {
                    Write-Host "    $($branches[$index])" -ForegroundColor Gray
                }
            }

            if ($selected -eq $branches.Count) {
                Write-Host "  > キャンセル" -ForegroundColor Yellow -BackgroundColor DarkGray
            }
            else {
                Write-Host "    キャンセル" -ForegroundColor Yellow
            }
            $key = [Console]::ReadKey($true)
            switch ($key.Key) {
                "UpArrow" { $selected = ($selected - 1 + $itemCount) % $itemCount }
                "DownArrow" { $selected = ($selected + 1) % $itemCount }
                "Escape" { return }
                "Enter" { break }
            }
            if ($key.Key -eq "Enter") {
                break
            }
        }

        if ($selected -eq $branches.Count) {
            return
        }

        $branch = $branches[$selected]
        Write-Host ""
        Write-Host "選択したブランチ: $branch" -ForegroundColor Cyan
        Write-Host "現在の作業変更をこのブランチ上の新しい変更へ切り替えます。" -ForegroundColor Yellow
        
        if (Read-YesNo -Prompt "続行しますか？" -DefaultYes $False) {
            Write-Host "ブランチ切り替えをキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "ブランチ切り替え" "$branch に切り替えています..."
        Invoke-RequiredCommand "jj" @("new", $branch)
        
        Write-Host "`nブランチを切り替えました: $branch" -ForegroundColor Green
        Write-Host "新しい作業変更で作業を開始できます。" -ForegroundColor DarkGray
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchCreate {
    Write-Header
    try {
        $branch = Read-Host "作成するブランチ名（空白でキャンセル）"
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "ブランチ作成をキャンセルしました。" -ForegroundColor Yellow
            return
        }
        if ($branch -notmatch '^[A-Za-z0-9._/-]+$') {
            throw "ブランチ名に使用できない文字が含まれています。"
        }

        Write-StageProgress 1 1 "ブランチ作成" "$branch を作成しています..."
        Invoke-RequiredCommand "jj" @("bookmark", "create", $branch, "-r", "@")
        
        Write-Host "`nブランチを作成しました: $branch" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchDelete {
    Write-Header
    try {
        $branches = @(Get-Branches)
        if ($branches.Count -eq 0) {
            Write-Host "削除できるブランチがありません。" -ForegroundColor Yellow
            return
        }

        Write-Host "削除するブランチ名を入力してください。" -ForegroundColor Cyan
        $branch = Read-Host "ブランチ名（空白でキャンセル）"
        if ([string]::IsNullOrWhiteSpace($branch)) {
            Write-Host "ブランチ削除をキャンセルしました。" -ForegroundColor Yellow
            return
        }
        if ($branches -notcontains $branch) {
            throw "指定したブランチが見つかりません: $branch"
        }

        Write-Host "削除対象: $branch" -ForegroundColor Yellow
        if (Read-YesNo -Prompt "このブランチを削除しますか？" -DefaultYes $False) {
            Write-Host "ブランチ削除をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "ブランチ削除" "$branch を削除しています..."
        Invoke-RequiredCommand "jj" @("bookmark", "delete", $branch)
        
        Write-Host "`nブランチを削除しました: $branch" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchMerge {
    Write-Header
    try {
        $branches = @(Get-Branches)
        if ($branches.Count -lt 2) {
            Write-Host "マージには2つ以上のブランチが必要です。" -ForegroundColor Yellow
            return
        }

        Write-Host "マージ先（変更を取り込む側）を入力してください。" -ForegroundColor Cyan
        $target = Read-Host "マージ先ブランチ名（空白でキャンセル）"
        if ([string]::IsNullOrWhiteSpace($target)) {
            Write-Host "ブランチマージをキャンセルしました。" -ForegroundColor Yellow
            return
        }
        if ($branches -notcontains $target) {
            throw "マージ先ブランチが見つかりません: $target"
        }

        Write-Host "マージ元（取り込む側）を入力してください。" -ForegroundColor Cyan
        $source = Read-Host "マージ元ブランチ名（空白でキャンセル）"
        if ([string]::IsNullOrWhiteSpace($source)) {
            Write-Host "ブランチマージをキャンセルしました。" -ForegroundColor Yellow
            return
        }
        if ($branches -notcontains $source) {
            throw "マージ元ブランチが見つかりません: $source"
        }
        if ($target -eq $source) {
            throw "マージ先とマージ元には別のブランチを指定してください。"
        }

        Write-Host "$source を $target にマージします。" -ForegroundColor Yellow
        if (Read-YesNo -Prompt "実行しますか？" -DefaultYes $False) {
            Write-Host "ブランチマージをキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 2 "ブランチマージ" "マージ変更を作成しています..."
        Invoke-RequiredCommand "jj" @("new", $target, $source)
        Write-StageProgress 2 2 "ブランチマージ" "$target をマージ結果へ更新しています..."
        Invoke-RequiredCommand "jj" @("bookmark", "set", $target, "-r", "@")
        
        Write-Host "`nブランチをマージしました: $source -> $target" -ForegroundColor Green
        Write-Host "必要に応じて「変更を保存」から push してください。" -ForegroundColor DarkGray
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-BranchManagement {
    $items = @(
        @{ Label = "ブランチを切り替え"; Color = "Magenta"; Action = { Invoke-BranchSwitch } },
        @{ Label = "ブランチを作成"; Color = "Green"; Action = { Invoke-BranchCreate } },
        @{ Label = "ブランチをマージ"; Color = "Blue"; Action = { Invoke-BranchMerge } },
        @{ Label = "ブランチを削除"; Color = "Red"; Action = { Invoke-BranchDelete } },
        @{ Label = "戻る"; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-Header
        Write-Host "  ブランチ操作を選択してください" -ForegroundColor White
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
            "Escape" { return }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でブランチ操作メニューに戻ります"
            }
        }
    }
}

function Invoke-Publish {
    Write-Header
    try {

        Invoke-Update

        Write-StageProgress 1 4 "JC 保存" "変更を確認しています..."
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

            if ( Read-YesNo -Prompt "このコメントを利用しますか？" -DefaultYes $true) {
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
            
            Write-Host "`n保存をキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 2 4 "JC 保存" "変更にコメントを設定しています..."
        Invoke-RequiredCommand "jj" @("desc", "-m", $comment)

        Write-StageProgress 3 4 "JC 保存" "main を更新しています..."
        Invoke-RequiredCommand "jj" @("bookmark", "set", "main", "-r", "@")

        Write-StageProgress 4 4 "JC 保存" "サーバーへアップロードしています..."
        Invoke-RequiredCommand "jj" @("git", "push")
        
        Write-Host "`nアップロードが完了しました。" -ForegroundColor Green
        Write-Host "コメント: $comment" -ForegroundColor DarkGray
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-NewChange {
    Write-Header
    try {
        Write-Host "新しい変更のコメントを入力してください。（空白でキャンセル）" -ForegroundColor Cyan
        $comment = Read-Host "変更コメント"
        if ([string]::IsNullOrWhiteSpace($comment)) {
            
            Write-Host "`n変更をキャンセルしました。" -ForegroundColor Yellow
            return
        }
        Write-StageProgress 1 1 "JC 区切り" "新しい変更を作成しています..."
        Invoke-RequiredCommand "jj" @("new", "-m", $comment)
        
        Write-Host "`n新しい変更を作成しました。" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ChangeDescriptionMenu {
    $items = @(
        @{ Label = "新しい変更で区切る"; Color = "DarkCyan"; Action = { Invoke-NewChange } },
        @{ Label = "既存の変更にコメントを付ける"; Color = "White"; Action = { Invoke-AddDescription } },
        @{ Label = "変更履歴を閲覧"; Color = "DarkCyan"; Action = { Invoke-ViewHistory } },
        @{ Label = "戻る"; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-Header
        Write-Host "  変更の区切り・コメント設定" -ForegroundColor White
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
            "Escape" { return }
            "Enter" {
                if ($selected -eq ($items.Count - 1)) { return }
                & $items[$selected].Action
                Write-Host ""
                Read-Host "Enter でメニューに戻ります"
            }
        }
    }
}

function Invoke-AddDescription {
    Write-Header
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
                Write-Header
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
            
            Write-Host "`nコメントを設定しました。" -ForegroundColor Green
            Write-Host "続けて別の変更にもコメントを設定できます。" -ForegroundColor DarkCyan
        }
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-Undo {
    Write-Header
    try {
        Write-Host "直前の操作を取り消します。" -ForegroundColor Yellow
        
        if (Read-YesNo -Prompt "取り消しますか？" -DefaultYes $False) {
            Write-Host "取り消しをキャンセルしました。" -ForegroundColor Yellow
            return
        }

        Write-StageProgress 1 1 "JC Undo" "直前の操作を取り消しています..."
        Invoke-RequiredCommand "jj" @("undo")
        
        Write-Host "`n直前の操作を取り消しました。" -ForegroundColor Green
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Get-ConflictFiles {
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
        $conflictFiles = @(Get-ConflictFiles)
        if ($conflictFiles.Count -eq 0) {
            Write-Header
            Write-Host "  コンフリクトがありません。" -ForegroundColor Green
            return
        }

        $selected = 0
        while ($true) {
            Write-Header
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
        
        Write-Host "`nコンフリクトを解決しました: $conflictPath" -ForegroundColor Green
    }
    catch {
        
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

        
        if ($changedFiles.Count -eq 0) {
            Write-Header
            Write-Host "  変更されたファイルはありません。" -ForegroundColor Green
            return
        }

        Read-ChangedFileChoice -ChangedFiles $changedFiles
    }
    catch {
        
        Write-Host "`nエラー: $($_.Exception.Message)" -ForegroundColor Red
    }
}

function Invoke-ViewHistory {
    Write-Header
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

function Get-StatusColor {
    param([Parameter(Mandatory)] [string] $Status)

    switch ($Status) {
        "M" { return "Yellow" }
        "A" { return "Green" }
        "D" { return "Red" }
        "R" { return "Cyan" }
        default { return "Gray" }
    }
}

function Read-ChangedFileChoice {
    param([Parameter(Mandatory)] [array] $ChangedFiles)

    $selected = 0
    while ($true) {
        Write-Header
        Write-Host "  変更されたファイル" -ForegroundColor White
        Write-Host "  M:変更  A:追加  D:削除  R:名前変更" -ForegroundColor DarkGray
        Write-Host ""

        for ($index = 0; $index -lt $ChangedFiles.Count; $index++) {
            $file = $ChangedFiles[$index]
            $color = Get-StatusColor -Status $file.Status
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
                Show-FileDiff -Path $ChangedFiles[$selected].Path
            }
        }
    }
}

function Show-FileDiff {
    param([Parameter(Mandatory)] [string] $Path)

    Write-Header
    Write-Host "  [$Path]" -ForegroundColor Cyan
    Write-Host ""
    & jj diff -- $Path
    if ($LASTEXITCODE -ne 0) {
        Write-Host "`n差分の表示に失敗しました。" -ForegroundColor Red
    }
    Write-Host ""
    Read-Host "Enter でファイル一覧に戻ります"
}

function Read-MenuChoice {
    $items = @(
        @{ Label = "最新の情報を取得"; Color = "Blue"; Action = { Invoke-Update } },
        @{ Label = "変更を保存"; Color = "Green"; Action = { Invoke-Publish } },
        @{ Label = "変更を確認"; Color = "Cyan"; Action = { Invoke-ReviewChanges } },
        @{ Label = "変更を区切る / コメントを付け / 変更履歴"; Color = "DarkCyan"; Action = { Invoke-ChangeDescriptionMenu } },
        @{ Label = "ブランチ操作（切り替え / 作成 / マージ / 削除）"; Color = "Magenta"; Action = { Invoke-BranchManagement } },
        @{ Label = "直前の操作を取り消す"; Color = "Yellow"; Action = { Invoke-Undo } },
        @{ Label = "コンフリクトを解決"; Color = "Red"; Action = { Invoke-ResolveConflicts } },
        @{ Label = "保存済み設定を変更"; Color = "Yellow"; Action = { Invoke-ConfigChange } },
        @{ Label = "終了"; Color = "Gray"; Action = { return } }
    )
    $selected = 0

    while ($true) {
        Write-Header
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

        Invoke-Update

        Write-Host ""
        Read-Host "Enter でメニューに進みます"
    }
    else {
        try {
            Set-ProjectLocation
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
    Test-Update

    Read-MenuChoice
}
catch {
    Write-Host "`n致命的なエラー: $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}