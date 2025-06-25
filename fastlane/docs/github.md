
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
2.  In your newly forked iAPS repository, navigate to **Settings > Secrets and Variables > Actions**.
3.  Add the following secrets by clicking **"New repository secret"** for each one. Enter the secret name and its corresponding value:
    * `TEAMID`
    * `FASTLANE_KEY_ID`
    * `FASTLANE_ISSUER_ID`
    * `FASTLANE_KEY`
    * `GH_PAT` (This is the token you generated earlier)
    * `MATCH_PASSWORD` (Just create a new, strong password for this)
4.  Under the **Variables** tab (also within Secrets and Variables), set the following two variables:
    * `APP_IDENTIFIER`: This defaults to `ru.artpancreas.#{TEAMID}.FreeAPS` if you don't set it.
    * `BUILD_GROUP`: This variable is typically left blank unless you're labeling a distribution or build shared by multiple users.

---

### Keep Your Fork Up to Date

To synchronize your forked repository with the original iAPS repository:

1.  Go to the **"Actions"** tab in your iAPS repository.
2.  Select the **"5. Sync Upstream"** workflow.
3.  Click **"Run Workflow,"** choose the branch you want to maintain, and then tap the green button.

While most users will only need to sync one branch, you can repeat this process for any branch where these workflows are available. This action is currently scheduled to run daily at midnight, but you can trigger it manually anytime.
