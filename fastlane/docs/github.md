## Setup Github iAPS repository

### Generate Personal Access Token

>    If you have previously created a Personal Access Token ( PAT ), you can re-use it,
>    and skip this step.
>
>    **NOTE:** GitHub doesn't provide a means to view a previously created token, it only 
>    allows you to regenerate it.  Regenerating the token invalidates the old one, so
>    if you already have one in use and do not know what it is, create a new one.
>
>    * Enter a name for your token. Something like "FastLane Access Token".
>    * The default Expiration time is 30 days - but you should select `No Expiration`
>    * Select the `repo` permission scope.
>    * Click "Generate token".
>    * Copy the token and record it. It will be used below as `GH_PAT`.

### Fork iAPS Repository

>   **NOTE:** If you already have a fork of iAPS in GitHub, you can't make another one. You can continue to work with your existing fork, or delete that from GitHub and fork a new >   copy.
>
>   1. Fork https://github.com/Artificial-Pancreas/iAPS into your account.
>   2. In the forked iAPS repo, go to Settings -> Secrets and Variables -> Actions
>   3. For each of the following secrets, tap on "New repository secret", then add the name of the secret, along with the value you recorded for it:
>      * `TEAMID`
>      * `FASTLANE_KEY_ID`
>      * `FASTLANE_ISSUER_ID`
>      * `FASTLANE_KEY`
>      * `GH_PAT`
>      * `MATCH_PASSWORD` - just make up a password for this
>     

### Keep Fork Up to Date

>   1. Click on the "Actions" tab of your iAPS repository.
>   2. Select "5. Sync Upstream".
>   3. Click "Run Workflow", Select Branch to Maintain, and tap the green button.
>
>   Although most people will only need to sync one branch, the above can be repeated
>   on any branch where these workflows are available.
>
>   Currently the Action is scheduled to run at midnight daily, but can be manually
>   triggered at any time.

