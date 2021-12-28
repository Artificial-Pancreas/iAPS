# FreeAPS X

FreeAPS X - an artificial pancreas system for iOS based on [OpenAPS Reference](https://github.com/openaps/oref0) algorithms

FreeAPS X uses original JavaScript files of oref0 and provides a user interface (UI) to control and set up the system

## Documentation

[Overview & Onboarding Tips on Loop&Learn](https://www.loopandlearn.org/freeaps-x/)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

## Smartphone requirements

- All iPhones which support iOS 15 and up.

## Supported pumps

To control an insulin pump FreeAPS X uses modified [rileylink_ios](https://github.com/ps2/rileylink_ios) library, thus supporting the same pump list:

- Medtronic 515 or 715 (any firmware)
- Medtronic 522 or 722 (any firmware)
- Medtronic 523 or 723 (firmware 2.4 or lower)
- Medtronic Worldwide Veo 554 or 754 (firmware 2.6A or lower)
- Medtronic Canadian/Australian Veo 554 or 754 (firmware 2.7A or lower)
- Omnipod "Eros" pods

To control an insulin you need to have a [RileyLink](https://getrileylink.org), OrangeLink, Pickle, GNARL, Emalink, DiaLink or similar device

## Current state of FreeAPS X

FreeAPS X is in an active development state and changes frequently.

You can find a description of versions on the [releases page](https://github.com/ivalkou/freeaps/releases).

### Stable versions

A stable version means that it has been tested for a long time and does not contain critical bugs. We consider it ready for everyday use.

Stable version numbers end in **.0**.

### Beta versions

Beta versions are the first to introduce new functionality. They are designed to test and identify issues and bugs.

**Beta versions are fairly stable, but may contain occasional bugs.**

Beta numbers end with a number greater than **0**.

## Contribution

Pull requests are accepted on the [dev branch](https://github.com/ivalkou/freeaps/tree/dev).

Bug reports and feature requests are accepted on the [Issues page](https://github.com/ivalkou/freeaps/issues).

## Implemented

- All base functions of oref0
- All base functions of oref1 (SMB, UAM and others)
- Autotune
- Autosens
- Nightscout BG data source as a CGM (Online)
- Applications that mimic Nightscout as a CGM (apps like Spike and Diabox) (Offline)
- [xDrip4iOS](https://github.com/JohanDegraeve/xdripswift) data source as a CGM via shared app gpoup (Offline)
- [GlucoseDirectApp](https://github.com/creepymonster/GlucoseDirectApp) data source as a CGM via shared app gpoup (Offline)
- Libre 1 transmitters and Libre 2 direct as a CGM
- Simple glucose simulator
- System state upload to Nightscout
- Remote carbs enter and temporary targets through Nightscout
- Remote bolusing and insulin pump control
- Dexcom offline support (beta)
- Detailed oref preferences description inside the app (beta)
- User notifications of the system and connected devices state (beta)
- Apple Watch app (beta)
- Enlite support (beta)
- Apple Health support for blood glucose (beta)

## Not implemented (plans for future)

- Open loop mode
- Profile upload to Nightscout
- Home screen widget
- Apple Health support for carbs and insulin

## Community

- [English Telegram group](https://t.me/freeapsx_eng)
- [Russian Telegram group](https://t.me/freeapsx)

