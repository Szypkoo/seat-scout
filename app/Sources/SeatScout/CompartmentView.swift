import Foundation

struct CompartmentLayout {
    struct Group: Identifiable {
        let id: Int
        let rows: [[CoreSeat]]
    }

    let groups: [Group]

    init?(seats: [CoreSeat]) {
        guard !seats.isEmpty, seats.allSatisfy({ $0.xy != nil && $0.number % 10 != 0 }) else { return nil }
        let grouped = Dictionary(grouping: seats, by: { $0.number / 10 })
        guard grouped.count >= 2 else { return nil }

        var result: [Group] = []
        for number in grouped.keys.sorted() {
            guard let seats = grouped[number], seats.count == 6 || seats.count == 8 else { return nil }
            let numbers = Set(seats.map { $0.number % 10 })
            guard numbers == Set(1...seats.count) else { return nil }
            let positions = seats.compactMap(\.xy)
            let rows = Set(positions.map(\.x)).sorted()
            let columns = Set(positions.map(\.y)).sorted()
            guard rows.count == 2, columns.count * 2 == seats.count else { return nil }
            let arranged = rows.map { row in
                seats.filter { $0.xy?.x == row }.sorted { $0.xy!.y < $1.xy!.y }
            }
            guard arranged.allSatisfy({ $0.count == columns.count && Set($0.compactMap { $0.xy?.y }).count == columns.count }) else { return nil }
            result.append(Group(id: number, rows: arranged))
        }
        groups = result
    }
}
