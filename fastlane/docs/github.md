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

>   In order to ensure your fork is kept up to date with changes, there is a GitHub App availabled
>   called **Pull**.   By default, your fork already has the config file in place for this, so if you
>   are not a developer, all you need to do is install the app, and everything will be handled
>   automatically for you.
>
>   To install App, go to [Pull App Repository](https://github.com/apps/pull), and click `Install`
>
>   **For Developers**
>
>   > It is recommended that you do not modify code in either the **main** or **dev** branches, as they
>   > should be in sync with the main repository.  If you follow that recommendation, then you can use
>   > **Pull** as described above without any modifications.
>   >
>   > Do to how **Pull** resets the branches it is monitoriing, you can not modify the **pull.yml** in
>   > the **main** branch, since the sync process will reset it to the same as the master repository.
>   >
>   > If you need to modify **pull.yml**, to auto sync other branches maybe, or to disable sync of **dev**,
>   > please check the [Advanced Setup](https://wei.github.io/pull) Section in the docs.
