import Foundation

public enum JSONC {
    public static func strip(_ data: Data) -> Data {
        Data(strip(String(decoding: data, as: UTF8.self)).utf8)
    }

    public static func strip(_ source: String) -> String {
        let chars = Array(source.unicodeScalars)
        var output = String.UnicodeScalarView()
        var index = 0
        var inString = false
        while index < chars.count {
            let char = chars[index]
            let next: Unicode.Scalar? = index + 1 < chars.count ? chars[index + 1] : nil
            if inString {
                output.append(char)
                if char == "\\", let next {
                    output.append(next)
                    index += 2
                    continue
                }
                if char == "\"" { inString = false }
                index += 1
            } else if char == "\"" {
                inString = true
                output.append(char)
                index += 1
            } else if char == "/", next == "/" {
                while index < chars.count, chars[index] != "\n" { index += 1 }
            } else if char == "/", next == "*" {
                index += 2
                skipBlockComment(in: chars, index: &index)
            } else if char == "," {
                let trailing = isTrailingComma(in: chars, after: index)
                if !trailing { output.append(char) }
                index += 1
            } else {
                output.append(char)
                index += 1
            }
        }
        return String(output)
    }

    private static func isTrailingComma(in chars: [Unicode.Scalar], after index: Int) -> Bool {
        var lookahead = index + 1
        while lookahead < chars.count {
            let char = chars[lookahead]
            let next: Unicode.Scalar? = lookahead + 1 < chars.count ? chars[lookahead + 1] : nil
            if char == " " || char == "\t" || char == "\n" || char == "\r" {
                lookahead += 1
            } else if char == "/", next == "/" {
                while lookahead < chars.count, chars[lookahead] != "\n" { lookahead += 1 }
            } else if char == "/", next == "*" {
                lookahead += 2
                skipBlockComment(in: chars, index: &lookahead)
            } else {
                return char == "}" || char == "]"
            }
        }
        return false
    }

    private static func skipBlockComment(in chars: [Unicode.Scalar], index: inout Int) {
        while index < chars.count, !(chars[index] == "*" && index + 1 < chars.count && chars[index + 1] == "/") {
            index += 1
        }
        index += 2
    }

}
