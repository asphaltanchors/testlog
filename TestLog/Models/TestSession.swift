//
//  TestSession.swift
//  TestLog
//
//  Created by Oren Teich on 2/19/26.
//

import Foundation
import SwiftData

@Model
final class TestSession {
    var sessionDate: Date
    var notes: String?
    var weatherConditions: String?

    @Relationship(deleteRule: .cascade, inverse: \PullTest.session)
    var tests: [PullTest] = []

    init(sessionDate: Date, notes: String? = nil, weatherConditions: String? = nil) {
        self.sessionDate = sessionDate
        self.notes = notes
        self.weatherConditions = weatherConditions
    }
}
