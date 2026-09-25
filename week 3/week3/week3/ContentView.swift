
import SwiftUI

// array of colors to pick from
let colors: [Color] = [.red, .green, .yellow, .orange]

// the grid is 6 tiles across and 8 tiles down
let columns = 6
let rows = 8

// is it a juice box? what color?
struct Tile {
    var isJuiceBox: Bool
    var color: Color
}

// make an array of random tiles
func makeTiles() -> [Tile] {
    var tiles: [Tile] = []
    for _ in 0..<(columns * rows) {
        let isJuiceBox = Bool.random()          // coin flip, like 10print!
        let color = colors.randomElement()!     // random color from the array
        tiles.append(Tile(isJuiceBox: isJuiceBox, color: color))
    }
    return tiles
}

// draw one tile at column "col", row "row"
func drawTile(_ tile: Tile, col: Int, row: Int, size: CGFloat, context: GraphicsContext) {
    let x = CGFloat(col) * size     // left edge of this tile
    let y = CGFloat(row) * size     // top edge of this tile

    if tile.isJuiceBox {
        // juice box = a rectangle
        let box = CGRect(x: x + size * 0.25, y: y + size * 0.3, width: size * 0.5, height: size * 0.6)
        context.fill(Path(box), with: .color(tile.color))

        // straw = a line sticking out the top
        var straw = Path()
        straw.move(to: CGPoint(x: x + size * 0.6, y: y + size * 0.3))
        straw.addLine(to: CGPoint(x: x + size * 0.6, y: y + size * 0.1))
        context.stroke(straw, with: .color(.white), lineWidth: 4)
    } else {
        // apple = a circle
        let body = CGRect(x: x + size * 0.2, y: y + size * 0.3, width: size * 0.6, height: size * 0.6)
        context.fill(Path(ellipseIn: body), with: .color(tile.color))

        // stem = a short brown line on top
        var stem = Path()
        stem.move(to: CGPoint(x: x + size * 0.5, y: y + size * 0.3))
        stem.addLine(to: CGPoint(x: x + size * 0.5, y: y + size * 0.15))
        context.stroke(stem, with: .color(.brown), lineWidth: 4)
    }
}

// =================== The tabs ===================

struct ContentView: View {
    var body: some View {
        TabView {
            StillView()
                .tabItem { Label("Apples", systemImage: "leaf") }
            AnimatedView()
                .tabItem { Label("Animate", systemImage: "play.circle") }
        }
    }
}

struct StillView: View {
    // when tiles changes, the screen redraws
    @State private var tiles = makeTiles()

    var body: some View {
        VStack {
            Canvas { context, size in
                let tileSize = size.width / CGFloat(columns)

                // nested for loops: every row, every column
                for row in 0..<rows {
                    for col in 0..<columns {
                        let tile = tiles[row * columns + col]
                        drawTile(tile, col: col, row: row, size: tileSize, context: context)
                    }
                }
            }

            Button("Shuffle") {
                tiles = makeTiles()     // new random tiles
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(Color.black)
    }
}


struct AnimatedView: View {
    @State private var tiles = makeTiles()

    var body: some View {
        // TimelineView redraws the Canvas over and over, like a timer
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let tileSize = size.width / CGFloat(columns)

                // use the clock to decide how many tiles to show (5 new tiles per second)
                // % makes it go back to 0 and start over when the grid is full
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                let howMany = Int(seconds * 5) % (columns * rows + 1)

                for i in 0..<howMany {
                    let col = i % columns    // remainder = which column
                    let row = i / columns    // divide = which row
                    drawTile(tiles[i], col: col, row: row, size: tileSize, context: context)
                }
            }
        }
        .padding()
        .background(Color.black)
    }
}

#Preview {
    ContentView()
}
