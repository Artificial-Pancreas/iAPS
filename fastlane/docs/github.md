## Setup Github iAPS repository

If you have previously built Loop or another app using the "browser build" method, you can can re-use your previous personal access token (`GH_PAT`) and skip ahead to `step 2`.

* Create a [new personal access token](https://github.com/settings/tokens/new):
  * Enter a name for your token. Something like "FastLane Access Token".
  * The default Expiration time is 30 days - but you should select `No Expiration`
  * Select the `repo` permission scope.
  * Click "Generate token".
  * Copy the token and record it. It will be used below as `GH_PAT`.

1. Fork https://github.com/Artificial-Pancreas/iAPS into your account. If you already have a fork of iAPS in GitHub, you can't make another one. You can continue to work with your existing fork, or delete that from GitHub and then and fork https://github.com/Artificial-Pancreas/iAPS.
1. In the forked iAPS repo, go to Settings -> Secrets -> Actions.
1. For each of the following secrets, tap on "New repository secret", then add the name of the secret, along with the value you recorded for it:
    * `TEAMID`
    * `FASTLANE_KEY_ID`
    * `FASTLANE_ISSUER_ID`
    * `FASTLANE_KEY`
    * `GH_PAT`
    * `MATCH_PASSWORD` - just make up a password for this
