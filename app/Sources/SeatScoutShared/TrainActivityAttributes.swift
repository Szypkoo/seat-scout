import ActivityKit
import Foundation

public struct TrainActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable, Sendable {
        public var phase: String
        public var headline: String
        public var nextStop: String
        public var nextDate: Date?
        public var delayMinutes: Int?
        public var seatText: String?
        public var changeText: String?
        public var changeDate: Date?
        public var progress: Double

        public init(phase: String, headline: String, nextStop: String, nextDate: Date?, delayMinutes: Int?,
                    seatText: String?, changeText: String?, changeDate: Date?, progress: Double) {
            self.phase = phase
            self.headline = headline
            self.nextStop = nextStop
            self.nextDate = nextDate
            self.delayMinutes = delayMinutes
            self.seatText = seatText
            self.changeText = changeText
            self.changeDate = changeDate
            self.progress = progress
        }
    }

    public var trainLabel: String
    public var route: String

    public init(trainLabel: String, route: String) {
        self.trainLabel = trainLabel
        self.route = route
    }
}
