import Foundation
import SwiftUI

/// 本地化辅助函数 - 使用动态 Bundle 支持即时语言切换
func L(_ key: String) -> String {
    LanguageService.shared.localizedString(key)
}

/// 本地化辅助函数（带参数）
func L(_ key: String, _ arguments: CVarArg...) -> String {
    let format = LanguageService.shared.localizedString(key)
    return String(format: format, arguments: arguments)
}

/// 本地化辅助函数（带 Int 参数）- 专门处理 %lld 格式
func L(_ key: String, _ arg: Int) -> String {
    let format = LanguageService.shared.localizedString(key)
    return String(format: format, arg)
}
