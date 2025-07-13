# iAPS: Your Experimental Artificial Pancreas System for iOS

iAPS is an advanced artificial pancreas system for iOS, built upon the foundation of Ivan Valkou's original `freeaps.git` Swift repository and powered by the **OpenAPS Reference (Master 0.7.1)** algorithms. After thousands of commits and the addition of many unique features, the app has been rebranded as iAPS under the new organization, Artificial Pancreas. We also leverage numerous frameworks published by the **Loop community** to bring you this robust system.

-----

## Get Started with iAPS

Ready to explore iAPS? Here's how you can download and build the repository:

### Download the Repo

  * **Using Terminal:**

    ```bash
    git clone --branch=main https://github.com/artificial-pancreas/iaps.git
    cd iaps
    xed .
    ```

  * **Using the GitHub Interface:**
    Simply navigate to the iAPS GitHub page, click the green **"Code"** button, and select **"Open with Xcode."**

### Build Without Xcode (Directly in GitHub)

For instructions on how to build iAPS directly within GitHub, refer to these resources:

  * **iAPS-Specific Instructions:** [https://github.com/Artificial-Pancreas/iAPS/blob/main/fastlane/testflight.md](https://github.com/Artificial-Pancreas/iAPS/blob/main/fastlane/testflight.md)
  * **General GitHub Actions Overview:** [https://loopkit.github.io/loopdocs/gh-actions/gh-overview/](https://loopkit.github.io/loopdocs/gh-actions/gh-overview/)

-----

## Important Considerations

Please understand that iAPS is:

  * **Highly experimental and rapidly evolving.**
  * **Not CE or FDA approved for therapy.**

-----

## Compatible Devices

### Insulin Pumps

  * **Omnipod EROS**
  * **Omnipod DASH**
  * **Dana:**
      * Dana-I
      * DanaRS (firmware 3 only)
  * **Medtronic:**
      * 515 or 715 (any firmware)
      * 522 or 722 (any firmware)
      * 523 or 723 (firmware 2.4 or lower)
      * Worldwide Veo 554 or 754 (firmware 2.6A or lower)
      * Canadian/Australian Veo 554 or 754 (firmware 2.7A or lower)

### CGM Sensors

  * **Dexcom:**
      * G5
      * G6
      * ONE
      * ONE +
      * G7
  * **Libre:**
      * 1
      * 2 (European)
      * 2 Plus (European)
  * **Medtronic Enlite**
  * **Nightscout** (as CGM)

### iPhone and iPod Compatibility

The iAPS app runs on your **iPhone** or **iPod**. An **iPhone 8 or newer** is required, running a **minimum of iOS 17**.

-----

## Documentation and Community

Connect with the iAPS community and find helpful resources here:

  * **Discord iAPS Server:** [https://discord.com/invite/ptkk2Y264Z](https://discord.com/invite/ptkk2Y264Z)
  * **Facebook Group:** [https://www.facebook.com/groups/403549385863967](https://www.facebook.com/groups/403549385863967)
  * **iAPS Statistics:** [https://open-iaps.org](https://open-iaps.org)
  * **iAPS Documentation (under development):** [https://iaps.readthedocs.io/en/latest/](https://iaps.readthedocs.io/en/latest/)
  * **OpenAPS Documentation:** [https://openaps.readthedocs.io/en/latest/](https://openaps.readthedocs.io/en/latest/)
  * **Crowdin Project for iAPS Translation:** [https://crowdin.com/project/iaps](https://crowdin.com/project/iaps)
    [](https://crowdin.com/project/iaps)
  * **Middleware code for iAPS:** [https://github.com/Jon-b-m/middleware](https://github.com/Jon-b-m/middleware)
  * **Omnipod DASH Pump and Settings:** [https://loopkit.github.io/loopdocs/loop-3/omnipod/](https://loopkit.github.io/loopdocs/loop-3/omnipod/)

-----

## Contribute to iAPS

We welcome your contributions to improve iAPS\!

  * **Code contributions** via Pull Requests are highly encouraged.
  * **Translators** can join our Crowdin project by clicking the link above.
  * For **questions or other contributions**, please email jon.m@live.se.
