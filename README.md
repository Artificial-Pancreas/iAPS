# FreeAPS X

## Introduction 

FreeAPS X - an artificial pancreas system for iOS based on [OpenAPS Reference](https://github.com/openaps/oref0) algorithms

FreeAPS X uses original JavaScript files of oref0 and provides a user interface (UI) to control and set up the system. 

This repo includes two branchs allowing to use OmniPod Dash pumps : 
- the branch dash_dev includes the dash pump in the setting pump 
- the branch dash_garmin_disf_dev includes the dash pump, but also the dISF implementation (with update of openAPS) and the garmin service to connect with garmin watches. 

To use this branch : 

git clone -b dash_dev remote-repo-url or git clone -b dash_garmin_disf_dev remote-repo-url 

or use directly Xcode to use one specific branch. 

Don't forget to copy / reference your ConfigOverride 

:warning: :warning: :warning: :warning:

# Precaution 

Please understand that these version are :
- highly experimental
- not approved for therapy

WARNING 
- The settings of your current FAX should not be re-init when you update to this version but check it before close loop 
- The update MUST ONLY be done when you change of a pod. The previous pod would be not accessible. So, first, desactivate your current pod then compile and update your FAX on your phone and add a new pod with the dash pump menu.


These version were tested by few developers with success. But...Don't hesitate to create issues if you find bugs or issues. 

:warning: :warning: :warning: 


# Documentation

[freeAPS X original github](https://github.com/ivalkou/freeaps)

[ADD DASH PUMP and SETTINGS](https://loopkit.github.io/loopdocs/loop-3/omnipod/)

[Overview & Onboarding Tips on Loop&Learn](https://www.loopandlearn.org/freeaps-x/)

[OpenAPS documentation](https://openaps.readthedocs.io/en/latest/)


# Technical updates 

## Updated to include dashpod

- replace the Rileylink package to the Loop version of 2 august 2022
- replace the Loopkit package to the Loop version of 2 august 2022
- add the MKRingProgressView from the Loop version of 2 august 2022
- add the OMNIBLE package from the Loop version of 2 august 2022
_ modify the order of compilation for CGMBLEKit (header before compilation)
 
 ## Changes in package 
 
No change 😁. Use extension in FAX to include the managerIdentifier

 
 ## Changes in freeapsx

 - in info, add the Bundle Display Name used by package 
 - add Bluetooth service state in Services/Bluetooth required by the new version of the package + add this service as a swift injection in APS resolver
 - in Aps manager :
    - Added blueTooth manager
    - modify enactTempBasal to respect the new protocol
    - modify enactBolus to respect the new protocol. The new loopkit requires a new parameter to describe the type of bolus - in FAX defaut to .manualRecommendationAccepted
    - modify the clearBolusReporter to improve the refresh of the state of the pump
 
 - in devicemanager : 
    - Added blueTooth manager
    - change the staticPumpManagerByIdentifier 
    - change the call ensureCurrentPumpData to respect the new version
    - change the result of fetchNewDataIfNeeded 
    - change the PumpManagerDelegate extension 
    - change the alert protocol
    - add OmniBLE config

 - in extension PumpManager
    - change managerIdentifier
    - remove setupViewController extension
    - new settingsViewController 

- in PumpHistoryStorage  
    - remove a ismutable method
 
- Color and UIColor added and LoopUICOloPalette+Default


In the different views : 
- In home view, add Bluetooth 
- in pump config model, change the PumpConfig.StateModel extension 
- add the bluetooth and correct new interfaces in settings pump views
- change the view for settings max basal /bolus in pump 
- Improve the log message in MainStateModel + UserNotificationManager + Router 

In deviceDataManager :
- add the management of the issue alert (lot of changes with the previous version in the alert management by LoopKit) - Send the alert to UNNotification (modify also)


## issues 
- unable to display all the screens when setup a new pump 
- ~~choice of the insulin for the pump.~~ 
- unable to use truetime for NTP sync. Not yet used by Loop 

