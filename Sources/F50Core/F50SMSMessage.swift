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

    // MARK: - 审核与演示模式模拟短信
    public static var mockMessages: [F50SMSMessage] {
        [
            F50SMSMessage(
                id: "mock-1",
                number: "106900008888",
                content: "【F50 管理】您正在登录随身 WiFi 后台管理面板，验证码为 682390，请在 5 分钟内输入。切勿泄露给他人。",
                dateText: "2026-08-22 14:20:15",
                tag: "1",
                isLocallyRead: false
            ),
            F50SMSMessage(
                id: "mock-2",
                number: "10086",
                content: "【中国移动】尊敬的客户，截至今日您的 5G 随身 WiFi 套餐国内通用流量已使用 40.00 GB，剩余 60.00 GB。感谢您的使用。",
                dateText: "2026-08-20 09:12:00",
                tag: "0",
                isLocallyRead: true
            ),
            F50SMSMessage(
                id: "mock-3",
                number: "10086",
                content: "【中国移动】您的 5G 速率体验包已生效，下行最高速率可达 1000Mbps，上行最高可达 150Mbps。",
                dateText: "2026-08-15 11:30:22",
                tag: "0",
                isLocallyRead: true
            )
        ]
    }
}
