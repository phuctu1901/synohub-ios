//
//  Item.swift
//  SynoHubs
//
//  Created by Nguyen Tu on 19/5/26.
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
