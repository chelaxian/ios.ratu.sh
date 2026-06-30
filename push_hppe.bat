@echo off
:: HPPE v0.6.4 push script
:: Runs git push from the ios-ratu-sh-repo. Use this after waking up
:: to publish the v0.6.4 commit (3b6a029) to github.

cd /d "C:\Users\chelaxian\Documents\iPhone 14 Pro Max iOS 17.0 semi-jailbreak Roothide Bootstrap 2.2\ios-ratu-sh-repo"

echo === Current local commit ===
git log --oneline -3

echo.
echo === Checking remote ===
git remote -v

echo.
echo === Pushing to origin/main ===
git push origin main 2>&1

if %ERRORLEVEL% NEQ 0 (
    echo.
    echo Push failed. Options:
    echo   1. gh auth login    (interactively authenticate GitHub CLI)
    echo   2. git push with a personal access token
    echo   3. Use the GitHub web UI: go to github.com/chelaxian/ios.ratu.sh
    echo      ^|^| settings ^|^| GitHub Apps ^|^| Personal access tokens
    echo      Generate a token, then:
    echo      set GITHUB_TOKEN=ghp_xxx
    echo      git -c credential.helper=push origin main
)

echo.
echo === After push, verify with: ===
echo   git log --oneline -5
echo   (should show 3b6a029 on origin/main)
