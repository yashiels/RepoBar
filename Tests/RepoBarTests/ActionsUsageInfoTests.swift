import Foundation
@testable import RepoBarCore
import Testing

struct ActionsUsageInfoTests {
    @Test
    func `current month minutes include GitHub billing date only rows`() {
        let usage = ActionsUsageInfo(
            items: [
                Self.item(date: "2026-05-01", quantity: 12),
                Self.item(date: "2026-05-14T10:15:00Z", quantity: 3),
                Self.item(date: "2026-04-30", quantity: 100),
                Self.item(date: "2026-05-02", quantity: 7, unitType: "gb")
            ],
            fetchedAt: Self.date("2026-05-14T12:00:00Z")
        )

        #expect(usage.minutesUsedInCurrentMonth(now: Self.date("2026-05-14T12:00:00Z")) == 15)
    }

    @Test
    func `usage date parser accepts date only and internet dates`() {
        #expect(ActionsUsageInfo.date(fromUsageDate: "2026-05-01") == Self.date("2026-05-01T00:00:00Z"))
        #expect(ActionsUsageInfo.date(fromUsageDate: "2026-05-01T12:34:56Z") == Self.date("2026-05-01T12:34:56Z"))
        #expect(ActionsUsageInfo.date(fromUsageDate: "not-a-date") == nil)
    }

    private static func item(date: String, quantity: Double, unitType: String = "minutes") -> ActionsUsageItem {
        ActionsUsageItem(
            date: date,
            product: "actions",
            sku: "Actions Linux",
            quantity: quantity,
            unitType: unitType,
            pricePerUnit: 0,
            grossAmount: 0,
            netAmount: 0,
            organizationName: nil,
            repositoryName: nil
        )
    }

    private static func date(_ raw: String) -> Date {
        ISO8601DateFormatter().date(from: raw)!
    }
}
