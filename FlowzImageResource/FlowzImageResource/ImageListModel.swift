//
//  ImageListModel.swift
//  FlowzImageResource
//
//  Created by 千千 on 4/8/24.
//

import Foundation


struct ImageItem: Codable, Identifiable {
    var id = UUID()
    var path: String
    var inUse: Bool
    var compressed: Bool
    var isAllowUnused: Bool
}
