//
//  RadioObservationEntity.swift
//  Meshtastic
//

import Foundation
import SwiftData

@Model
final class RadioObservationEntity {
	@Attribute(.unique) var id: UUID
	var sessionId: UUID
	var receivedAt: Date
	var fromNode: UInt32
	var toNode: UInt32
	var packetId: UInt32
	var portNum: Int
	var channel: Int
	var hopStart: Int?
	var hopLimit: Int?
	var rssi: Int?
	var snr: Float?
	var viaMqtt: Bool
	var rawPayload: Data?

	init(
		id: UUID = UUID(),
		sessionId: UUID,
		receivedAt: Date,
		fromNode: UInt32,
		toNode: UInt32,
		packetId: UInt32,
		portNum: Int,
		channel: Int,
		hopStart: Int? = nil,
		hopLimit: Int? = nil,
		rssi: Int? = nil,
		snr: Float? = nil,
		viaMqtt: Bool,
		rawPayload: Data? = nil
	) {
		self.id = id
		self.sessionId = sessionId
		self.receivedAt = receivedAt
		self.fromNode = fromNode
		self.toNode = toNode
		self.packetId = packetId
		self.portNum = portNum
		self.channel = channel
		self.hopStart = hopStart
		self.hopLimit = hopLimit
		self.rssi = rssi
		self.snr = snr
		self.viaMqtt = viaMqtt
		self.rawPayload = rawPayload
	}
}
