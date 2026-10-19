#if DEBUG
import Foundation

/// Erfundenes Gym fuer Aufnahmen im Simulator (`COCKPIT_GYM_DEMO=1`): zwei
/// Tage, sechs Geraete, eine kleine Geraeteliste, ein paar Wochen Verlauf. Nur Platzhalter („Gerät A“,
/// Notiz „Sitz 4“) - das Repo ist oeffentlich. Nur im Speicher, nie gesendet.
enum GymDemo {

    static func state(today: CalendarDate) -> GymState {
        var machines = ["A", "B", "C", "D", "E", "F"].map {
            GymMachine(id: "m-demo-\($0.lowercased())", name: "Gerät \($0)", archived: false, createdAt: nil)
        }
        machines[0].note = "Sitz 4"
        func exercise(_ letter: String, _ sets: Int, _ reps: Int, _ kg: Double, from repsMin: Int? = nil) -> GymExercise {
            GymExercise(id: "e-demo-\(letter)", machineId: "m-demo-\(letter)", sets: sets, reps: reps,
                        repsMin: repsMin, weightKg: kg)
        }
        let dayA = GymDay(id: "d-demo-a", name: "Tag A", position: 0,
                          exercises: [exercise("a", 3, 10, 40, from: 8), exercise("b", 3, 10, 27.5),
                                      exercise("c", 4, 12, 0)],
                          weekdays: [1, 4])
        let dayB = GymDay(id: "d-demo-b", name: "Tag B", position: 1,
                          exercises: [exercise("d", 2, 8, 60, from: 6), exercise("e", 3, 10, 35),
                                      exercise("f", 3, 15, 12.5)],
                          weekdays: [2, 5])
        var last: [String: GymLast] = [:]
        for day in [dayA, dayB] {
            for e in day.exercises {
                // Mit Spanne nicht jeder Satz bis oben - so steht „10, 9, 8“ da.
                let setReps = (0..<e.sets).map { max(e.reps - (e.repsRange == nil ? 0 : $0), e.repsLower) }
                last[e.machineId] = GymLast(date: today.adding(days: day.id == "d-demo-a" ? -3 : -2),
                                            weightKg: max(e.weightKg - 2.5, 0), sets: e.sets, reps: e.reps,
                                            setReps: setReps)
            }
        }
        let catalog = [
            GymCatalogGroup(name: "Gruppe A", entries: ["Gerät A", "Gerät G", "Gerät H", "Gerät I"]),
            GymCatalogGroup(name: "Gruppe B", entries: ["Gerät J", "Gerät K", "Gerät L"]),
            GymCatalogGroup(name: "Gruppe C", entries: ["Gerät M", "Gerät N"]),
        ]
        return GymState(today: today, machines: machines, days: [dayA, dayB], nextDayId: dayA.id,
                        sessions: [], last: last, catalog: catalog)
    }

    /// Acht Wochen, zweimal je Woche, langsam schwerer - manchmal fehlt im
    /// letzten Satz eine Wiederholung.
    static func history(machineId: String, today: CalendarDate) -> [GymHistoryPoint] {
        var generator = SplitMix(seed: machineId.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) })
        var kg = 30.0
        return stride(from: 56, through: 2, by: -3).map { offset in
            if generator.next() % 3 == 0 { kg += 2.5 }
            let setReps = generator.next() % 2 == 0 ? [8, 8, 8] : [8, 8, 7]
            return GymHistoryPoint(date: today.adding(days: -offset), weightKg: kg, sets: 3, reps: 8, setReps: setReps)
        }
    }
}
#endif
