flutter build apk --release

$version = (Get-Content pubspec.yaml |
    Select-String '^version:' |
    ForEach-Object { $_.ToString().Replace('version:','').Trim() })

git push

gh release create "v$version" `
  build/app/outputs/flutter-apk/app-release.apk `
  --generate-notes