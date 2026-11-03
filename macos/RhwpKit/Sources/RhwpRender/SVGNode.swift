import Foundation

/// SVG 조각을 읽어 만든 가벼운 트리. 속성은 문자열 그대로 두고 해석은 그리는 쪽이 한다.
final class SVGNode {
    enum Child {
        case element(SVGNode)
        case text(String)
    }

    let name: String
    let attributes: [String: String]
    var children: [Child] = []

    init(name: String, attributes: [String: String]) {
        self.name = name
        self.attributes = attributes
    }

    /// XML을 읽어 루트(우리가 조각을 감싼 가상 `svg`)를 돌려준다. 문서가 중간에 깨지면 거기까지 읽은 트리와
    /// `complete == false`를 돌려준다(없는 것보다 일부라도 그리는 편이 낫다).
    static func parse(_ data: Data) -> (root: SVGNode, complete: Bool) {
        let builder = Builder()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = false
        parser.delegate = builder
        let complete = parser.parse()
        return (builder.root ?? SVGNode(name: "svg", attributes: [:]), complete)
    }

    private final class Builder: NSObject, XMLParserDelegate {
        var root: SVGNode?
        private var stack: [SVGNode] = []

        func parser(
            _ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
            attributes attributeDict: [String: String]
        ) {
            let node = SVGNode(name: elementName, attributes: attributeDict)
            if let parent = stack.last {
                parent.children.append(.element(node))
            } else {
                root = node
            }
            stack.append(node)
        }

        func parser(_ parser: XMLParser, foundCharacters string: String) {
            guard let node = stack.last else { return }
            // 파서는 엔티티(`&amp;`)마다 글자를 끊어 준다. 이어 붙여야 공백 접기가 조각 경계에서 틀어지지 않는다.
            if case let .text(previous)? = node.children.last {
                node.children[node.children.count - 1] = .text(previous + string)
            } else {
                node.children.append(.text(string))
            }
        }

        func parser(
            _ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName: String?
        ) {
            _ = stack.popLast()
        }
    }
}
