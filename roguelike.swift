import Foundation
import Darwin.ncurses
import GameplayKit

class Object {
	var position: (x: Int, y: Int) = (x: 0, y: 0)
	var char: String
	var solid: Bool = false
	var destructible: Bool = true
	var hp: Int = 1
	var actionOnEnter: () -> () = { } 

	init(char: String){
		self.char = char
	}

	func teleport( _ position: (x: Int, y: Int)){
		let desiredPosition = world.getTile((position)) 
		if desiredPosition != nil {
			if desiredPosition!.onGround == nil {
				let previousPosition = self.position
				world.setOnGround(position, toSet: self)	
				world.setOnGround(previousPosition, toSet: nil)
			} else {
				desiredPosition!.onGround!.actionOnEnter()
			}
		}
	}

	func spawn(_ desiredPosition: (x: Int, y: Int)) {
		let desiredTile = world.getTile(desiredPosition)
		if desiredTile != nil {
			if desiredTile!.onGround == nil {
				world.setOnGround(desiredPosition, toSet: self)
			} else {
				searchInArea: for radius in 1..<world.width {
					let circle: [(x: Int, y: Int)] = bresenhamCircle(center: desiredPosition, radius: radius)	
					for positionInCircle in circle {
						let tileInCircle: Tile? = world.getTile(positionInCircle)
						if tileInCircle != nil {
							if tileInCircle!.onGround == nil{
								world.setOnGround(positionInCircle, toSet: self)
								break searchInArea
							}
						}
					}	
				}
			}
		}
	}
}

class Tile {
	var ground: Object
	var onGround: Object?

	init(ground: Object){
		self.ground = ground
	}	
}

class World{
	let width: Int
	let height: Int
	var content: [[Tile]] = []
	var isDay: Bool = true

	init(width: Int, height: Int){
		self.width = width
		self.height = height
		for y in 0..<height {
			content.append([])
			for x in 0..<width {
				let groundObject = Object(
					char: "_"
				)
				groundObject.position = (x: x, y: y)
				let newTile = Tile(
					ground: groundObject
				)

				content[y].append(newTile)
			}
		}
	}
	
	// get a link to a tile
	func getTile(_ position: (x: Int, y: Int)) -> Tile? {
		if position.x >= 0 && position.x < width
		&& position.y >= 0 && position.y < height {
			return content[position.y][position.x]
		} else {
			return nil
		}
	}
	
	func setOnGround(_ position: (x: Int, y: Int), toSet: Object?){
		let getTile = getTile(position)
		if getTile != nil {
			getTile!.onGround = toSet
			if toSet != nil {
				toSet!.position = position
				statusLine("Set position of \(content[position.y][position.x].onGround!.char) : \(position.x), \(position.y)")
			}
		}
	}
	
	func map2d(f: (Tile) -> ()){
		for y in content {
			for x in y {
				f(x)	
			}
		}
	}	
	
	func mapMask(mask: Array<Array<Any>>, f: (Tile, Any) -> ()){
		for y in 0..<content.count {
			for x in 0..<content[y].count {
				f(content[y][x], mask[y][x])				
			}
		}	
	}
}

class Player: Object {
	init(position: (x: Int, y: Int)){
		super.init(char: "@")
		spawn(position)
	}


	func move(direction: Direction){
		switch direction {
			case .up:
				teleport((x: self.position.x, y: self.position.y - 1))
			case .right:
				teleport((x: self.position.x + 1, y: self.position.y))
			case .down:
				teleport((x: self.position.x, y: self.position.y + 1))
			case .left:
				teleport((x: self.position.x - 1, y: self.position.y))
		}
	}
		
}

enum Direction {
	case up, right, down, left
}

struct View {
	var position: (x: Int, y: Int) //position on screen
	var inWorldPosition: (x: Int, y: Int) {
		return (x: player.position.x - (player.position.x % width),
			y: player.position.y - (player.position.y % height)
			)
		//position of a top left corner inside the world
	} 
	var width: Int
	var height: Int

	func draw(){
		refresh()
		if world.isDay == false {
			for y in position.y..<position.y + height {
				for x in position.x..<position.x + width {
					move(Int32(y), Int32(x))
					addstr("░")
				}
			}
			var borderTilesCoordinates: [(x: Int, y: Int)] = []
			borderTilesCoordinates = bresenhamCircle(center: player.position, radius: width)

			for borderTileCoordinate in borderTilesCoordinates {
				let visionLineCoordinates = bresenhamLine(start: player.position, end: borderTileCoordinate )
				visionLine: for coordinate in visionLineCoordinates {
					if world.getTile(coordinate) == nil { continue }
					let tileToPrint = world.getTile(coordinate)! 
					var strToPrint: String = " "
					let onScreenPosY = Int32(coordinate.y - inWorldPosition.y + position.y)
					let onScreenPosX = Int32(coordinate.x - inWorldPosition.x + position.x)
					if onScreenPosY >= height + position.y || onScreenPosX >= width + position.x ||
					   onScreenPosY < position.y || onScreenPosX < position.x { continue }
					
					if coordinate == player.position {
						move(Int32(onScreenPosY), Int32(onScreenPosX))
						addstr(" ")
						continue
					}
					if tileToPrint.onGround != nil {
						strToPrint = tileToPrint.onGround!.char
						move(Int32(onScreenPosY), Int32(onScreenPosX))	
						addstr(strToPrint)
						break visionLine	
					} else {
						strToPrint = tileToPrint.ground.char
						move(Int32(onScreenPosY), Int32(onScreenPosX))	
						addstr(strToPrint)
					}
					
				}
			}
		
			move(Int32(player.position.y - inWorldPosition.y + position.y), Int32(player.position.x - inWorldPosition.x + position.x))
			addstr(player.char)
		} else {
			//Without vision lines:
			for y in inWorldPosition.y..<inWorldPosition.y + height{
				for x in inWorldPosition.x..<inWorldPosition.x + width {
					let rx = x - inWorldPosition.x //relative postion from a top left corner
					let ry = y - inWorldPosition.y
					move(Int32(position.y + ry), Int32(position.x + rx))
					let charToPrint: String
					let tileToPrint: Tile?
					tileToPrint = world.getTile((x: inWorldPosition.x + rx, y: inWorldPosition.y + ry))
					if let tileToPrint = tileToPrint{
						if tileToPrint.onGround != nil {
							charToPrint = tileToPrint.onGround!.char
						} else {
							charToPrint = tileToPrint.ground.char
						}
					} else {
						charToPrint = "x"
					}
					addstr(charToPrint)
				}
			}	
		}
	}
}

func statusLine( _ strToPrint: String, x: Int = 10, y: Int = 24) {
	move(Int32(y), Int32(x))
	addstr(String(repeating: " ", count: 60))
	move(Int32(y), Int32(x))
	addstr(strToPrint)
}

func perlinNoise(width: Int, height: Int, frequency: Double, seed: Int) -> Array<Array<Float>> {
	let perlinNoiseSource = GKPerlinNoiseSource(frequency: frequency, octaveCount: 6, persistence: 0.5, lacunarity: 2.0, seed: Int32(seed))
	let noise = GKNoise(perlinNoiseSource)
	let size = vector_double2(x: 1, y: 1)
	let origin = vector_double2(x: 0, y: 0)
	let sampleCount = vector_int2(x: Int32(width), y: Int32(height))
	let noiseMap = GKNoiseMap(
			noise,
		 	size: size,
			origin: origin, 
			sampleCount: sampleCount, 
			seamless: true
			)

	var result: [[Float]] = []

	for y in 0..<height {
		result.append([])
		for x in 0..<width{
			result[y].append(noiseMap.value(at: vector_int2(x: Int32(x), y: Int32(y))))		
		}
	}

	return result 
}

func bresenhamLine(start: (x: Int, y: Int), end: (x: Int, y: Int)) -> [(x: Int, y: Int)]{
	var result: [(x: Int, y: Int)] = []
	
	plotLine(start: start, end: end)


	func plotLineLow(start: (x: Int, y: Int), end: (x: Int, y: Int)){
		let dx: Int = end.x - start.x
		var dy: Int = end.y - start.y
		var yi: Int = 1
		if dy < 0 {
			yi = -1
			dy = -dy
		}
		var D: Int = (2 * dy) - dx
		var y: Int = start.y

		for x in start.x..<end.x {
			result.append((x: x, y: y))
			if D > 0 {
				y = y + yi
				D = D + (2 * (dy - dx))
			} else {
				D = D + 2 * dy
			}
		}
	}	
	func plotLineHigh(start: (x: Int, y: Int), end: (x: Int, y: Int)){
		var dx: Int = end.x - start.x
		let dy: Int = end.y - start.y
		var xi: Int = 1
		if dx < 0 {
			xi = -1
			dx = -dx
		}
		var D: Int = (2 * dx) - dy
		var x: Int = start.x

		for y in start.y..<end.y {
			result.append((x: x, y: y))
			if D > 0 {
				x = x + xi
				D = D + (2 * (dx - dy))
			} else {
				D = D + 2 * dx
			}
		}	
	}
	func plotLine(start: (x: Int, y: Int), end: (x: Int, y: Int)){
		if abs(end.y - start.y) < abs(end.x - start.x){
			if start.x > end.x {
				plotLineLow(start: end, end: start)
				result.reverse()
			} else {
				plotLineLow(start: start, end: end)
				//result.reverse()
			}
		} else {
			if start.y > end.y {
				plotLineHigh(start: end, end: start)
				result.reverse()
			} else {
				plotLineHigh(start: start, end: end)
				//result.reverse()
			}
		}
	}
	return result

}

func bresenhamCircle(center: (x: Int, y: Int), radius: Int) -> [(x: Int, y: Int)] {
	var result: [(x: Int, y: Int)] = []
	var x: Int = 0
	var y: Int = radius
	var delta: Int = 1 - 2 * radius
	var error: Int = 0
	while y >= x {
		result.append((x: center.x + x, y: center.y + y))
		result.append((x: center.x + x, y: center.y - y))
		result.append((x: center.x - x, y: center.y + y))
		result.append((x: center.x - x, y: center.y - y))
		result.append((x: center.x + y, y: center.y + x))
		result.append((x: center.x + y, y: center.y - x))
		result.append((x: center.x - y, y: center.y + x))
		result.append((x: center.x - y, y: center.y - x))
		error = 2 * (delta + y) - 1
		if delta < 0 && error <= 0 {
			x += 1
			delta += 2 * x + 1
			continue
		}
		if delta > 0 && error > 0 {
			y -= 1
			delta -= 2 * y + 1
			continue
		}
		x += 1
		y -= 1
		delta += 2 * (x - y)
	}
	return result
}

var world = World(width: 240, height: 200)

let perlinNoiseGrid = perlinNoise(width: world.width, height: world.height, frequency: 15.0, seed: 1)

world.mapMask(mask: perlinNoiseGrid) { value, maskValue in

}

world.mapMask(mask: perlinNoiseGrid) { tile, maskValue in
	if maskValue as! Float >= 0.2 {
		tile.onGround = Object(char: "▓")
	} else {
		//tile.ground.char = "·"
		tile.ground.char = " "
	}
}

var boulder = Object(char: "o")
boulder.spawn((x: 10, y: 10))
boulder.actionOnEnter = { statusLine("You hit a boulder") }
var boulder2 = Object(char: "o")
boulder2.spawn((x: 15, y: 15))


var player = Player(position: (x: 15, y: 15))
var view = View(position: (x: 10, y: 3), width: 60, height: 20)


setlocale(LC_ALL, "") //enable ASCII characters
initscr() // Init window. Must be first
cbreak()
noecho() // Don't echo user input
nonl()  // Disable newline mode
intrflush(stdscr, true) // Prevent flush
keypad(stdscr, true) // Enable function and arrow keys
curs_set(0) //Set cursor to be invisible


view.draw()
statusLine("Game begun")

while true {
	switch getch() {
		case Int32(UnicodeScalar("q").value):
			endwin()
			exit(EX_OK)

		case KEY_LEFT:
			player.move(direction: .left) 
			view.draw()
		case KEY_RIGHT:
			player.move(direction: .right)
			view.draw()
		case KEY_UP:
			player.move(direction: .up)
			view.draw()
		case KEY_DOWN:
			player.move(direction: .down)
			view.draw()
		case Int32(UnicodeScalar("r").value):
			clear()
			view.draw()
			statusLine("Screen refreshed")
		case Int32(UnicodeScalar("t").value):
			clear()
			world.isDay.toggle()
			view.draw()
			statusLine("Time is changed")
		default:
			continue
	}
}
