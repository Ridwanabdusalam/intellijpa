//
//  Item.swift
//  intellijpa
//
//  Created by Ridwan Abdusalam on 20/05/2025.
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
