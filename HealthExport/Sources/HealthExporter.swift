import HealthKit

struct ExportRow {
    let date: String
    let metric: String
    let stat: String
    let value: Double
    let unit: String
}

/// Reads Apple Health and turns it into daily rows: date,metric,stat,value,unit
enum HealthExporter {
    static let store = HKHealthStore()

    private struct Spec {
        let id: HKQuantityTypeIdentifier
        let name: String
        let unit: HKUnit
        let cumulative: Bool   // true = daily sum, false = daily avg/min/max

        /// Also export every individual reading (with timestamp + source app) in the samples file.
        var detail: Bool {
            name.hasPrefix("dietary_") || HealthExporter.detailMetrics.contains(name)
        }
    }

    private static let detailMetrics: Set<String> = [
        "body_mass", "body_fat", "lean_body_mass", "bmi", "waist_circumference",
        "blood_pressure_systolic", "blood_pressure_diastolic", "blood_glucose",
        "body_temperature", "blood_oxygen", "blood_alcohol", "insulin_delivery",
    ]

    private static let bpm = HKUnit.count().unitDivided(by: .minute())
    private static let vo2 = HKUnit.literUnit(with: .milli).unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    private static let specs: [Spec] = [
        // Activity (daily totals)
        Spec(id: .stepCount, name: "steps", unit: .count(), cumulative: true),
        Spec(id: .distanceWalkingRunning, name: "distance_walking_running", unit: .meter(), cumulative: true),
        Spec(id: .distanceCycling, name: "distance_cycling", unit: .meter(), cumulative: true),
        Spec(id: .flightsClimbed, name: "flights_climbed", unit: .count(), cumulative: true),
        Spec(id: .activeEnergyBurned, name: "active_energy", unit: .kilocalorie(), cumulative: true),
        Spec(id: .basalEnergyBurned, name: "basal_energy", unit: .kilocalorie(), cumulative: true),
        Spec(id: .appleExerciseTime, name: "exercise_minutes", unit: .minute(), cumulative: true),
        Spec(id: .appleStandTime, name: "stand_minutes", unit: .minute(), cumulative: true),
        Spec(id: .timeInDaylight, name: "time_in_daylight", unit: .minute(), cumulative: true),
        // Heart & vitals (daily avg/min/max)
        Spec(id: .heartRate, name: "heart_rate", unit: bpm, cumulative: false),
        Spec(id: .restingHeartRate, name: "resting_heart_rate", unit: bpm, cumulative: false),
        Spec(id: .walkingHeartRateAverage, name: "walking_heart_rate_avg", unit: bpm, cumulative: false),
        Spec(id: .heartRateVariabilitySDNN, name: "hrv_sdnn", unit: .secondUnit(with: .milli), cumulative: false),
        Spec(id: .oxygenSaturation, name: "blood_oxygen", unit: .percent(), cumulative: false),
        Spec(id: .respiratoryRate, name: "respiratory_rate", unit: bpm, cumulative: false),
        Spec(id: .vo2Max, name: "vo2_max", unit: vo2, cumulative: false),
        Spec(id: .bloodPressureSystolic, name: "blood_pressure_systolic", unit: .millimeterOfMercury(), cumulative: false),
        Spec(id: .bloodPressureDiastolic, name: "blood_pressure_diastolic", unit: .millimeterOfMercury(), cumulative: false),
        Spec(id: .bloodGlucose, name: "blood_glucose", unit: HKUnit(from: "mg/dL"), cumulative: false),
        Spec(id: .bodyTemperature, name: "body_temperature", unit: .degreeCelsius(), cumulative: false),
        // Body
        Spec(id: .bodyMass, name: "body_mass", unit: .gramUnit(with: .kilo), cumulative: false),
        Spec(id: .bodyFatPercentage, name: "body_fat", unit: .percent(), cumulative: false),
        Spec(id: .leanBodyMass, name: "lean_body_mass", unit: .gramUnit(with: .kilo), cumulative: false),
        Spec(id: .bodyMassIndex, name: "bmi", unit: .count(), cumulative: false),
        Spec(id: .height, name: "height", unit: .meter(), cumulative: false),
        // Mobility
        Spec(id: .walkingSpeed, name: "walking_speed", unit: HKUnit.meter().unitDivided(by: .second()), cumulative: false),
        Spec(id: .walkingStepLength, name: "walking_step_length", unit: .meter(), cumulative: false),
        Spec(id: .walkingAsymmetryPercentage, name: "walking_asymmetry", unit: .percent(), cumulative: false),
        Spec(id: .appleWalkingSteadiness, name: "walking_steadiness", unit: .percent(), cumulative: false),
        Spec(id: .waistCircumference, name: "waist_circumference", unit: .meter(), cumulative: false),
        Spec(id: .heartRateRecoveryOneMinute, name: "heart_rate_recovery_1min", unit: bpm, cumulative: false),
        Spec(id: .atrialFibrillationBurden, name: "afib_burden", unit: .percent(), cumulative: false),
        Spec(id: .appleSleepingWristTemperature, name: "sleeping_wrist_temperature", unit: .degreeCelsius(), cumulative: false),
        Spec(id: .basalBodyTemperature, name: "basal_body_temperature", unit: .degreeCelsius(), cumulative: false),
        Spec(id: .peripheralPerfusionIndex, name: "perfusion_index", unit: .percent(), cumulative: false),
        Spec(id: .forcedVitalCapacity, name: "forced_vital_capacity", unit: .liter(), cumulative: false),
        Spec(id: .forcedExpiratoryVolume1, name: "fev1", unit: .liter(), cumulative: false),
        Spec(id: .bloodAlcoholContent, name: "blood_alcohol", unit: .percent(), cumulative: false),
        Spec(id: .insulinDelivery, name: "insulin_delivery", unit: .internationalUnit(), cumulative: true),
        Spec(id: .numberOfTimesFallen, name: "falls", unit: .count(), cumulative: true),
        Spec(id: .numberOfAlcoholicBeverages, name: "alcoholic_beverages", unit: .count(), cumulative: true),
        Spec(id: .uvExposure, name: "uv_exposure", unit: .count(), cumulative: false),
        Spec(id: .appleMoveTime, name: "move_minutes", unit: .minute(), cumulative: true),
        Spec(id: .pushCount, name: "wheelchair_pushes", unit: .count(), cumulative: true),
        Spec(id: .distanceSwimming, name: "distance_swimming", unit: .meter(), cumulative: true),
        Spec(id: .swimmingStrokeCount, name: "swimming_strokes", unit: .count(), cumulative: true),
        // Mobility (extra)
        Spec(id: .walkingDoubleSupportPercentage, name: "walking_double_support", unit: .percent(), cumulative: false),
        Spec(id: .stairAscentSpeed, name: "stair_ascent_speed", unit: HKUnit.meter().unitDivided(by: .second()), cumulative: false),
        Spec(id: .stairDescentSpeed, name: "stair_descent_speed", unit: HKUnit.meter().unitDivided(by: .second()), cumulative: false),
        Spec(id: .sixMinuteWalkTestDistance, name: "six_minute_walk_distance", unit: .meter(), cumulative: false),
        // Running & cycling
        Spec(id: .runningSpeed, name: "running_speed", unit: HKUnit.meter().unitDivided(by: .second()), cumulative: false),
        Spec(id: .runningPower, name: "running_power", unit: .watt(), cumulative: false),
        Spec(id: .runningStrideLength, name: "running_stride_length", unit: .meter(), cumulative: false),
        Spec(id: .runningVerticalOscillation, name: "running_vertical_oscillation", unit: .meterUnit(with: .centi), cumulative: false),
        Spec(id: .runningGroundContactTime, name: "running_ground_contact_time", unit: .secondUnit(with: .milli), cumulative: false),
        Spec(id: .cyclingSpeed, name: "cycling_speed", unit: HKUnit.meter().unitDivided(by: .second()), cumulative: false),
        Spec(id: .cyclingPower, name: "cycling_power", unit: .watt(), cumulative: false),
        Spec(id: .cyclingCadence, name: "cycling_cadence", unit: bpm, cumulative: false),
        // Nutrition (daily totals; Lose It! writes these)
        Spec(id: .dietaryEnergyConsumed, name: "dietary_energy", unit: .kilocalorie(), cumulative: true),
        Spec(id: .dietaryProtein, name: "dietary_protein", unit: .gram(), cumulative: true),
        Spec(id: .dietaryCarbohydrates, name: "dietary_carbs", unit: .gram(), cumulative: true),
        Spec(id: .dietaryFatTotal, name: "dietary_fat", unit: .gram(), cumulative: true),
        Spec(id: .dietaryWater, name: "dietary_water", unit: .liter(), cumulative: true),
        Spec(id: .dietaryCaffeine, name: "dietary_caffeine", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryFiber, name: "dietary_fiber", unit: .gram(), cumulative: true),
        Spec(id: .dietarySugar, name: "dietary_sugar", unit: .gram(), cumulative: true),
        Spec(id: .dietarySodium, name: "dietary_sodium", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryFatSaturated, name: "dietary_fat_saturated", unit: .gram(), cumulative: true),
        Spec(id: .dietaryFatMonounsaturated, name: "dietary_fat_monounsaturated", unit: .gram(), cumulative: true),
        Spec(id: .dietaryFatPolyunsaturated, name: "dietary_fat_polyunsaturated", unit: .gram(), cumulative: true),
        Spec(id: .dietaryCholesterol, name: "dietary_cholesterol", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryPotassium, name: "dietary_potassium", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryCalcium, name: "dietary_calcium", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryIron, name: "dietary_iron", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryMagnesium, name: "dietary_magnesium", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryZinc, name: "dietary_zinc", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryPhosphorus, name: "dietary_phosphorus", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryCopper, name: "dietary_copper", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryManganese, name: "dietary_manganese", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryChloride, name: "dietary_chloride", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietarySelenium, name: "dietary_selenium", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryChromium, name: "dietary_chromium", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryMolybdenum, name: "dietary_molybdenum", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryIodine, name: "dietary_iodine", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryVitaminA, name: "dietary_vitamin_a", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryVitaminC, name: "dietary_vitamin_c", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryVitaminD, name: "dietary_vitamin_d", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryVitaminE, name: "dietary_vitamin_e", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryVitaminK, name: "dietary_vitamin_k", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryVitaminB6, name: "dietary_vitamin_b6", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryVitaminB12, name: "dietary_vitamin_b12", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryFolate, name: "dietary_folate", unit: .gramUnit(with: .micro), cumulative: true),
        Spec(id: .dietaryThiamin, name: "dietary_thiamin", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryRiboflavin, name: "dietary_riboflavin", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryNiacin, name: "dietary_niacin", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryPantothenicAcid, name: "dietary_pantothenic_acid", unit: .gramUnit(with: .milli), cumulative: true),
        Spec(id: .dietaryBiotin, name: "dietary_biotin", unit: .gramUnit(with: .micro), cumulative: true),
        // Environment
        Spec(id: .environmentalAudioExposure, name: "environmental_audio", unit: .decibelAWeightedSoundPressureLevel(), cumulative: false),
        Spec(id: .headphoneAudioExposure, name: "headphone_audio", unit: .decibelAWeightedSoundPressureLevel(), cumulative: false),
    ]

    private static var sleepType: HKCategoryType { HKCategoryType(.sleepAnalysis) }

    /// Health events worth flagging (each occurrence is exported as a row in the samples file).
    private static let eventTypes: [(id: HKCategoryTypeIdentifier, name: String)] = [
        (.highHeartRateEvent, "event_high_heart_rate"),
        (.lowHeartRateEvent, "event_low_heart_rate"),
        (.irregularHeartRhythmEvent, "event_irregular_rhythm"),
        (.lowCardioFitnessEvent, "event_low_cardio_fitness"),
        (.appleWalkingSteadinessEvent, "event_walking_steadiness"),
        (.environmentalAudioExposureEvent, "event_loud_environment"),
        (.headphoneAudioExposureEvent, "event_loud_headphones"),
        (.mindfulSession, "mindful_session"),
        (.abdominalCramps, "symptom_abdominal_cramps"),
        (.acne, "symptom_acne"),
        (.appetiteChanges, "symptom_appetite_changes"),
        (.bladderIncontinence, "symptom_bladder_incontinence"),
        (.bloating, "symptom_bloating"),
        (.breastPain, "symptom_breast_pain"),
        (.chestTightnessOrPain, "symptom_chest_tightness_or_pain"),
        (.chills, "symptom_chills"),
        (.constipation, "symptom_constipation"),
        (.coughing, "symptom_coughing"),
        (.diarrhea, "symptom_diarrhea"),
        (.dizziness, "symptom_dizziness"),
        (.drySkin, "symptom_dry_skin"),
        (.fainting, "symptom_fainting"),
        (.fatigue, "symptom_fatigue"),
        (.fever, "symptom_fever"),
        (.generalizedBodyAche, "symptom_generalized_body_ache"),
        (.hairLoss, "symptom_hair_loss"),
        (.headache, "symptom_headache"),
        (.heartburn, "symptom_heartburn"),
        (.hotFlashes, "symptom_hot_flashes"),
        (.lossOfSmell, "symptom_loss_of_smell"),
        (.lossOfTaste, "symptom_loss_of_taste"),
        (.lowerBackPain, "symptom_lower_back_pain"),
        (.memoryLapse, "symptom_memory_lapse"),
        (.moodChanges, "symptom_mood_changes"),
        (.nausea, "symptom_nausea"),
        (.nightSweats, "symptom_night_sweats"),
        (.pelvicPain, "symptom_pelvic_pain"),
        (.rapidPoundingOrFlutteringHeartbeat, "symptom_rapid_pounding_or_fluttering_heartbeat"),
        (.runnyNose, "symptom_runny_nose"),
        (.shortnessOfBreath, "symptom_shortness_of_breath"),
        (.sinusCongestion, "symptom_sinus_congestion"),
        (.skippedHeartbeat, "symptom_skipped_heartbeat"),
        (.sleepChanges, "symptom_sleep_changes"),
        (.soreThroat, "symptom_sore_throat"),
        (.vaginalDryness, "symptom_vaginal_dryness"),
        (.vomiting, "symptom_vomiting"),
        (.wheezing, "symptom_wheezing"),
        (.menstrualFlow, "cycle_menstrual_flow"),
        (.intermenstrualBleeding, "cycle_intermenstrual_bleeding"),
        (.ovulationTestResult, "cycle_ovulation_test"),
        (.cervicalMucusQuality, "cycle_cervical_mucus"),
        (.appleStandHour, "stand_hour"),
        (.toothbrushingEvent, "toothbrushing"),
        (.handwashingEvent, "handwashing"),
    ]

    private static var readTypes: Set<HKObjectType> {
        var types: Set<HKObjectType> = [sleepType, .workoutType()]
        for e in eventTypes { types.insert(HKCategoryType(e.id)) }
        types.insert(HKObjectType.electrocardiogramType())
        types.insert(HKObjectType.activitySummaryType())
        types.insert(HKCharacteristicType(.dateOfBirth))
        types.insert(HKCharacteristicType(.biologicalSex))
        types.insert(HKCharacteristicType(.bloodType))
        for spec in specs { types.insert(HKQuantityType(spec.id)) }
        return types
    }

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    static func requestAuthorization() async throws {
        try await store.requestAuthorization(toShare: [], read: readTypes)
    }

    /// Wakes the app in the background when new Health data lands (throttled by ExportCoordinator.minInterval).
    static func startBackgroundDelivery() {
        guard isAvailable else { return }
        let types: [HKSampleType] = [HKQuantityType(.stepCount), HKQuantityType(.heartRate), HKQuantityType(.activeEnergyBurned),
                                     HKQuantityType(.heartRateVariabilitySDNN), sleepType, .workoutType()]
        for type in types {
            store.enableBackgroundDelivery(for: type, frequency: .immediate) { _, _ in }
            let query = HKObserverQuery(sampleType: type, predicate: nil) { _, completion, _ in
                Task { @MainActor in
                    await ExportCoordinator.shared.run(force: false)
                    completion()
                }
            }
            store.execute(query)
        }
    }

    // MARK: - CSV

    private static func windowStart(_ daysBack: Int, now: Date = Date()) -> Date {
        let cal = Calendar.current
        return cal.startOfDay(for: cal.date(byAdding: .day, value: -(max(daysBack, 1) - 1), to: now) ?? now)
    }

    /// Daily rows. Pass `only` (metric names) for a fast partial read, e.g. for the in-app summary.
    static func dailyRows(daysBack: Int, only: Set<String>? = nil) async throws -> [ExportRow] {
        let now = Date()
        let start = windowStart(daysBack, now: now)
        var rows: [ExportRow] = []
        for spec in specs where only == nil || only!.contains(spec.name) {
            rows += try await dailyStatistics(spec, from: start, to: now)
        }
        rows += try await sleepRows(from: start, to: now)
        if only == nil {
            rows += try await workoutRows(from: start, to: now)
            rows += try await activitySummaryRows(from: start, to: now)
        }
        rows.sort { ($0.date, $0.metric, $0.stat) < ($1.date, $1.metric, $1.stat) }
        return rows
    }

    static func buildCSV(daysBack: Int) async throws -> (csv: String, rowCount: Int, range: String) {
        let now = Date()
        let start = windowStart(daysBack, now: now)
        let rows = try await dailyRows(daysBack: daysBack)

        var lines = ["date,metric,stat,value,unit"]
        for r in rows {
            lines.append("\(r.date),\(r.metric),\(r.stat),\(r.value),\(r.unit)")
        }
        let range = "\(dayString(start))..\(dayString(now))"
        return (lines.joined(separator: "\n") + "\n", rows.count, range)
    }

    /// Every individual reading/event (with source app, e.g. "Lose It!" or "RENPHO") for the same window.
    static func buildSamplesCSV(daysBack: Int) async throws -> (csv: String, rowCount: Int) {
        let cal = Calendar.current
        let now = Date()
        let start = cal.startOfDay(for: cal.date(byAdding: .day, value: -(max(daysBack, 1) - 1), to: now) ?? now)

        struct Line { let start: Date; let text: String }
        var out: [Line] = []
        let iso = ISO8601DateFormatter()
        iso.timeZone = Calendar.current.timeZone
        iso.formatOptions = [.withInternetDateTime]

        func add(_ s: HKSample, metric: String, value: Double, unit: String) {
            let text = [iso.string(from: s.startDate), iso.string(from: s.endDate), metric, "\(value)", unit,
                        csvEscape(s.sourceRevision.source.name)].joined(separator: ",")
            out.append(Line(start: s.startDate, text: text))
        }

        for spec in specs where spec.detail {
            let all: [HKSample]
            do { all = try await samples(of: HKQuantityType(spec.id), from: start, to: now) }
            catch { if shouldRethrow(error) { throw error }; continue }
            for case let q as HKQuantitySample in all {
                add(q, metric: spec.name, value: q.quantity.doubleValue(for: spec.unit), unit: spec.unit.unitString)
            }
        }
        for event in eventTypes {
            let all: [HKSample]
            do { all = try await samples(of: HKCategoryType(event.id), from: start, to: now) }
            catch { if shouldRethrow(error) { throw error }; continue }
            for case let c as HKCategorySample in all {
                if event.id == .mindfulSession {
                    add(c, metric: event.name, value: c.endDate.timeIntervalSince(c.startDate) / 60, unit: "min")
                } else {
                    add(c, metric: event.name, value: Double(c.value), unit: "category")
                }
            }
        }
        if let all = try? await samples(of: sleepType, from: start, to: now) {
            for case let c as HKCategorySample in all {
                let stage: String
                switch HKCategoryValueSleepAnalysis(rawValue: c.value) {
                case .asleepCore: stage = "sleep_core"
                case .asleepDeep: stage = "sleep_deep"
                case .asleepREM: stage = "sleep_rem"
                case .asleepUnspecified: stage = "sleep_asleep"
                case .awake: stage = "sleep_awake"
                case .inBed: stage = "sleep_in_bed"
                default: continue
                }
                add(c, metric: stage, value: c.endDate.timeIntervalSince(c.startDate) / 60, unit: "min")
            }
        }
        if let all = try? await samples(of: .workoutType(), from: start, to: now) {
            for case let w as HKWorkout in all {
                let name = "workout_\(workoutName(w.workoutActivityType))"
                add(w, metric: name, value: w.duration / 60, unit: "min")
                if let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                    add(w, metric: "\(name)_energy", value: kcal, unit: "kcal")
                }
                if let hr = w.statistics(for: HKQuantityType(.heartRate))?.averageQuantity()?.doubleValue(for: bpm) {
                    add(w, metric: "\(name)_avg_heart_rate", value: hr, unit: "count/min")
                }
                var meters = 0.0
                for id in [HKQuantityTypeIdentifier.distanceWalkingRunning, .distanceCycling, .distanceSwimming] {
                    meters += w.statistics(for: HKQuantityType(id))?.sumQuantity()?.doubleValue(for: .meter()) ?? 0
                }
                if meters > 0 { add(w, metric: "\(name)_distance", value: meters, unit: "m") }
            }
        }
        if let all = try? await samples(of: HKObjectType.electrocardiogramType(), from: start, to: now) {
            for case let ecg as HKElectrocardiogram in all {
                let kind: String
                switch ecg.classification {
                case .sinusRhythm: kind = "sinus_rhythm"
                case .atrialFibrillation: kind = "atrial_fibrillation"
                case .inconclusiveLowHeartRate: kind = "inconclusive_low_hr"
                case .inconclusiveHighHeartRate: kind = "inconclusive_high_hr"
                case .inconclusivePoorReading: kind = "inconclusive_poor_reading"
                default: kind = "other"
                }
                add(ecg, metric: "ecg_\(kind)", value: ecg.averageHeartRate?.doubleValue(for: bpm) ?? 0, unit: "count/min")
            }
        }

        out.sort { $0.start < $1.start }
        let csv = (["start,end,metric,value,unit,source"] + out.map(\.text)).joined(separator: "\n") + "\n"
        return (csv, out.count)
    }

    private static let hourlyMetrics: Set<String> = [
        "steps", "active_energy", "basal_energy", "distance_walking_running", "heart_rate", "hrv_sdnn",
        "respiratory_rate", "blood_oxygen", "environmental_audio", "headphone_audio",
    ]

    /// Hour-by-hour statistics (capped at 14 days) for the high-frequency metrics.
    static func buildHourlyCSV(daysBack: Int) async throws -> (csv: String, rowCount: Int) {
        let now = Date()
        let start = windowStart(min(max(daysBack, 1), 14), now: now)
        var rows: [ExportRow] = []
        for spec in specs where hourlyMetrics.contains(spec.name) {
            rows += try await dailyStatistics(spec, from: start, to: now, hourly: true)
        }
        rows.sort { ($0.date, $0.metric, $0.stat) < ($1.date, $1.metric, $1.stat) }
        var lines = ["hour,metric,stat,value,unit"]
        for r in rows { lines.append("\(r.date),\(r.metric),\(r.stat),\(r.value),\(r.unit)") }
        return (lines.joined(separator: "\n") + "\n", rows.count)
    }

    /// Static profile facts from Health (age, sex, blood type) as key,value rows.
    static func buildProfileCSV() -> (csv: String, rowCount: Int) {
        var rows: [(String, String)] = []
        let cal = Calendar.current
        if let comps = try? store.dateOfBirthComponents(), let dob = cal.date(from: comps) {
            rows.append(("date_of_birth", dayString(dob)))
            if let age = cal.dateComponents([.year], from: dob, to: Date()).year { rows.append(("age_years", "\(age)")) }
        }
        if let sex = try? store.biologicalSex().biologicalSex {
            switch sex {
            case .female: rows.append(("biological_sex", "female"))
            case .male: rows.append(("biological_sex", "male"))
            case .other: rows.append(("biological_sex", "other"))
            default: break
            }
        }
        if let blood = try? store.bloodType().bloodType {
            let name: String?
            switch blood {
            case .aPositive: name = "A+"
            case .aNegative: name = "A-"
            case .bPositive: name = "B+"
            case .bNegative: name = "B-"
            case .abPositive: name = "AB+"
            case .abNegative: name = "AB-"
            case .oPositive: name = "O+"
            case .oNegative: name = "O-"
            default: name = nil
            }
            if let name { rows.append(("blood_type", name)) }
        }
        rows.append(("timezone", TimeZone.current.identifier))
        let lines = ["key,value"] + rows.map { "\($0.0),\(csvEscape($0.1))" }
        return (lines.joined(separator: "\n") + "\n", rows.count)
    }

    private static func csvEscape(_ field: String) -> String {
        guard field.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func makeFormatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar.current
        f.timeZone = Calendar.current.timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = format
        return f
    }
    private static let dayFormatter = makeFormatter("yyyy-MM-dd")
    private static let hourFormatter = makeFormatter("yyyy-MM-dd HH:00")

    private static func dayString(_ date: Date, hourly: Bool = false) -> String {
        (hourly ? hourFormatter : dayFormatter).string(from: date)
    }

    /// The Health database can't be read while the phone is locked; surface that, ignore other per-type errors.
    private static func shouldRethrow(_ error: Error) -> Bool {
        (error as? HKError)?.code == .errorDatabaseInaccessible || error is CancellationError
    }

    private static func dailyStatistics(_ spec: Spec, from start: Date, to end: Date, hourly: Bool = false) async throws -> [ExportRow] {
        let type = HKQuantityType(spec.id)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        let options: HKStatisticsOptions = spec.cumulative ? .cumulativeSum : [.discreteAverage, .discreteMin, .discreteMax]
        let unitLabel = spec.unit.unitString

        do {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[ExportRow], Error>) in
                let query = HKStatisticsCollectionQuery(quantityType: type,
                                                        quantitySamplePredicate: predicate,
                                                        options: options,
                                                        anchorDate: start,
                                                        intervalComponents: hourly ? DateComponents(hour: 1) : DateComponents(day: 1))
                query.initialResultsHandler = { _, results, error in
                    if let error { cont.resume(throwing: error); return }
                    var rows: [ExportRow] = []
                    results?.enumerateStatistics(from: start, to: end) { stats, _ in
                        let day = dayString(stats.startDate, hourly: hourly)
                        func add(_ stat: String, _ q: HKQuantity?) {
                            guard let q else { return }
                            rows.append(ExportRow(date: day, metric: spec.name, stat: stat,
                                                  value: q.doubleValue(for: spec.unit), unit: unitLabel))
                        }
                        if spec.cumulative {
                            add("sum", stats.sumQuantity())
                        } else {
                            add("avg", stats.averageQuantity())
                            add("min", stats.minimumQuantity())
                            add("max", stats.maximumQuantity())
                        }
                    }
                    cont.resume(returning: rows)
                }
                store.execute(query)
            }
        } catch {
            if shouldRethrow(error) { throw error }
            return []
        }
    }

    private static func samples(of type: HKSampleType, from start: Date, to end: Date) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [])
        return try await withCheckedThrowingContinuation { cont in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: nil) { _, samples, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: samples ?? []) }
            }
            store.execute(query)
        }
    }

    /// Hours asleep per night per stage, attributed to the day the sleep ended.
    private static func sleepRows(from start: Date, to end: Date) async throws -> [ExportRow] {
        let all: [HKSample]
        do { all = try await samples(of: sleepType, from: start, to: end) }
        catch { if shouldRethrow(error) { throw error }; return [] }

        var totals: [String: Double] = [:]   // "day|metric" -> hours
        for case let s as HKCategorySample in all {
            let stage: String
            switch HKCategoryValueSleepAnalysis(rawValue: s.value) {
            case .asleepCore: stage = "sleep_core"
            case .asleepDeep: stage = "sleep_deep"
            case .asleepREM: stage = "sleep_rem"
            case .asleepUnspecified: stage = "sleep_asleep"
            case .awake: stage = "sleep_awake"
            case .inBed: stage = "sleep_in_bed"
            default: continue
            }
            let key = "\(dayString(s.endDate))|\(stage)"
            totals[key, default: 0] += s.endDate.timeIntervalSince(s.startDate) / 3600
        }
        var rows = totals.map { key, hours -> ExportRow in
            let parts = key.split(separator: "|")
            return ExportRow(date: String(parts[0]), metric: String(parts[1]), stat: "sum", value: hours, unit: "hr")
        }
        // Total time actually asleep per night (all asleep stages combined).
        var asleep: [String: Double] = [:]
        for (key, hours) in totals {
            let parts = key.split(separator: "|")
            if ["sleep_core", "sleep_deep", "sleep_rem", "sleep_asleep"].contains(String(parts[1])) {
                asleep[String(parts[0]), default: 0] += hours
            }
        }
        for (day, hours) in asleep {
            rows.append(ExportRow(date: day, metric: "sleep_total_asleep", stat: "sum", value: hours, unit: "hr"))
        }
        return rows
    }

    /// Apple Watch activity rings: move / exercise / stand, with goals.
    private static func activitySummaryRows(from start: Date, to end: Date) async throws -> [ExportRow] {
        let cal = Calendar.current
        var s = cal.dateComponents([.year, .month, .day], from: start); s.calendar = cal
        var e = cal.dateComponents([.year, .month, .day], from: end); e.calendar = cal
        let predicate = HKQuery.predicate(forActivitySummariesBetweenStart: s, end: e)
        do {
            return try await withCheckedThrowingContinuation { (cont: CheckedContinuation<[ExportRow], Error>) in
                let query = HKActivitySummaryQuery(predicate: predicate) { _, summaries, error in
                    if let error { cont.resume(throwing: error); return }
                    var rows: [ExportRow] = []
                    for summary in summaries ?? [] {
                        var comps = summary.dateComponents(for: cal)
                        comps.calendar = cal
                        guard let date = cal.date(from: comps) else { continue }
                        let day = dayString(date)
                        func add(_ metric: String, _ q: HKQuantity?, _ unit: HKUnit, _ label: String) {
                            guard let q else { return }
                            rows.append(ExportRow(date: day, metric: metric, stat: "sum", value: q.doubleValue(for: unit), unit: label))
                        }
                        add("activity_move_kcal", summary.activeEnergyBurned, .kilocalorie(), "kcal")
                        add("activity_move_goal", summary.activeEnergyBurnedGoal, .kilocalorie(), "kcal")
                        add("activity_exercise_min", summary.appleExerciseTime, .minute(), "min")
                        add("activity_exercise_goal", summary.exerciseTimeGoal, .minute(), "min")
                        add("activity_stand_hours", summary.appleStandHours, .count(), "count")
                        add("activity_stand_goal", summary.standHoursGoal, .count(), "count")
                    }
                    cont.resume(returning: rows)
                }
                store.execute(query)
            }
        } catch {
            if shouldRethrow(error) { throw error }
            return []
        }
    }

    /// Workout count, minutes and active energy per day, per workout type.
    private static func workoutRows(from start: Date, to end: Date) async throws -> [ExportRow] {
        let all: [HKSample]
        do { all = try await samples(of: .workoutType(), from: start, to: end) }
        catch { if shouldRethrow(error) { throw error }; return [] }

        var totals: [String: Double] = [:]   // "day|metric|unit" -> value
        for case let w as HKWorkout in all {
            let day = dayString(w.startDate)
            let name = workoutName(w.workoutActivityType)
            totals["\(day)|workout_\(name)_count|count", default: 0] += 1
            totals["\(day)|workout_\(name)_minutes|min", default: 0] += w.duration / 60
            if let kcal = w.statistics(for: HKQuantityType(.activeEnergyBurned))?.sumQuantity()?.doubleValue(for: .kilocalorie()) {
                totals["\(day)|workout_\(name)_energy|kcal", default: 0] += kcal
            }
        }
        return totals.map { key, value in
            let p = key.split(separator: "|").map(String.init)
            return ExportRow(date: p[0], metric: p[1], stat: "sum", value: value, unit: p[2])
        }
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .walking: return "walking"
        case .running: return "running"
        case .cycling: return "cycling"
        case .swimming: return "swimming"
        case .hiking: return "hiking"
        case .yoga: return "yoga"
        case .functionalStrengthTraining, .traditionalStrengthTraining: return "strength"
        case .highIntensityIntervalTraining: return "hiit"
        case .elliptical: return "elliptical"
        case .rowing: return "rowing"
        default: return "other"
        }
    }
}
