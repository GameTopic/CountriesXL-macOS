//
//  Item.swift
//  CountriesXL
//
//  Created by Tyler Austin on 9/29/25.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date
    
    init(timestamp: Date) {
        self.timestamp = timestamp
    }
}
