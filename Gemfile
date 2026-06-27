source "https://rubygems.org"

gem "fastlane", git: "https://github.com/Artificial-Pancreas/fastlane.git", branch: "master"
gem "abbrev", git: "https://github.com/ruby/abbrev.git", branch: "master"
# Ruby 3.4 dropped kconv from the default gems, but CFPropertyList (a fastlane
# dependency) still `require`s it. kconv ships inside the nkf gem, so adding nkf
# lets the build keep running on the runner's system Ruby 3.4.x instead of pinning
# back to 3.3. Mirrors the abbrev entry above (same bundled-gem removal).
gem "nkf"
