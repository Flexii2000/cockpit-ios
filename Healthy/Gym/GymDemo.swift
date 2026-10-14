#if DEBUG
import Foundation

/// Erfundenes Gym fuer Aufnahmen im Simulator (`COCKPIT_GYM_DEMO=1`): zwei
/// Tage, sechs Geraete, ein paar Wochen Verlauf. Nur Platzhalter („Gerät A“) -
/// das Repo ist oeffentlich. Nur im Speicher, nie gesendet.
enum GymDemo {

    static func state(today: CalendarDate) -> GymState {
        let machines = ["A", "B", "C", "D", "E", "F"].map {
            GymMachine(id: "m-demo-\($0.lowercased())", name: "Gerät \($0)", archived: false, createdAt: nil)
        }
        func exercise(_ letter: String, _ sets: Int, _ reps: Int, _ kg: Double) -> GymExercise {
            GymExercise(id: "e-demo-\(letter)", machineId: "m-demo-\(letter)", sets: sets, reps: reps, weightKg: kg)
        }
        let dayA = GymDay(id: "d-demo-a", name: "Tag A", position: 0,
                          exercises: [exercise("a", 3, 8, 40), exercise("b", 3, 10, 27.5), exercise("c", 4, 12, 0)])
        let dayB = GymDay(id: "d-demo-b", name: "Tag B", position: 1,
                          exercises: [exercise("d", 3, 8, 60), exercise("e", 3, 10, 35), exercise("f", 3, 15, 12.5)])
        var last: [String: GymLast] = [:]
        for day in [dayA, dayB] {
            for e in day.exercises {
                last[e.machineId] = GymLast(date: today.adding(days: day.id == "d-demo-a" ? -3 : -2),
                                            weightKg: max(e.weightKg - 2.5, 0), sets: e.sets, reps: e.reps)
            }
        }
        return GymState(today: today, machines: machines, days: [dayA, dayB], nextDayId: dayA.id,
                        sessions: [], last: last)
    }

    /// Acht Wochen, zweimal je Woche, langsam schwerer.
    static func history(machineId: String, today: CalendarDate) -> [GymHistoryPoint] {
        var generator = SplitMix(seed: machineId.unicodeScalars.reduce(UInt64(7)) { $0 &* 31 &+ UInt64($1.value) })
        var kg = 30.0
        return stride(from: 56, through: 2, by: -3).map { offset in
            if generator.next() % 3 == 0 { kg += 2.5 }
            return GymHistoryPoint(date: today.adding(days: -offset), weightKg: kg, sets: 3, reps: 8)
        }
    }
}
#endif
