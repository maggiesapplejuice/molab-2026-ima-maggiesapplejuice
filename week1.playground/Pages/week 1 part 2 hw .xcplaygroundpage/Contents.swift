import Foundation

let adjectives = ["crisp", "juicy", "sweet", "tart", "golden", "ripe"]
let nouns = ["apple", "orchard", "applesauce", "apple juice", "cider", "core"]
let verbs = ["drips", "ripens", "ferments", "glows", "trickles", "spills"]

func makeLine() -> String {
    let adjective = adjectives.randomElement()!
    let noun = nouns.randomElement()!
    let verb = verbs.randomElement()!
    return "The \(adjective) \(noun) \(verb)"
}

func makePoem(lines: Int) -> String {
    var poem = ""
    for _ in 0..<lines {
        poem += makeLine() + "\n"
    }
    return poem
}

print(makePoem(lines: 4))
