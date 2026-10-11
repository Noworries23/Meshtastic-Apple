//
//  LoggingSessionEntity.swift
//  Meshtastic
//

import Foundation
import SwiftData

@Model
final class LoggingSessionEntity {
	@Attribute(.unique) var id: UUID
	var name: String
	var activity: String
	var startedAt: Date
	var endedAt: Date?
	var presetRawValue: String
	var configurationData: Data?

	init(
		id: UUID = UUID(),
		name: String,
		activity: String,
		startedAt: Date,
		endedAt: Date? = nil,
		presetRawValue: String,
		configurationData: Data? = nil
	) {
		self.id = id
		self.name = name
		self.activity = activity
		self.startedAt = startedAt
		self.endedAt = endedAt
		self.presetRawValue = presetRawValue
		self.configurationData = configurationData
	}
}
