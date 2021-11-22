//
//  CalibrationEditView.swift
//  LibreTransmitterUI
//
//  Created by Bjørn Inge Berg on 24/03/2021.
//  Copyright © 2021 Mark Wilson. All rights reserved.
//

import SwiftUI
import Combine

struct CalibrationEditView: View {
    typealias Params = SensorData.CalibrationInfo



    @State private var isPressed = false

    @State private var presentableStatus: StatusMessage?

    public var isReadOnly : Bool {
        if debugMode {
            return false
        }

        return !hasExistingParams
    }


    @ObservedObject fileprivate var formstate = FormErrorState.shared




    var saveButtonSection: some View{
        Section {
            Button(action: {
                print("calibrationsaving in progress")


                self.isPressed.toggle()

                if formstate.hasAnyError {
                    presentableStatus = StatusMessage(title: "Could not save", message:"Some of the fields was not correctly entered")
                    return
                }

                if false && isReadOnly {
                    presentableStatus = StatusMessage(title: "Could not save", message:"Calibration parameters are readonly and cannot be saved")
                    return
                }

                do {
                    try KeychainManagerWrapper.standard.setLibreNativeCalibrationData(newParams)
                    print("calibrationsaving completed")

                    presentableStatus = StatusMessage(title: "OK", message: "Calibrations saved!")
                } catch {
                    print("error: \(error.localizedDescription)")
                    presentableStatus = StatusMessage(title: "Calibration error", message:"Calibrations could not be saved, Check that footer crc is non-zero and that all values have sane defaults")
                }


            }, label: {
                Text("Save")

            }).buttonStyle(BlueButtonStyle())
            .alert(item: $presentableStatus) { status in
                Alert(title: Text(status.title), message: Text(status.message) , dismissButton: .default(Text("Got it!")))
            }

        }
    }

    var calibrationInputsSection : some View{
        Section {
            NumericTextField(description: "i1", showDescription: true, numericValue: $newParams.i1, isReadOnly: isReadOnly)
            NumericTextField(description: "i2", showDescription: true, numericValue: $newParams.i2, isReadOnly: isReadOnly)
            NumericTextField(description: "i3", showDescription: true, numericValue: $newParams.i3, isReadOnly: isReadOnly)
            NumericTextField(description: "i4", showDescription: true, numericValue: $newParams.i4, isReadOnly: isReadOnly)
            NumericTextField(description: "i5", showDescription: true, numericValue: $newParams.i5, isReadOnly: isReadOnly)
            NumericTextField(description: "i6", showDescription: true, numericValue: $newParams.i6, isReadOnly: isReadOnly)
        }
    }

    var validForSection : some View {
        Section {
            Text("Valid for footer: \(newParams.isValidForFooterWithReverseCRCs)")

        }
    }

    var body: some View {
        List {
            calibrationInputsSection
            validForSection
            saveButtonSection
        }
        .listStyle(InsetGroupedListStyle())
        .navigationBarTitle("Calibration Edit")
    }

    @ObservedObject private var newParams: Params

    private var debugMode = false
    private var hasExistingParams = false

    public init(debugMode:Bool=false) {
        self.debugMode = debugMode


        if let params = KeychainManagerWrapper.standard.getLibreNativeCalibrationData() {
            hasExistingParams = true
            self.newParams = params
        } else {
            hasExistingParams = false
            self.newParams = Params(i1: 1,i2: 2,i3: 3,i4: 4,i5: 5,i6: 5,isValidForFooterWithReverseCRCs: 1337)
        }

    }

    



}

struct CalibrationEditView_Previews: PreviewProvider {
    static var previews: some View {
        //var testData = FormState.shared
        //testData.childStates["i1"] = true
        CalibrationEditView(debugMode: true)

    }
}
