//
//  GPSObservationEntity.swift
//  Meshtastic
//

import Foundation
import SwiftData

@Model
final class GPSObservationEntity {
	@Attribute(.unique) var id: UUID
	var sessionId: UUID
	var recordedAt: Date
	var latitude: Double
	var longitude: Double
	var altitude: Double
	var horizontalAccuracy: Double
	var verticalAccuracy: Double
	var speed: Double
	var course: Double

	init(
		id: UUID = UUID(),
		sessionId: UUID,
		recordedAt: Date,
		latitude: Double,
		longitude: Double,
		altitude: Double,
		horizontalAccuracy: Double,
		verticalAccuracy: Double,
		speed: Double,
		course: Double
	) {
		self.id = id
		self.sessionId = sessionId
		self.recordedAt = recordedAt
		self.latitude = latitude
		self.longitude = longitude
		self.altitude = altitude
		self.horizontalAccuracy = horizontalAccuracy
		self.verticalAccuracy = verticalAccuracy
		self.speed = speed
		self.course = course
	}
}
