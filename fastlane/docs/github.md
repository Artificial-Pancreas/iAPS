
## Set Up Your iAPS GitHub Repository

### Generate a Personal Access Token (PAT)

If you've already got a **Personal Access Token (PAT)**, feel free to skip this step and reuse it. Keep in mind that GitHub doesn't let you view existing tokens; you can only regenerate them. Regenerating a token makes the old one invalid, so if you're using an existing token and don't know its value, it's best to create a new one.

To generate a new PAT:

* Give your token a recognizable name, like "FastLane Access Token."
* Change the expiration time from the default 30 days to **No Expiration**.
* Select the **`repo`** permission scope.
* Click **"Generate token."**
* **Copy the generated token immediately and save it somewhere safe.** You'll need this value as `GH_PAT` later.

---

### Fork the iAPS Repository

**Important:** You can only have one fork of the iAPS repository in your GitHub account. If you already have a fork, you can either continue using it or delete it and create a new one.

Follow these steps to fork the repository:

1.  **Fork** `https://github.com/Artificial-Pancreas/iAPS` into your GitHub account.
2.  If you are using an organization, do this step at the organization level, e.g., username-org. If you are not using an organization, do this step at the repository level, e.g., username/iAPS:
    * Go to Settings -> Secrets and variables -> Actions and make sure the Secrets tab is open. 
3. For each of the following secrets, tap on "New organization secret" or "New repository secret", then add the name of the secret, along with the value you recorded for it:
    * `TEAMID`
    * `FASTLANE_KEY_ID`
    * `FASTLANE_ISSUER_ID`
    * `FASTLANE_KEY`
    * `GH_PAT` (This is the token you generated earlier)
    * `MATCH_PASSWORD` (Just create a new, strong password for this)
4. If you are using an organization, do this step at the organization level, e.g., username-org. If you are not using an organization, do this step at the repository level, e.g., username/iAPS:
    * Go to Settings -> Secrets and variables -> Actions and make sure the Variables tab is open
4. Tap on "Create new organization variable" or "Create new repository variable", then add the name below and enter the value *true*. Unlike secrets these variables are visible and can be edited.
    * `ENABLE_NUKE_CERTS`
5.  **Optional: most people should skip this step.** Neither of the following is needed for a normal build. Only add them if you specifically need the behaviour described:
    * `APP_IDENTIFIER` (secret *or* variable) - the app's bundle identifier. **Leave it unset** (do not create the secret/variable) unless you are deliberately building with a non-default bundle id (for example a second, separate app). If you don't set it, the build automatically uses `ru.artpancreas.<your team id>.FreeAPS`, with your team id filled in for you - you do **not** need to create anything or type that value anywhere (in particular, do not paste `<your team id>` or `#{TEAMID}` literally, and do not include the extra symbols: `<>`, `${}`, etc; it is just a placeholder for your team id). If you *do* need a custom value, add it as a **secret** named `APP_IDENTIFIER` (preferred, because the bundle id contains your team id, which is best kept private); a repository **variable** of the same name is still supported as a fallback.
    * `BUILD_GROUP` (variable) - leave it unset unless you're labeling a distribution or build shared by multiple users.
      
---

### Keep Your Fork Up to Date

To synchronize your forked repository with the original iAPS repository:

1.  Go to the **"Actions"** tab in your iAPS repository.
2.  Select the **"5. Sync Upstream"** workflow.
3.  Click **"Run Workflow,"** choose the branch you want to maintain, and then tap the green button.

While most users will only need to sync one branch, you can repeat this process for any branch where these workflows are available. This action is currently scheduled to run daily at midnight, but you can trigger it manually anytime.
