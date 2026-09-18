import Foundation

let apple = """
     (
    /
  .-'''-.
 (       )
 (       )
  '-...-'
"""

// print() just shows whatever is inside the string
print(apple)

// split() breaks the string apart every time it sees a line break (\n)
// turns it into a list (array) of separate lines
let lines = apple.split(separator: "\n")
print("The apple has \(lines.count) lines")

// a "for loop" repeats the code inside it once for every item in a list
// here it goes through the lines one at a time and prints each one
for line in lines {
    print("-> \(line)")
}
