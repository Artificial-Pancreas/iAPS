//
//  NavigationLink.swift
//  DanaKit
//
//  Created by Bastiaan Verhaar on 01/01/2024.
//  Copyright © 2024 Randall Knutson. All rights reserved.
//

import SwiftUI

extension NavigationLink where Label == EmptyView, Destination == EmptyView {

   /// Useful in cases where a `NavigationLink` is needed but there should not be
   /// a destination. e.g. for programmatic navigation.
   static var empty: NavigationLink {
       self.init(destination: EmptyView(), label: { EmptyView() })
   }
}
