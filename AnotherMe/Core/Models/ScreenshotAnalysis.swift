import Foundation

/// Structured result returned by AI screenshot analysis
struct ScreenshotAnalysis: Codable {
    let appName: String
    let windowTitle: String
    let visibleApps: [String]?
    let activityCategory: String
    let topics: [String]
    let contentSummary: String
    let extractedText: ExtractedText?
    let userIntent: String?
    let engagementLevel: String?

    struct ExtractedText: Codable {
        let userAuthored: String?
        let userExpressions: [String]?
        let readingContent: String?
        let codeSnippets: String?
        let uiData: String?

        enum CodingKeys: String, CodingKey {
            case userAuthored = "user_authored"
            case userExpressions = "user_expressions"
            case readingContent = "reading_content"
            case codeSnippets = "code_snippets"
            case uiData = "ui_data"
        }

        /// Flatten all non-empty parts into a single string for storage
        var combined: String {
            var parts = [userAuthored, readingContent, codeSnippets, uiData]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
            if let expressions = userExpressions?.filter({ !$0.isEmpty }), !expressions.isEmpty {
                parts.append(expressions.joined(separator: "\n"))
            }
            return parts.joined(separator: "\n\n")
        }

        /// All user expressions combined: userAuthored + userExpressions array
        var allUserText: String {
            var parts: [String] = []
            if let authored = userAuthored, !authored.isEmpty {
                parts.append(authored)
            }
            if let expressions = userExpressions {
                parts.append(contentsOf: expressions.filter { !$0.isEmpty })
            }
            return parts.joined(separator: "\n")
        }
    }

    enum CodingKeys: String, CodingKey {
        case appName = "app_name"
        case windowTitle = "window_title"
        case visibleApps = "visible_apps"
        case activityCategory = "activity_category"
        case topics
        case contentSummary = "content_summary"
        case extractedText = "extracted_text"
        case userIntent = "user_intent"
        case engagementLevel = "engagement_level"
    }
}
