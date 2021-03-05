---
title: "game - fake snake with ebiten"
date: 2021-01-27T17:41:03+09:00
slug: "game-fake-snake-with-ebiten"
description: "Using Go's ebiten library to create a snake like game, poking fun at Trump's love of Fox News."
keywords: ["go", "ebiten", "game"]
draft: false
tags: ["go", "ebiten", "game"]
math: false
toc: false
---
## Ebiten
Go was never really aimed at being a language for game development, but as with
all established language it has grown large enough to sprout a few game
libraries. 

One that caught my attention was
[Ebiten](https://github.com/hajimehoshi/ebiten) which touts itself as "a dead
simple 2D game library for Go". Having never done any, it felt perfect for
dipping my toes in.

One of the best features of ebiten is its cross platform targeting abilities;
you can create your game and target Windows (as long as no cgo is used), macOS,
Linux, FreeBSD, Android, iOS *and* WebAssembly.

Spending some time with the community and seeing how responsive Hajime was
prompted me to sponsor him and the project.

## The Game
I had quite a few ideas for games that I would love to develop, but it seemed
appropriate to start with something simple and build up some domain knowledge
first. The game chosen was the classic,
[snake](https://en.wikipedia.org/wiki/Snake_(video_game_genre)). 

From a programming perspective games are based on an event loop, the game
initialises itself and then within its loop processes input and state before
drawing the state to the display. Ebiten encapsulates this with its interface:

```go
type Game struct {}

// update the logical state
func (g *Game) Update() error {}

// render the state to screen
func (g *Game) Draw(...) {}
```

### State
For low complexity games (i.e. this) where the Update function can process in a
timely manner there is no need to use any concurrency, which means that we can
modify our state without any synchronisation. 

We need to store the following:

* **Grid**, breakdown the screen in to a grid and store what is in each cell
* **Snake**, an array of cell indexes describing the length and location
* **Food**, index describing the location of the food (traditionally an apple)

On each update we need to:

1. Detect any input and update the head of the snake to reflect any change
2. If there is no food present on the screen, generate some
	* When creating food, make sure that it isn't spawned on the snake
3. Loop through the cells containing the snake and:
	* Calculate the cell's next cell based on the direction of the last checked
	  cell, or if the head, its own direction.
	* If a wall or snake collision is detected trigger GameOver.
	* If food is detected, add a segment (the food becomes the head).
	* Otherwise move the snake by moving the segment to its next position.
4. Draw (see below)

### Input
The snake can only move in 4 directions, and the player is only able to effect
which direction the snake moves and not its speed. Therefore we need to listen
for input changing the snakes direction, ebiten offers some nice utilities for
listening for input and detecting what the input was. 

Our input handler is very
simple, only adding some conditionals to prevent unnatural movements, namely
back on itself:

```go
func (g *Game) handleInput() {
	headCell := g.grid[g.snake[len(g.snake)-1]]

	if ebiten.IsKeyPressed(ebiten.KeyUp) {
		if headCell.direction != directionDown {
			headCell.direction = directionUp
		}
	} else if ebiten.IsKeyPressed(ebiten.KeyDown) {
		if headCell.direction != directionUp {
			headCell.direction = directionDown
		}
	} else if ebiten.IsKeyPressed(ebiten.KeyLeft) {
		if headCell.direction != directionRight {
			headCell.direction = directionLeft
		}
	} else if ebiten.IsKeyPressed(ebiten.KeyRight) {
		if headCell.direction != directionLeft {
			headCell.direction = directionRight
		}
	}
}
```

### Art
I have always enjoyed drawing and felt like I would be able to have some fun
with this (turns out drawing with a mouse isn't so fun). I discovered
[asperite](https://www.aseprite.org/) which is a fantastic and incredibly cute
piece of software. 

Being topical at the time I decided to theme the game with
Donanld Trump, his for Fox News and the handily snake rhyming word fake.

![Splash screen](/img/fake-splash.png)

![In Game](/img/fake-play.png)
