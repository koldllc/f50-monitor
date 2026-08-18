import Foundation

public struct F50SMSMessage: Identifiable, Equatable {
    public let id: String
    public let number: String
    public let content: String
    public let dateText: String
    public let tag: String
    public var isLocallyRead: Bool

    public var isUnread: Bool { (tag == "1" || tag.lowercased() == "unread") && !isLocallyRead }
    public var isOutgoing: Bool { tag == "2" || tag == "3" }
    public var didFailToSend: Bool { tag == "5" || tag.lowercased() == "failed" }

    public init(id: String, number: String, content: String, dateText: String, tag: String, isLocallyRead: Bool = false) {
        self.id = id
        self.number = number
        self.content = content
        self.dateText = dateText
        self.tag = tag
        self.isLocallyRead = isLocallyRead
    }
}
