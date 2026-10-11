//
//  FieldLoggingConfiguration.swift
//  Meshtastic
//

import Foundation

enum FieldLoggingPreset: String, CaseIterable, Codable, Identifiable, Sendable {
	case minimal
	case balanced
	case rfSurvey
	case fullCapture

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
		}
	}

	var configuration: FieldLoggingConfiguration {
		switch self {
		case .minimal:
			return FieldLoggingConfiguration(
				preset: self,
				saveGPS: true,
				saveLocationAccuracy: false,
				saveRadioObservations: false,
				saveSignalData: false,
				saveRoutingMetadata: false,
				saveTelemetry: false,
				saveRawPayloads: false,
				gpsAccuracy: .hundredMeters,
				gpsDistanceFilter: 10
			)
		case .balanced:
			return FieldLoggingConfiguration(
				preset: self,
				saveGPS: true,
				saveLocationAccuracy: true,
				saveRadioObservations: true,
				saveSignalData: true,
				saveRoutingMetadata: false,
				saveTelemetry: true,
				saveRawPayloads: false,
				gpsAccuracy: .best,
				gpsDistanceFilter: 10
			)
		case .rfSurvey:
			return FieldLoggingConfiguration(
				preset: self,
				saveGPS: true,
				saveLocationAccuracy: true,
				saveRadioObservations: true,
				saveSignalData: true,
				saveRoutingMetadata: true,
				saveTelemetry: true,
				saveRawPayloads: false,
				gpsAccuracy: .best,
				gpsDistanceFilter: 5
			)
		case .fullCapture:
			return FieldLoggingConfiguration(
				preset: self,
				saveGPS: true,
				saveLocationAccuracy: true,
				saveRadioObservations: true,
				saveSignalData: true,
				saveRoutingMetadata: true,
				saveTelemetry: true,
				saveRawPayloads: true,
				gpsAccuracy: .best,
				gpsDistanceFilter: 0
			)
		}
	}
}

struct FieldLoggingConfiguration: Codable, Equatable, Sendable {
	enum GPSAccuracy: String, Codable, Sendable {
		case hundredMeters
		case best
	}

	var preset: FieldLoggingPreset
	var saveGPS: Bool
	var saveLocationAccuracy: Bool
	var saveRadioObservations: Bool
	var saveSignalData: Bool
	var saveRoutingMetadata: Bool
	var saveTelemetry: Bool
	var saveRawPayloads: Bool
	var gpsAccuracy: GPSAccuracy
	var gpsDistanceFilter: Double

	static let balanced = FieldLoggingPreset.balanced.configuration
}
