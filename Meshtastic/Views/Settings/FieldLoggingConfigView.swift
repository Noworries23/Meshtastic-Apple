//
//  FieldLoggingConfigView.swift
//  Meshtastic
//

import SwiftUI

struct FieldLoggingConfigView: View {
	@State private var selectedPreset: LoggingPreset
	@State private var draftConfiguration: FieldLoggingConfiguration
	@State private var isAdvancedControlsExpanded = false

	init(preset: LoggingPreset = .balanced) {
		_selectedPreset = State(initialValue: preset)
		_draftConfiguration = State(initialValue: .preset(preset))
	}

	var body: some View {
		Form {
			Section {
				Picker("Preset", selection: $selectedPreset) {
					ForEach(LoggingPreset.allCases) { preset in
						Text(preset.title).tag(preset)
					}
				}
				.onChange(of: selectedPreset) { _, preset in
					draftConfiguration = .preset(preset)
				}
			} header: {
				Text("Logging Mode")
			} footer: {
				Text("Choose a starting point. Advanced Controls can be adjusted before the session starts.")
			}

			Section {
				DisclosureGroup("Advanced Controls", isExpanded: $isAdvancedControlsExpanded) {
					gpsControls
					radioControls
					sessionLimits
				}
			}

			if showsBatteryWarning {
				Section {
					Label {
						Text("Frequent or high-accuracy GPS updates can reduce battery life.")
					} icon: {
						Image(systemName: "battery.75percent")
					}
					.foregroundStyle(.orange)
				}
			}

			if draftConfiguration.logRawPayloads {
				Section {
					Label {
						Text("Raw packet payloads may contain private message data and can use significant storage.")
					} icon: {
						Image(systemName: "exclamationmark.shield.fill")
					}
					.foregroundStyle(.red)
				}
			}
		}
		.formStyle(.grouped)
		.navigationTitle("Field Logging")
	}

	private var gpsControls: some View {
		Group {
			Picker("Desired Accuracy", selection: $draftConfiguration.desiredAccuracy) {
				ForEach(accuracyOptions, id: \.value) { option in
					Text(option.label).tag(option.value)
				}
			}

			Stepper(
				"Distance Filter: \(draftConfiguration.distanceFilter, format: .number.precision(.fractionLength(0...1))) m",
				value: $draftConfiguration.distanceFilter,
				in: 1...1000,
				step: 1
			)

			Stepper(
				"Update Interval: \(draftConfiguration.timeIntervalFilter ?? 0, format: .number.precision(.fractionLength(0...1))) s",
				value: timeIntervalBinding,
				in: 1...300,
				step: 1
			)
		}
	}

	private var radioControls: some View {
		Group {
			Toggle("Metadata Capture", isOn: $draftConfiguration.logRadioMetadata)
			Toggle("Raw Payload Capture", isOn: $draftConfiguration.logRawPayloads)
		}
	}

	private var sessionLimits: some View {
		Group {
			Toggle("Limit Storage", isOn: storageLimitEnabled)
			if draftConfiguration.maxStorageMB != nil {
				Stepper(
					"Max Storage: \(draftConfiguration.maxStorageMB ?? 0) MB",
					value: storageLimitBinding,
					in: 1...102400,
					step: 1
				)
			}

			Toggle("Limit Duration", isOn: durationLimitEnabled)
			if draftConfiguration.maxDuration != nil {
				Stepper(
					"Max Duration: \(durationHours, format: .number.precision(.fractionLength(0...1))) hours",
					value: durationHoursBinding,
					in: 1...168,
					step: 1
				)
			}
		}
	}

	private var showsBatteryWarning: Bool {
		(draftConfiguration.timeIntervalFilter ?? .infinity) < 5 || draftConfiguration.desiredAccuracy <= 10
	}

	private var accuracyOptions: [(label: String, value: Double)] {
		[
			(String(localized: "100 meters"), 100),
			(String(localized: "10 meters"), 10),
			(String(localized: "5 meters"), 5),
			(String(localized: "1 meter"), 1)
		]
	}

	private var timeIntervalBinding: Binding<TimeInterval> {
		Binding(
			get: { draftConfiguration.timeIntervalFilter ?? 10 },
			set: { draftConfiguration.timeIntervalFilter = $0 }
		)
	}

	private var storageLimitEnabled: Binding<Bool> {
		Binding(
			get: { draftConfiguration.maxStorageMB != nil },
			set: { draftConfiguration.maxStorageMB = $0 ? (draftConfiguration.maxStorageMB ?? 1024) : nil }
		)
	}

	private var storageLimitBinding: Binding<Int> {
		Binding(
			get: { draftConfiguration.maxStorageMB ?? 1024 },
			set: { draftConfiguration.maxStorageMB = $0 }
		)
	}

	private var durationLimitEnabled: Binding<Bool> {
		Binding(
			get: { draftConfiguration.maxDuration != nil },
			set: { draftConfiguration.maxDuration = $0 ? (draftConfiguration.maxDuration ?? 24 * 60 * 60) : nil }
		)
	}

	private var durationHours: Double {
		(draftConfiguration.maxDuration ?? 24 * 60 * 60) / (60 * 60)
	}

	private var durationHoursBinding: Binding<Double> {
		Binding(
			get: { durationHours },
			set: { draftConfiguration.maxDuration = $0 * 60 * 60 }
		)
	}
}
