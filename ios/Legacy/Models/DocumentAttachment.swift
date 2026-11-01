import Foundation
import SwiftData

@Model
public final class DocumentAttachment {
    public var id: UUID
    public var fileName: String
    public var fileExtension: String
    @Attribute(.externalStorage) public var fileData: Data?
    public var extractedText: String?
    public var createdAt: Date
    
    public var event: LifecycleEvent?
    public var asset: Asset?
    
    public init(
        id: UUID = UUID(),
        fileName: String,
        fileExtension: String,
        fileData: Data? = nil,
        extractedText: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.fileName = fileName
        self.fileExtension = fileExtension
        self.fileData = fileData
        self.extractedText = extractedText
        self.createdAt = createdAt
    }
}
