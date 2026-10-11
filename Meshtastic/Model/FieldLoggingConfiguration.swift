//
//  FieldLoggingConfiguration.swift
//  Meshtastic
//

import Foundation

enum LoggingPreset: String, CaseIterable, Codable, Identifiable, Sendable {
	case minimal
	case balanced
	case rfSurvey
	case fullCapture
	case custom

	var id: String { rawValue }

	var title: String {
		switch self {
		case .minimal:
			return String(localized: "Minimal")
		case .balanced:
			return String(localized: "Balanced")
		case .rfSurvey:
			return String(localized: "RF Survey")
		case .fullCapture:
			return String(localized: "Full Capture")
		case .custom:
			return String(localized: "Custom")
		}
	}
}

struct FieldLoggingConfiguration: Codable, Equatable, Sendable {
	var desiredAccuracy: Double
	var distanceFilter: Double
	var timeIntervalFilter: TimeInterval?
	var logRadioMetadata: Bool
	var logRawPayloads: Bool
	var enabledPortFilter: [Int]?
	var maxDuration: TimeInterval?
	var maxStorageMB: Int?

	static func preset(_ preset: LoggingPreset) -> FieldLoggingConfiguration {
		switch preset {
		case .minimal:
			return FieldLoggingConfiguration(
				desiredAccuracy: 100,
				distanceFilter: 10,
				timeIntervalFilter: 60,
				logRadioMetadata: false,
				logRawPayloads: false,
				enabledPortFilter: nil,
				maxDuration: nil,
				maxStorageMB: nil
			)
		case .balanced, .custom:
			return FieldLoggingConfiguration(
				desiredAccuracy: 10,
				distanceFilter: 10,
				timeIntervalFilter: 10,
				logRadioMetadata: true,
				logRawPayloads: false,
				enabledPortFilter: nil,
				maxDuration: nil,
				maxStorageMB: nil
			)
		case .rfSurvey:
			return FieldLoggingConfiguration(
				desiredAccuracy: 5,
				distanceFilter: 5,
				timeIntervalFilter: 1,
				logRadioMetadata: true,
				logRawPayloads: false,
				enabledPortFilter: nil,
				maxDuration: nil,
				maxStorageMB: nil
			)
		case .fullCapture:
			return FieldLoggingConfiguration(
				desiredAccuracy: 1,
				distanceFilter: 1,
				timeIntervalFilter: 1,
				logRadioMetadata: true,
				logRawPayloads: true,
				enabledPortFilter: nil,
				maxDuration: nil,
				maxStorageMB: nil
			)
		}
	}
}
