import Foundation

// MARK: - JSONPathExpression

struct JSONPathExpression: Equatable, Sendable {
    enum Origin: Equatable, Sendable {
        case root
        case current
    }

    let origin: Origin
    var segments: [JSONPathSegment]
    var tailFunction: JSONPathFunctionCall?
}

// MARK: - JSONPathSegment

enum JSONPathSegment: Equatable, Sendable {
    case child([JSONPathSelector])
    case descendant([JSONPathSelector])
}

// MARK: - JSONPathSelector

enum JSONPathSelector: Equatable, Sendable {
    case name(String)
    case index(Int)
    case wildcard
    case slice(start: Int?, end: Int?, step: Int?)
    case filter(JSONPathFilterExpression)
}

// MARK: - JSONPathFunctionCall

struct JSONPathFunctionCall: Equatable, Sendable {
    let name: String
    let arguments: [JSONPathFilterExpression]
}

// MARK: - JSONPathFilterExpression

indirect enum JSONPathFilterExpression: Equatable, Sendable {
    case literal(JSONPathLiteral)
    case path(JSONPathExpression)
    case array([JSONPathFilterExpression])
    case function(JSONPathFunctionCall)
    case unaryNot(JSONPathFilterExpression)
    case binary(JSONPathFilterExpression, JSONPathBinaryOperator, JSONPathFilterExpression)
}

// MARK: - JSONPathLiteral

enum JSONPathLiteral: Equatable, Sendable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case regex(pattern: String, options: NSRegularExpression.Options)
}

// MARK: - JSONPathBinaryOperator

enum JSONPathBinaryOperator: String, Equatable, Sendable {
    case equal
    case notEqual
    case less
    case lessOrEqual
    case greater
    case greaterOrEqual
    case regexMatch
    case and
    case or
    case `in`
    case nin
    case subsetof
    case anyof
    case noneof
    case size
    case empty
}

// MARK: - JSONPathParser

struct JSONPathParser {
    // MARK: Lifecycle

    init(tokens: [JSONPathToken], limits: JSONPathEvaluationLimits = .default) {
        self.tokens = tokens
        self.limits = limits
    }

    init(source: String, limits: JSONPathEvaluationLimits = .default) throws {
        self.limits = limits
        tokens = try JSONPathLexer(source: source, limits: limits).tokenize()
    }

    // MARK: Internal

    mutating func parse() throws -> JSONPathExpression {
        let expression = try parsePathExpression(required: true, depth: 0)
        guard current == .eof else {
            throw JSONPathError.invalidQuery(String(
                localized: "Unexpected token at end of query.",
                bundle: RockxyLocalization.bundle
            ))
        }
        return expression
    }

    // MARK: Private

    private var tokens: [JSONPathToken]
    private var index: Int = 0
    private let limits: JSONPathEvaluationLimits

    private var current: JSONPathToken {
        tokens[index]
    }

    private mutating func parsePathExpression(required: Bool, depth: Int) throws -> JSONPathExpression {
        guard depth <= limits.maxASTDepth else {
            throw JSONPathError.limitExceeded(String(
                localized: "Query is too complex.",
                bundle: RockxyLocalization.bundle
            ))
        }

        let origin: JSONPathExpression.Origin
        if match(.root) {
            origin = .root
        } else if match(.current) {
            origin = .current
        } else if required {
            throw JSONPathError.invalidQuery(String(
                localized: "Query must start with $ or @.",
                bundle: RockxyLocalization.bundle
            ))
        } else {
            throw JSONPathError.invalidQuery(String(
                localized: "Expected path expression.",
                bundle: RockxyLocalization.bundle
            ))
        }

        var expression = JSONPathExpression(origin: origin, segments: [], tailFunction: nil)
        while true {
            if match(.dot) {
                if match(.star) {
                    expression.segments.append(.child([.wildcard]))
                } else {
                    let name = try consumeIdentifier()
                    if current == .leftParen {
                        expression.tailFunction = try parseFunctionCall(name: name, depth: depth + 1)
                        break
                    }
                    expression.segments.append(.child([.name(name)]))
                }
            } else if match(.deepScan) {
                if match(.star) {
                    expression.segments.append(.descendant([.wildcard]))
                } else if match(.leftBracket) {
                    let selectors = try parseSelectors(depth: depth + 1)
                    try consume(
                        .rightBracket,
                        message: String(localized: "Expected ].", bundle: RockxyLocalization.bundle)
                    )
                    expression.segments.append(.descendant(selectors))
                } else {
                    try expression.segments.append(.descendant([.name(consumeIdentifier())]))
                }
            } else if match(.leftBracket) {
                let selectors = try parseSelectors(depth: depth + 1)
                try consume(.rightBracket, message: String(localized: "Expected ].", bundle: RockxyLocalization.bundle))
                expression.segments.append(.child(selectors))
            } else {
                break
            }
        }

        return expression
    }

    private mutating func parseSelectors(depth: Int) throws -> [JSONPathSelector] {
        if match(.question) {
            try consume(
                .leftParen,
                message: String(localized: "Expected ( after ?.", bundle: RockxyLocalization.bundle)
            )
            let filter = try parseFilterExpression(depth: depth + 1)
            try consume(
                .rightParen,
                message: String(localized: "Expected ) after filter.", bundle: RockxyLocalization.bundle)
            )
            return [.filter(filter)]
        }

        var selectors: [JSONPathSelector] = []
        repeat {
            if match(.star) {
                selectors.append(.wildcard)
            } else if case let .string(value) = current {
                advance()
                selectors.append(.name(value))
            } else if case let .number(value) = current {
                advance()
                if current == .colon {
                    try selectors.append(parseSlice(start: Int(value), depth: depth))
                } else {
                    selectors.append(.index(Int(value) ?? 0))
                }
            } else if match(.colon) {
                try selectors.append(parseSlice(start: nil, consumedFirstColon: true, depth: depth))
            } else {
                throw JSONPathError.invalidQuery(String(
                    localized: "Invalid bracket selector.",
                    bundle: RockxyLocalization.bundle
                ))
            }
        } while match(.comma)

        return selectors
    }

    private mutating func parseSlice(
        start: Int?,
        consumedFirstColon: Bool = false,
        depth _: Int
    )
        throws -> JSONPathSelector
    {
        if !consumedFirstColon {
            try consume(.colon, message: String(localized: "Expected : in slice.", bundle: RockxyLocalization.bundle))
        }
        let end = consumeOptionalInt()
        let step: Int? = if match(.colon) {
            consumeOptionalInt()
        } else {
            nil
        }
        return .slice(start: start, end: end, step: step)
    }

    private mutating func parseFilterExpression(depth: Int) throws -> JSONPathFilterExpression {
        try parseOr(depth: depth)
    }

    private mutating func parseOr(depth: Int) throws -> JSONPathFilterExpression {
        var expr = try parseAnd(depth: depth + 1)
        while match(.or) {
            expr = try .binary(expr, .or, parseAnd(depth: depth + 1))
        }
        return expr
    }

    private mutating func parseAnd(depth: Int) throws -> JSONPathFilterExpression {
        var expr = try parseComparison(depth: depth + 1)
        while match(.and) {
            expr = try .binary(expr, .and, parseComparison(depth: depth + 1))
        }
        return expr
    }

    private mutating func parseComparison(depth: Int) throws -> JSONPathFilterExpression {
        var expr = try parseUnary(depth: depth + 1)
        while let op = consumeComparisonOperator() {
            expr = try .binary(expr, op, parseUnary(depth: depth + 1))
        }
        return expr
    }

    private mutating func parseUnary(depth: Int) throws -> JSONPathFilterExpression {
        if match(.bang) {
            return try .unaryNot(parseUnary(depth: depth + 1))
        }
        return try parsePrimary(depth: depth + 1)
    }

    private mutating func parsePrimary(depth: Int) throws -> JSONPathFilterExpression {
        switch current {
        case .root,
             .current:
            return try .path(parsePathExpression(required: true, depth: depth + 1))
        case let .string(value):
            advance()
            return .literal(.string(value))
        case let .number(value):
            advance()
            return .literal(.number(Double(value) ?? 0))
        case let .bool(value):
            advance()
            return .literal(.bool(value))
        case .null:
            advance()
            return .literal(.null)
        case let .regex(pattern, options):
            advance()
            return .literal(.regex(pattern: pattern, options: options))
        case .leftBracket:
            advance()
            var values: [JSONPathFilterExpression] = []
            if current != .rightBracket {
                repeat {
                    try values.append(parseFilterExpression(depth: depth + 1))
                } while match(.comma)
            }
            try consume(.rightBracket, message: String(localized: "Expected ].", bundle: RockxyLocalization.bundle))
            return .array(values)
        case let .identifier(name):
            advance()
            if current == .leftParen {
                return try .function(parseFunctionCall(name: name, depth: depth + 1))
            }
            return .literal(.string(name))
        case .leftParen:
            advance()
            let expr = try parseFilterExpression(depth: depth + 1)
            try consume(.rightParen, message: String(localized: "Expected ).", bundle: RockxyLocalization.bundle))
            return expr
        default:
            throw JSONPathError.invalidQuery(String(
                localized: "Expected expression.",
                bundle: RockxyLocalization.bundle
            ))
        }
    }

    private mutating func parseFunctionCall(name: String, depth: Int) throws -> JSONPathFunctionCall {
        try consume(.leftParen, message: String(localized: "Expected (.", bundle: RockxyLocalization.bundle))
        var args: [JSONPathFilterExpression] = []
        if current != .rightParen {
            repeat {
                try args.append(parseFilterExpression(depth: depth + 1))
            } while match(.comma)
        }
        try consume(.rightParen, message: String(localized: "Expected ).", bundle: RockxyLocalization.bundle))
        return JSONPathFunctionCall(name: name, arguments: args)
    }

    private mutating func consumeComparisonOperator() -> JSONPathBinaryOperator? {
        switch current {
        case .equal:
            advance()
            return .equal
        case .notEqual:
            advance()
            return .notEqual
        case .less:
            advance()
            return .less
        case .lessOrEqual:
            advance()
            return .lessOrEqual
        case .greater:
            advance()
            return .greater
        case .greaterOrEqual:
            advance()
            return .greaterOrEqual
        case .regexMatch:
            advance()
            return .regexMatch
        case let .identifier(name):
            switch name {
            case "in": advance()
                return .in
            case "nin": advance()
                return .nin
            case "subsetof": advance()
                return .subsetof
            case "anyof": advance()
                return .anyof
            case "noneof": advance()
                return .noneof
            case "size": advance()
                return .size
            case "empty": advance()
                return .empty
            default: return nil
            }
        default:
            return nil
        }
    }

    private mutating func advance() {
        index = min(index + 1, tokens.count - 1)
    }

    private mutating func match(_ token: JSONPathToken) -> Bool {
        guard current == token else {
            return false
        }
        advance()
        return true
    }

    private mutating func consume(_ token: JSONPathToken, message: String) throws {
        guard match(token) else {
            throw JSONPathError.invalidQuery(message)
        }
    }

    private mutating func consumeIdentifier() throws -> String {
        guard case let .identifier(value) = current else {
            throw JSONPathError.invalidQuery(String(
                localized: "Expected identifier.",
                bundle: RockxyLocalization.bundle
            ))
        }
        advance()
        return value
    }

    private mutating func consumeOptionalInt() -> Int? {
        guard case let .number(value) = current else {
            return nil
        }
        advance()
        return Int(value)
    }
}
