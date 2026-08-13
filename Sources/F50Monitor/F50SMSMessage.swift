import Foundation

public struct F50SMSMessage: Identifiable, Equatable {
    public let id: String
    public let number: String
    public let content: String
    public let dateText: String
    public let tag: String

    public var isUnread: Bool { tag == "1" }
    public var isOutgoing: Bool { tag == "2" || tag == "3" }
    public var didFailToSend: Bool { tag == "3" }
}
