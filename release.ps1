$commitMessage = Read-Host "Enter commit message"

git add .

if ((git diff --cached --name-only).Length -gt 0) {
    git commit -m "$commitMessage"
}

flutter build apk --release

$version = (Get-Content pubspec.yaml |
    Select-String '^version:' |
    ForEach-Object { $_.ToString().Replace('version:','').Trim() })

git push

gh release create "v$version" `
  build/app/outputs/flutter-apk/app-release.apk `
  --generate-notes