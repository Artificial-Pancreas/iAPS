# FreeAPS X

FreeAPS X - an artificial pancreas system for iOS based on [OpenAPS Reference](https://github.com/openaps/oref0) algorithms

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)

FreeAPS X uses original JavaScript files of oref0 and provides a user interface (UI) to control and set up the system

## Smartphone requirements

- All iPhones which support iOS 14 and up.

## Supported pumps

To control an insulin pump FreeAPS X uses modified [rileylink_ios](https://github.com/ps2/rileylink_ios) library, thus supporting the same pump list:

- Medtronic 515 or 715 (any firmware)
- Medtronic 522 or 722 (any firmware)
- Medtronic 523 or 723 (firmware 2.4 or lower)
- Medtronic Worldwide Veo 554 or 754 (firmware 2.6A or lower)
- Medtronic Canadian/Australian Veo 554 or 754 (firmware 2.7A or lower)
- Omnipod "Eros" pods

To control an insulin you need to have a [RileyLink](https://getrileylink.org), oRange, Pickle, GNARL, Emalink or similar device

## Current state of FreeAPS X

FreeAPS X is in an active development state

**We do not recommend to use the system for everyday control of blood glucose**

If you want to test it, there is a beta-version available

## Implemented

- All base functions of oref0
- All base functions of oref1 (SMB, UAM and others)
- Autotune
- Autosens
- Nightscout BG data source as a CGM (Online)
- Applications that mimic Nightscout as a CGM (apps like Spike and Diabox) (Offline)
- xDrip4iOS data source as a CGM via shared app gpoup (Offline)
- System state upload to Nightscout
- Remote carbs enter and temporary targets through Nightscout
- Remote bolusing and insulin pump control

## Not implemented (plans for future)

- Open loop mode
- Phone notifications of the system and connected devices state
- Profile upload to Nightscout
- Desktop widget
- Apple Watch app
- Plugins
- Dexcom support
- Enlite support
- Apple Health support
- Detailed functions description inside the app

## Documentation

*In progress*

## Community

- [English Telegram group](https://t.me/freeapsx_eng)
- [Russian Telegram group](https://t.me/freeapsx)

