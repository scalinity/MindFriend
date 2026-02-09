# Setting Main as Default Branch

This document provides instructions for setting `main` as the default branch for the MindFriend repository.

## Current Status
- ✅ `CLAUDE.md` file has been removed from the repository
- ✅ `main` branch exists both locally and remotely
- ⚠️ Current default branch on GitHub: `feat/mood-adaptive-home`

## How to Set Main as Default Branch

The default branch can only be changed through GitHub's repository settings. Follow these steps:

### Via GitHub Web Interface

1. Go to the repository on GitHub: https://github.com/scalinity/MindFriend
2. Click on **Settings** (requires admin access)
3. In the left sidebar, click on **Branches** (under "Code and automation")
4. Under "Default branch", you'll see the current default branch (`feat/mood-adaptive-home`)
5. Click the **Switch to another branch** button (↔️ icon)
6. Select **main** from the dropdown
7. Click **Update**
8. Confirm the change in the dialog that appears

### Via GitHub CLI (if installed)

```bash
gh repo edit scalinity/MindFriend --default-branch main
```

### Via GitHub API

```bash
curl -X PATCH \
  -H "Accept: application/vnd.github+json" \
  -H "Authorization: Bearer YOUR_GITHUB_TOKEN" \
  https://api.github.com/repos/scalinity/MindFriend \
  -d '{"default_branch":"main"}'
```

## Verification

After changing the default branch, verify by:

1. Running: `git remote show origin | grep "HEAD branch"`
   - Should show: `HEAD branch: main`

2. Checking that new PRs and clones use `main` by default

## Notes

- This change only affects which branch is checked out by default when cloning or shown first in the GitHub UI
- All other branches remain unchanged
- PRs targeting the old default branch will need to be updated manually if desired
