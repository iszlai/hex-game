package com.hexgame.screen

import java.util.Timer

import com.badlogic.gdx.{Gdx, Screen}
import com.badlogic.gdx.graphics.Texture
import com.badlogic.gdx.graphics.g2d.SpriteBatch
import com.hexgame.Hex
import com.hexgame.model.HiveGrid

/**
  * Created by leheli on 2016.08.01..
  */
class LevelScreen extends Screen {
  private val app: Hex = null
  private val batch: SpriteBatch = null
  private val img: Texture = null
  private val row: HiveGrid = null
  private val hex: Deck = null
  private val lvl: Int = 0

  def this (app: Hex, lvl: Int) {
  this ()
  this.app = app
  this.lvl = lvl
  batch = new SpriteBatch
  img = new Texture ("hex.png")
  row = new HiveGrid (5, img, lvl)
  hex = new Deck
  hex.setX (1000)
  System.out.println (Gdx.graphics.getWidth)
  System.out.println (Gdx.graphics.getHeight)
}


  private def update {
  if (Gdx.input.justTouched) {
  val x: Float = Gdx.input.getX
  val y: Float = Gdx.graphics.getHeight - Gdx.input.getY

  import scala.collection.JavaConversions._

  for (sprite <- row.list) {
  if (sprite.getBoundingRectangle.contains (x, y) && sprite.clickable) {
  sprite.clickable = false
  sprite.setColor (Color.RED)
  sprite.setTexture (hex.getTexture)
  val neighbour: GridLocation = sprite.location.getNeighbour (hex.side)
  val gameObject: GameObject = row.grid.get (neighbour)
  if (gameObject != null) {
  gameObject.setColor (Color.GREEN)
  gameObject.walkAble = true
}
  hex.next
  if (com.hexgame.utils.Utils.isGameOver (row.start, row.end) ) {
  Timer.schedule (new Timer.Task () {
  def run {
  app.setScreen (new StarsScreen (app, lvl + 1) )
}
}, 1)
}
}
}
}
}

  def show {
}

  def render (delta: Float) {
  Gdx.gl.glClearColor (0.81f, 0.85f, 0.86f, 1)
  Gdx.gl.glClear (GL20.GL_COLOR_BUFFER_BIT)
  batch.begin
  row.draw (batch)
  hex.draw (batch)
  batch.end
  update
}

  def resize (width: Int, height: Int) {
}

  def pause {
}

  def resume {
}

  def hide {
}

  def dispose {
  batch.dispose
  img.dispose
}
}
